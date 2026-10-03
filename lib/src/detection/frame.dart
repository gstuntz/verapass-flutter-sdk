import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Pixel layouts the camera plugins deliver (Android: YUV 4:2:0; iOS: BGRA), plus RGB for
/// frames that don't come from a camera (tests).
enum FrameFormat { yuv420, bgra8888, rgb888 }

class FramePlane {
  const FramePlane(this.bytes, {required this.bytesPerRow, this.bytesPerPixel = 1});
  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
}

/// One camera frame as delivered, with what it takes to make it upright and unmirrored:
/// rotate clockwise by [rotationDegrees], then un-mirror if [mirrored].
///
/// Everything downstream (detection, guidance, the photos sent to the server) works on
/// that upright, unmirrored view, the same convention the server's head-turn check uses.
class CameraFrame {
  const CameraFrame({
    required this.width,
    required this.height,
    required this.format,
    required this.planes,
    this.rotationDegrees = 0,
    this.mirrored = false,
  });

  final int width;
  final int height;
  final FrameFormat format;
  final List<FramePlane> planes;
  final int rotationDegrees;
  final bool mirrored;

  bool get _quarterTurn => rotationDegrees % 180 != 0;
  int get uprightWidth => _quarterTurn ? height : width;
  int get uprightHeight => _quarterTurn ? width : height;

  /// The raw pixel (x, y) that appears at upright, unmirrored position (u, v).
  (int, int) _sourceOf(int u, int v) {
    final uw = uprightWidth;
    final un = mirrored ? uw - 1 - u : u; // undo mirroring in upright space
    return switch (rotationDegrees % 360) {
      90 => (v, height - 1 - un),
      180 => (width - 1 - un, height - 1 - v),
      270 => (width - 1 - v, un),
      _ => (un, v),
    };
  }

  /// RGB of raw pixel (x, y).
  (int, int, int) _rgbAt(int x, int y) {
    switch (format) {
      case FrameFormat.bgra8888:
        final p = planes[0];
        final i = y * p.bytesPerRow + x * 4;
        return (p.bytes[i + 2], p.bytes[i + 1], p.bytes[i]);
      case FrameFormat.rgb888:
        final p = planes[0];
        final i = y * p.bytesPerRow + x * 3;
        return (p.bytes[i], p.bytes[i + 1], p.bytes[i + 2]);
      case FrameFormat.yuv420:
        final yp = planes[0], up = planes[1], vp = planes[2];
        final yy = yp.bytes[y * yp.bytesPerRow + x];
        final ci = (y >> 1) * up.bytesPerRow + (x >> 1) * up.bytesPerPixel;
        final u = up.bytes[ci] - 128;
        final v = vp.bytes[(y >> 1) * vp.bytesPerRow + (x >> 1) * vp.bytesPerPixel] - 128;
        int c(double value) => value < 0 ? 0 : (value > 255 ? 255 : value.round());
        return (c(yy + 1.402 * v), c(yy - 0.344136 * u - 0.714136 * v), c(yy + 1.772 * u));
    }
  }

  /// The model input: upright, unmirrored, letterboxed into [size]x[size], RGB in [-1, 1]
  /// (nearest-neighbour sampling, plenty for detection). Returns the input and the
  /// letterbox, to map detections back to frame coordinates.
  (Float32List, Letterbox) toModelInput(int size) {
    final uw = uprightWidth, uh = uprightHeight;
    final scale = size / (uw > uh ? uw : uh);
    final cw = (uw * scale).round(), ch = (uh * scale).round();
    final ox = (size - cw) ~/ 2, oy = (size - ch) ~/ 2;
    final input = Float32List(size * size * 3)..fillRange(0, size * size * 3, -1.0);
    for (var ty = 0; ty < ch; ty++) {
      final v = ((ty + 0.5) / scale).floor().clamp(0, uh - 1);
      for (var tx = 0; tx < cw; tx++) {
        final u = ((tx + 0.5) / scale).floor().clamp(0, uw - 1);
        final (sx, sy) = _sourceOf(u, v);
        final (r, g, b) = _rgbAt(sx, sy);
        final i = ((ty + oy) * size + tx + ox) * 3;
        input[i] = r / 127.5 - 1;
        input[i + 1] = g / 127.5 - 1;
        input[i + 2] = b / 127.5 - 1;
      }
    }
    return (input, Letterbox(ox / size, oy / size, cw / size, ch / size));
  }

  /// A JPEG of the upright, unmirrored frame (what the server expects). CPU-heavy: call
  /// it from a background isolate (see [encodeFrameJpeg]).
  Uint8List toJpeg({int quality = 90}) {
    final uw = uprightWidth, uh = uprightHeight;
    final image = img.Image(width: uw, height: uh);
    for (var v = 0; v < uh; v++) {
      for (var u = 0; u < uw; u++) {
        final (sx, sy) = _sourceOf(u, v);
        final (r, g, b) = _rgbAt(sx, sy);
        image.setPixelRgb(u, v, r, g, b);
      }
    }
    return img.encodeJpg(image, quality: quality);
  }
}

/// Where the frame sits inside the square model input (fractions of the input size).
class Letterbox {
  const Letterbox(this.x, this.y, this.width, this.height);
  final double x;
  final double y;
  final double width;
  final double height;

  double mapX(double modelX) => (modelX - x) / width;
  double mapY(double modelY) => (modelY - y) / height;
  double mapWidth(double modelWidth) => modelWidth / width;
  double mapHeight(double modelHeight) => modelHeight / height;
}

/// Top-level so it can run in a background isolate (`compute(encodeFrameJpeg, frame)`).
Uint8List encodeFrameJpeg(CameraFrame frame) => frame.toJpeg();
