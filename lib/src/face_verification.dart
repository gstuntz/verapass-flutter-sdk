import 'package:flutter/material.dart';

import 'errors.dart';
import 'flow/verification_controller.dart';
import 'options.dart';
import 'result.dart';
import 'ui/verification_view.dart';

/// Face verification in one call: opens a full-screen verification, and completes when the
/// user leaves it.
///
/// ```dart
/// final result = await FaceVerification.start(
///   context,
///   apiUrl: Uri.parse('https://api.example.com'),
///   clientTokenProvider: () => myBackend.startFaceVerification(), // returns "fpct_..."
///   options: const FaceVerificationOptions(voice: true),
/// );
/// if (result.passed) await myBackend.confirmFaceVerification(result.sessionId);
/// ```
///
/// There is no API key here on purpose: anything inside an app can be extracted. Your server
/// creates the session with its secret API key and hands the app a client token that can
/// complete only that one session.
abstract final class FaceVerification {
  static bool _open = false;

  /// Returns the result the user saw when they closed it. Throws [FaceVerificationException]
  /// if they left without one (code [FaceVerificationErrorCode.cancelled], or the error they
  /// saw, e.g. [FaceVerificationErrorCode.cameraDenied]).
  ///
  /// Pass [clientToken] (one session) or [clientTokenProvider] (called for each attempt, so
  /// the user can try again after a failed verification).
  static Future<FaceVerificationResult> start(
    BuildContext context, {
    required Uri apiUrl,
    String? clientToken,
    Future<String> Function()? clientTokenProvider,
    FaceVerificationOptions options = const FaceVerificationOptions(),
  }) async {
    if ((clientToken == null) == (clientTokenProvider == null)) {
      throw const FaceVerificationException(FaceVerificationErrorCode.configurationError, 'Pass exactly one of clientToken and clientTokenProvider');
    }
    if (clientToken != null) VerificationController.checkToken(clientToken); // fail fast for developers
    if (_open) {
      throw const FaceVerificationException(FaceVerificationErrorCode.configurationError, 'A verification is already open');
    }
    _open = true;
    try {
      final outcome = await Navigator.of(context).push<FaceVerificationOutcome>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (routeContext) => FaceVerificationView(
            apiUrl: apiUrl,
            clientToken: clientToken,
            clientTokenProvider: clientTokenProvider,
            options: options,
            onClose: (outcome) => Navigator.of(routeContext).pop(outcome),
          ),
        ),
      );
      if (outcome?.result case final result?) return result;
      throw outcome?.error ?? const FaceVerificationException(FaceVerificationErrorCode.cancelled, 'The verification was closed');
    } finally {
      _open = false;
    }
  }
}
