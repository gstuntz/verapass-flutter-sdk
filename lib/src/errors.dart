/// Every failure the SDK reports, with a stable [code]. Messages are for developers.
enum FaceVerificationErrorCode {
  /// Invalid options (for example an API key passed as the client token).
  configurationError,

  /// The user (or a device policy) refused camera access.
  cameraDenied,

  /// No usable camera was found (for example the requested lens doesn't exist).
  cameraNotFound,

  /// The camera exists but couldn't be started.
  cameraUnavailable,

  /// Your `clientToken` callback failed: your server couldn't start a session.
  sessionUnavailable,

  /// The client token is unknown or expired.
  invalidToken,

  /// The session already has a result; create a new one.
  sessionUsed,

  /// The session expired before it was completed.
  sessionExpired,

  /// The session checks face match, but your server hasn't uploaded its reference photo.
  referenceMissing,

  /// The session skips a check listed in [FaceVerificationOptions.checks].
  checksMismatch,

  /// The user didn't complete a step in time (nothing was submitted).
  stepTimeout,

  /// The API couldn't be reached.
  networkError,

  /// The API answered with a server error.
  serviceUnavailable,

  /// The API refused the submitted photos.
  requestRejected,

  /// The user closed the verification.
  cancelled;

  /// Whether the same session can be tried again on this device.
  bool get retryable => switch (this) {
    cameraDenied || cameraNotFound || cameraUnavailable || stepTimeout || sessionUnavailable || networkError || serviceUnavailable || requestRejected => true,
    _ => false,
  };
}

class FaceVerificationException implements Exception {
  const FaceVerificationException(this.code, this.message, [this.cause]);

  final FaceVerificationErrorCode code;
  final String message;
  final Object? cause;

  bool get retryable => code.retryable;

  @override
  String toString() => 'FaceVerificationException(${code.name}): $message';
}
