/// What a session verifies, chosen by your server when it creates the session (within what
/// its API key allows).
enum FaceCheck {
  /// Head-turn challenge and anti-spoofing on the captured photos.
  liveness,

  /// Compare the captured face with the reference photo your server uploaded.
  faceMatch;

  String get wireName => switch (this) {
    liveness => 'liveness',
    faceMatch => 'face_match',
  };

  static FaceCheck? parse(String value) => switch (value) {
    'liveness' => liveness,
    'face_match' => faceMatch,
    _ => null,
  };
}

/// Session statuses, as the API reports them.
enum FaceSessionStatus {
  created,
  processing,
  livenessPassed,
  livenessFailed,
  verificationPassed,
  verificationFailed,
  expired,
  failed;

  static FaceSessionStatus parse(String value) => switch (value) {
    'created' => created,
    'processing' => processing,
    'liveness_passed' => livenessPassed,
    'liveness_failed' => livenessFailed,
    'verification_passed' => verificationPassed,
    'verification_failed' => verificationFailed,
    'expired' => expired,
    _ => failed,
  };

  bool get isFinal => switch (this) {
    livenessFailed || verificationPassed || verificationFailed || expired || failed => true,
    _ => false,
  };
}

/// Why a session didn't pass, as far as the user's device may know.
enum FaceFailureCode {
  noFace,
  multipleFaces,
  faceTooSmall,
  lowConfidence,
  faceOutOfFrame,
  notFrontal,
  wrongPose,
  invalidImage,
  livenessFailed,
  notMatched,
  referenceUnusable,
  expired,
  serviceUnavailable,
  failed;

  static FaceFailureCode? parse(String? value) => switch (value) {
    null => null,
    'no_face' => noFace,
    'multiple_faces' => multipleFaces,
    'face_too_small' => faceTooSmall,
    'low_confidence' => lowConfidence,
    'face_out_of_frame' => faceOutOfFrame,
    'not_frontal' => notFrontal,
    'wrong_pose' => wrongPose,
    'invalid_image' => invalidImage,
    'liveness_failed' => livenessFailed,
    'not_matched' => notMatched,
    'reference_unusable' => referenceUnusable,
    'expired' => expired,
    'service_unavailable' => serviceUnavailable,
    _ => failed,
  };
}

/// The outcome shown to the user. **Not proof**: an app can be tampered with. Your server
/// must read the session with its API key (GET /api/v1/sessions/{id}) before acting on it.
class FaceVerificationResult {
  const FaceVerificationResult({
    required this.sessionId,
    required this.status,
    this.checks = const {FaceCheck.liveness, FaceCheck.faceMatch},
    this.failureCode,
    this.failureFrame,
  });

  final String sessionId;

  /// What the session verified.
  final Set<FaceCheck> checks;
  final FaceSessionStatus status;
  final FaceFailureCode? failureCode;

  /// Which photo (0 = facing the camera) the failure is about, when known.
  final int? failureFrame;

  /// True only when every check of the session passed.
  bool get passed => status == FaceSessionStatus.verificationPassed;

  @override
  String toString() => 'FaceVerificationResult($sessionId, ${status.name}${failureCode == null ? '' : ', ${failureCode!.name}'})';
}
