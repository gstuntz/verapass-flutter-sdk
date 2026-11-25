import 'dart:math' as math;

import '../api/client_api.dart';

/// The countdown appears only in the last 2 minutes, so a normal run isn't rushed.
const countdownFrom = Duration(minutes: 2);

/// When the session expires, on this device's clock. The server sends `expires_in` (seconds
/// left, its own clock) so a wrong device clock doesn't matter; older servers only send
/// `expires_at`.
DateTime? deadlineFrom(ClientSession session, DateTime now) {
  final seconds = session.expiresIn;
  if (seconds != null) return now.add(Duration(seconds: math.max(0, seconds)));
  return session.expiresAt;
}

/// m:ss, rounded up so it never reads 0:00 while time is left.
String formatClock(Duration left) {
  final seconds = math.max(0, (left.inMilliseconds / 1000).ceil());
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Whole minutes for the intro ("You have 9 minutes"): rounded down, at least 1.
int minutesLeft(Duration left) => math.max(1, left.inMinutes);
