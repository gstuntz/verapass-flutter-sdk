import 'dart:math' as math;

/// A point in normalized image coordinates (0..1 across the upright, unmirrored frame).
class NormalizedPoint {
  const NormalizedPoint(this.x, this.y);
  final double x;
  final double y;

  @override
  String toString() => '(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

/// A face box in normalized coordinates of the upright, unmirrored frame.
class NormalizedBox {
  const NormalizedBox(this.x, this.y, this.width, this.height);
  final double x;
  final double y;
  final double width;
  final double height;

  double get centerX => x + width / 2;
  double get centerY => y + height / 2;
}

/// One detected face. Keypoints follow BlazeFace: eyes, nose tip, mouth, ears.
class ObservedFace {
  const ObservedFace({required this.box, required this.score, this.eyeA, this.eyeB, this.nose});

  final NormalizedBox box;
  final double score;
  final NormalizedPoint? eyeA;
  final NormalizedPoint? eyeB;
  final NormalizedPoint? nose;

  /// Signed head turn, same geometry as the server: (nose x - eye midpoint x) / eye distance,
  /// on the unmirrored frame. Positive = the face points to the image's right = the person's
  /// own left. Null when keypoints are missing.
  double? get yaw {
    final a = eyeA, b = eyeB, n = nose;
    if (a == null || b == null || n == null) return null;
    final distance = (b.x - a.x).abs();
    if (distance < 1e-6) return null;
    return (n.x - (a.x + b.x) / 2) / distance;
  }

  @override
  String toString() => 'Face(score: ${score.toStringAsFixed(2)}, width: ${box.width.toStringAsFixed(3)}, yaw: ${yaw?.toStringAsFixed(3)})';
}

double sigmoid(double x) => 1 / (1 + math.exp(-x.clamp(-100.0, 100.0)));
