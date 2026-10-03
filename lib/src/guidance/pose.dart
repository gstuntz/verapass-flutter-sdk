import '../detection/face.dart';

/// The pose a step asks for. Turns are the person's own left and right.
enum StepPose {
  frontal,
  turnLeft,
  turnRight;

  static StepPose fromAction(String action) => switch (action) {
    'turn_left' => turnLeft,
    'turn_right' => turnRight,
    _ => throw ArgumentError('Unknown challenge action: $action'),
  };
}

/// What to tell the user about the current frame. [holdStill] means the frame is good.
enum Guidance { noFace, multipleFaces, moveCloser, moveBack, centerFace, lookStraight, turnLeft, turnRight, holdStill }

/// Client-side thresholds. A little stricter than the server where it matters (frontal
/// 0.08 vs 0.12) and with margin for the two landmark models disagreeing (turn 0.28 vs the
/// server's 0.25: on our fixtures this detector measures ~0.03 less than the server's).
/// The server re-checks every frame and is the only authority.
class PoseThresholds {
  const PoseThresholds({
    this.frontalMax = 0.08,
    this.turnMin = 0.28,
    this.minFaceWidth = 0.22,
    this.maxFaceWidth = 0.85,
    this.edgeTolerance = 0.05,
    this.centerX = (0.25, 0.75),
    this.centerY = (0.2, 0.8),
  });

  final double frontalMax;
  final double turnMin;

  /// Face box width as a fraction of the (portrait) frame width.
  final double minFaceWidth;
  final double maxFaceWidth;
  final double edgeTolerance;
  final (double, double) centerX;
  final (double, double) centerY;
}

bool poseMatches(double yaw, StepPose pose, [PoseThresholds t = const PoseThresholds()]) => switch (pose) {
  StepPose.frontal => yaw.abs() <= t.frontalMax,
  StepPose.turnLeft => yaw >= t.turnMin,
  StepPose.turnRight => yaw <= -t.turnMin,
};

Guidance requestedGuidance(StepPose pose) => switch (pose) {
  StepPose.frontal => Guidance.lookStraight,
  StepPose.turnLeft => Guidance.turnLeft,
  StepPose.turnRight => Guidance.turnRight,
};

/// The guidance for one frame (faces in normalized coordinates of the upright frame).
Guidance evaluateFrame(List<ObservedFace> faces, StepPose pose, [PoseThresholds t = const PoseThresholds()]) {
  if (faces.isEmpty) return Guidance.noFace;
  if (faces.length > 1) return Guidance.multipleFaces;
  final face = faces.single;
  final box = face.box;
  if (box.width < t.minFaceWidth) return Guidance.moveCloser;
  if (box.width > t.maxFaceWidth) return Guidance.moveBack;
  final mx = box.width * t.edgeTolerance, my = box.height * t.edgeTolerance;
  if (box.x < -mx || box.y < -my || box.x + box.width > 1 + mx || box.y + box.height > 1 + my) return Guidance.centerFace;
  if (box.centerX < t.centerX.$1 || box.centerX > t.centerX.$2 || box.centerY < t.centerY.$1 || box.centerY > t.centerY.$2) {
    return Guidance.centerFace;
  }
  final yaw = face.yaw;
  if (yaw != null && poseMatches(yaw, pose, t)) return Guidance.holdStill;
  return requestedGuidance(pose);
}

/// Requires a pose to be held for [hold] before capture, so one noisy frame never triggers it.
class HoldTracker {
  HoldTracker(this.hold);
  final Duration hold;
  Duration? _since;

  /// Feed one frame's verdict at time [now]; true once the pose has been held long enough.
  bool update(bool good, Duration now) {
    if (!good) {
      _since = null;
      return false;
    }
    _since ??= now;
    return now - _since! >= hold;
  }

  double progress(Duration now) {
    final since = _since;
    if (since == null) return 0;
    return ((now - since).inMicroseconds / hold.inMicroseconds).clamp(0.0, 1.0);
  }

  void reset() => _since = null;
}
