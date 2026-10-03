import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../detection/frame.dart';
import '../errors.dart';
import '../flow/ports.dart';
import '../options.dart';

/// Frames from the device camera via the official `camera` plugin. Video only: no audio,
/// so no microphone permission is ever requested.
///
/// Orientation (the screen is held in portrait during verification):
/// - iOS delivers front-camera frames upright and **mirrored** (the plugin mirrors the
///   capture connection), so they are un-mirrored here.
/// - Android delivers frames in sensor orientation, unmirrored; they are rotated upright by
///   the camera's sensor angle.
class CameraFrameSource implements FrameSource {
  CameraFrameSource(this.options);

  final FaceCameraOptions options;
  CameraController? _controller;
  final _frames = StreamController<CameraFrame>.broadcast();
  bool _closed = false;

  @override
  Stream<CameraFrame> get frames => _frames.stream;

  @override
  bool get previewMirrored => _controller?.description.lensDirection == CameraLensDirection.front;

  @override
  double? get previewAspectRatio {
    final value = _controller?.value;
    if (value == null || !value.isInitialized) return null;
    return 1 / value.aspectRatio; // the plugin reports landscape width / height
  }

  @override
  Future<void> open() async {
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException catch (e) {
      throw _map(e);
    }
    final wanted = options.lens == FaceCameraLens.front ? CameraLensDirection.front : CameraLensDirection.back;
    final description = cameras.where((c) => c.lensDirection == wanted).firstOrNull;
    if (description == null) {
      throw FaceVerificationException(FaceVerificationErrorCode.cameraNotFound, 'No ${options.lens.name} camera on this device');
    }
    final controller = _controller = CameraController(
      description,
      switch (options.resolution) {
        FaceCameraResolution.medium => ResolutionPreset.medium,
        FaceCameraResolution.high => ResolutionPreset.high,
        FaceCameraResolution.veryHigh => ResolutionPreset.veryHigh,
      },
      enableAudio: false,
      imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
    );
    try {
      await controller.initialize();
      if (_closed) return;
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await controller.startImageStream(_onImage);
    } on CameraException catch (e) {
      throw _map(e);
    }
  }

  void _onImage(CameraImage image) {
    if (_closed || _frames.isClosed) return;
    final front = _controller?.description.lensDirection == CameraLensDirection.front;
    final sensor = _controller?.description.sensorOrientation ?? 0;
    _frames.add(
      CameraFrame(
        width: image.width,
        height: image.height,
        format: image.format.group == ImageFormatGroup.bgra8888 ? FrameFormat.bgra8888 : FrameFormat.yuv420,
        planes: [for (final p in image.planes) FramePlane(p.bytes, bytesPerRow: p.bytesPerRow, bytesPerPixel: p.bytesPerPixel ?? 1)],
        rotationDegrees: Platform.isIOS ? 0 : sensor,
        mirrored: Platform.isIOS && front,
      ),
    );
  }

  @override
  Widget buildPreview(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return const SizedBox.expand();
    return CameraPreview(controller);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final controller = _controller;
    _controller = null;
    try {
      if (controller != null && controller.value.isStreamingImages) await controller.stopImageStream();
    } catch (_) {
      // already stopped
    }
    await controller?.dispose();
    // Not awaited: a broadcast stream's close() never completes once its listener has
    // cancelled, which would freeze the flow right before submitting.
    unawaited(_frames.close());
  }

  static FaceVerificationException _map(CameraException e) => switch (e.code) {
    'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' || 'CameraAccessRestricted' || 'cameraPermission' => FaceVerificationException(FaceVerificationErrorCode.cameraDenied, e.description ?? e.code, e),
    'cameraNotFound' || 'noCamerasAvailable' => FaceVerificationException(FaceVerificationErrorCode.cameraNotFound, e.description ?? e.code, e),
    _ => FaceVerificationException(FaceVerificationErrorCode.cameraUnavailable, '${e.code}: ${e.description}', e),
  };
}
