import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:verapass/src/detection/blaze_face_decoder.dart';
import 'package:verapass/src/detection/frame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Raw model outputs for fixture photos, recorded with the reference implementation
/// (LiteRT + MediaPipe's anchor/decoding/NMS rules), and the faces it decoded.
(Float32List, Float32List, List<Map<String, dynamic>>) fixture(String name) {
  final bytes = File('test/fixtures/blaze_$name.bin').readAsBytesSync();
  final floats = bytes.buffer.asFloat32List();
  final regressors = Float32List.fromList(floats.sublist(0, 896 * 16));
  final scores = Float32List.fromList(floats.sublist(896 * 16));
  final expected = (jsonDecode(File('test/fixtures/blaze_$name.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
  return (regressors, scores, expected);
}

void main() {
  group('BlazeFace decoder', () {
    final decoder = BlazeFaceDecoder();

    for (final name in ['frontal', 'left', 'right', 'pair', 'empty']) {
      test('matches the reference decoding: $name', () {
        final (regressors, scores, expected) = fixture(name);
        final faces = decoder.decode(regressors, scores);
        expect(faces, hasLength(expected.length));
        for (final (i, face) in faces.indexed) {
          final want = expected[i];
          final box = (want['box'] as List).cast<num>();
          expect(face.score, closeTo(want['score'] as num, 1e-4));
          expect([face.box.x, face.box.y, face.box.width, face.box.height], [for (final v in box) closeTo(v, 1e-4)]);
          final kp = (want['kp'] as List).cast<List>();
          expect(face.eyeA!.x, closeTo(kp[0][0] as num, 1e-4));
          expect(face.nose!.y, closeTo(kp[2][1] as num, 1e-4));
        }
      });
    }

    test('measures head turns with the server convention (positive = person\'s left)', () {
      double yaw(String name) {
        final (r, s, _) = fixture(name);
        return decoder.decode(r, s).single.yaw!;
      }

      expect(yaw('frontal').abs(), lessThan(0.08));
      expect(yaw('left'), greaterThan(0.28));
      expect(yaw('right'), lessThan(-0.28));
    });
  });

  group('CameraFrame orientation', () {
    // A 3x2 RGB frame with distinct pixels; letters name them as laid out in the raw buffer:
    //   a b c
    //   d e f
    final raw = Uint8List.fromList([for (var i = 1; i <= 6; i++) ...[i * 10, 0, 0]]);
    CameraFrame frame({int rotation = 0, bool mirrored = false}) => CameraFrame(
      width: 3,
      height: 2,
      format: FrameFormat.rgb888,
      planes: [FramePlane(raw, bytesPerRow: 9, bytesPerPixel: 3)],
      rotationDegrees: rotation,
      mirrored: mirrored,
    );

    List<List<int>> upright(CameraFrame f) {
      final image = img.decodeJpg(f.toJpeg(quality: 100))!;
      return [for (var y = 0; y < image.height; y++) [for (var x = 0; x < image.width; x++) (image.getPixel(x, y).r / 10).round()]];
    }

    test('no rotation', () => expect(upright(frame()), [[1, 2, 3], [4, 5, 6]]));
    test('rotates clockwise by the sensor angle (Android 90)', () => expect(upright(frame(rotation: 90)), [[4, 1], [5, 2], [6, 3]]));
    test('rotates clockwise by the sensor angle (Android front camera 270)', () => expect(upright(frame(rotation: 270)), [[3, 6], [2, 5], [1, 4]]));
    test('un-mirrors mirrored frames (iOS front camera)', () => expect(upright(frame(mirrored: true)), [[3, 2, 1], [6, 5, 4]]));

    test('letterboxes into the model input, preserving aspect', () {
      final (input, box) = frame().toModelInput(6);
      expect(box.width, 1.0);
      expect(box.height, closeTo(4 / 6, 1e-9)); // 3x2 -> 6x4 inside 6x6
      expect(box.y, closeTo(1 / 6, 1e-9));
      expect(input[0], -1.0); // padding is black (-1)
      final firstPixelRow = 1; // after one row of padding
      expect(input[(firstPixelRow * 6) * 3], closeTo(10 / 127.5 - 1, 1e-6));
    });
  });

  test('YUV 4:2:0 converts to RGB (white and black)', () {
    // 2x2 luma, 1x1 chroma (neutral): top row white, bottom row black.
    final frame = CameraFrame(
      width: 2,
      height: 2,
      format: FrameFormat.yuv420,
      planes: [
        FramePlane(Uint8List.fromList([255, 255, 0, 0]), bytesPerRow: 2),
        FramePlane(Uint8List.fromList([128]), bytesPerRow: 1),
        FramePlane(Uint8List.fromList([128]), bytesPerRow: 1),
      ],
    );
    final image = img.decodeJpg(frame.toJpeg(quality: 100))!;
    expect(image.getPixel(0, 0).r, greaterThan(240));
    expect(image.getPixel(0, 1).r, lessThan(15));
  });
}
