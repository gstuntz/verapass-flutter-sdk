/// Test hooks: run the real verification flow and UI with your own frames instead of the
/// camera (e.g. in integration tests on a simulator, which has no camera).
///
/// Not for production code.
library;

import 'package:flutter/foundation.dart';

import 'src/flow/ports.dart';
import 'src/ui/default_dependencies.dart';
import 'src/ui/verification_view.dart' as view;

export 'src/detection/face.dart' show NormalizedBox, NormalizedPoint, ObservedFace;
export 'src/detection/frame.dart' show CameraFrame, FrameFormat, FramePlane, encodeFrameJpeg;
export 'src/flow/ports.dart' show FaceDetector, FlowDependencies, FrameSource, Speaker;
export 'src/platform/tflite_face_detector.dart' show TfliteFaceDetector;
export 'src/platform/tts_speaker.dart' show SilentSpeaker, TtsSpeaker;

/// The production dependencies, to override only some of them.
FlowDependencies get defaultDependencies => defaultFlowDependencies;

/// Replace the platform dependencies for every verification started after this call;
/// `null` restores the real ones.
@visibleForTesting
set faceVerificationDependencies(FlowDependencies? dependencies) => view.debugFlowDependenciesOverride = dependencies;
