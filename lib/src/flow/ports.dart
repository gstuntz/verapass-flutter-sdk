import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../api/client_api.dart';
import '../detection/face.dart';
import '../detection/frame.dart';
import '../options.dart';

/// Where camera frames come from. The real one uses the `camera` plugin; tests feed images.
abstract class FrameSource {
  /// Opens the camera (asking for permission if needed). Throws FaceVerificationException
  /// with cameraDenied / cameraNotFound / cameraUnavailable.
  Future<void> open();

  /// Frames as they arrive, until [close]. Frames may be dropped while one is being analyzed.
  Stream<CameraFrame> get frames;

  /// The live preview. [previewMirrored] says whether it is shown mirrored (selfie style).
  Widget buildPreview(BuildContext context);
  bool get previewMirrored;

  /// Width / height of the upright preview (e.g. 9/16 for a portrait 720p stream), once open.
  double? get previewAspectRatio;

  /// Releases the camera. Safe to call more than once.
  Future<void> close();
}

/// Finds faces in a frame (normalized coordinates of the upright, unmirrored frame).
abstract class FaceDetector {
  Future<List<ObservedFace>> detect(CameraFrame frame);
  void close();
}

/// Speaks instructions. Disabled or unavailable speech is a no-op that completes at once.
abstract class Speaker {
  bool get enabled;

  /// Completes when the text has been spoken (or skipped). An instruction replaces whatever
  /// is being said; a hint is skipped while an instruction is still playing.
  Future<void> say(String text, {bool instruction = false});
  Future<void> stop();
}

/// Everything the flow uses from the platform, replaceable in tests.
class FlowDependencies {
  const FlowDependencies({
    required this.frameSource,
    required this.detector,
    required this.speaker,
    required this.encodeJpeg,
    this.api = _defaultApi,
  });

  final FrameSource Function(FaceCameraOptions options) frameSource;

  /// Null result means detection is unavailable: steps fall back to a countdown.
  final Future<FaceDetector?> Function() detector;
  final Speaker Function(bool enabled, String locale) speaker;
  final Future<Uint8List> Function(CameraFrame frame) encodeJpeg;
  final ClientApi Function(Uri apiUrl, String token) api;

  static ClientApi _defaultApi(Uri apiUrl, String token) => ClientApi(apiUrl, token);
}
