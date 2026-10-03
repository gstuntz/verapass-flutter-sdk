import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import '../detection/blaze_face_decoder.dart';
import '../detection/face.dart';
import '../detection/frame.dart';
import '../flow/ports.dart';

/// BlazeFace short-range (the model the web SDK uses) on the open-source TensorFlow Lite
/// runtime: on-device, no network, no telemetry.
class TfliteFaceDetector implements FaceDetector {
  TfliteFaceDetector._(this._interpreter);

  static const asset = 'packages/facera/assets/blaze_face_short_range.tflite';

  static Future<TfliteFaceDetector> load() async {
    final interpreter = await Interpreter.fromAsset(asset, options: InterpreterOptions()..threads = 2);
    interpreter.allocateTensors();
    return TfliteFaceDetector._(interpreter);
  }

  final Interpreter _interpreter;
  final _decoder = BlazeFaceDecoder();

  @override
  Future<List<ObservedFace>> detect(CameraFrame frame) async {
    final (input, letterbox) = frame.toModelInput(BlazeFaceDecoder.inputSize);
    _interpreter.getInputTensor(0).data = input.buffer.asUint8List();
    _interpreter.invoke();
    final regressors = _floats(_interpreter.getOutputTensor(0).data);
    final scores = _floats(_interpreter.getOutputTensor(1).data);
    return [for (final face in _decoder.decode(regressors, scores)) _toFrame(face, letterbox)];
  }

  static Float32List _floats(Uint8List bytes) => Float32List.fromList(bytes.buffer.asFloat32List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 4));

  /// From the model's letterboxed square to the upright frame's own 0..1 coordinates.
  static ObservedFace _toFrame(ObservedFace face, Letterbox l) {
    NormalizedPoint? point(NormalizedPoint? p) => p == null ? null : NormalizedPoint(l.mapX(p.x), l.mapY(p.y));
    final b = face.box;
    return ObservedFace(
      box: NormalizedBox(l.mapX(b.x), l.mapY(b.y), l.mapWidth(b.width), l.mapHeight(b.height)),
      score: face.score,
      eyeA: point(face.eyeA),
      eyeB: point(face.eyeB),
      nose: point(face.nose),
    );
  }

  @override
  void close() => _interpreter.close();
}
