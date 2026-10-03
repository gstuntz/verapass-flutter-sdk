import 'package:flutter/foundation.dart';

import '../detection/frame.dart';
import '../flow/ports.dart';
import '../platform/camera_frame_source.dart';
import '../platform/tflite_face_detector.dart';
import '../platform/tts_speaker.dart';

/// The real device implementations: camera plugin, TensorFlow Lite, platform text-to-speech,
/// and JPEG encoding in a background isolate (so the UI never stutters).
final defaultFlowDependencies = FlowDependencies(
  frameSource: CameraFrameSource.new,
  detector: TfliteFaceDetector.load,
  speaker: TtsSpeaker.create,
  encodeJpeg: (frame) => compute(encodeFrameJpeg, frame),
);
