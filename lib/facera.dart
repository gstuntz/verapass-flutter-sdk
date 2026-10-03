/// Face verification for Flutter apps: camera, on-device guidance, the liveness check, and
/// the result, against the Face Platform API.
///
/// Start with [FaceVerification.start], or embed [FaceVerificationView].
library;

export 'src/errors.dart' show FaceVerificationErrorCode, FaceVerificationException;
export 'src/face_verification.dart' show FaceVerification;
export 'src/guidance/pose.dart' show Guidance;
export 'src/l10n/messages.dart' show FaceVerificationMessages;
export 'src/options.dart' show FaceCameraLens, FaceCameraOptions, FaceCameraResolution, FaceVerificationOptions, FaceVerificationTheme;
export 'src/result.dart' show FaceFailureCode, FaceSessionStatus, FaceVerificationResult;
export 'src/ui/verification_view.dart' show FaceVerificationOutcome, FaceVerificationView;
