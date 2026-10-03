import 'dart:typed_data';

import 'face.dart';

/// Decodes the raw outputs of MediaPipe's BlazeFace short-range model
/// (input 128x128 RGB in [-1, 1]; outputs 896x16 regressors and 896 scores) into faces.
///
/// Mirrors MediaPipe's own graph (SsdAnchorsCalculator, TensorsToDetectionsCalculator,
/// weighted non-max suppression), validated against reference outputs in test/fixtures.
class BlazeFaceDecoder {
  BlazeFaceDecoder({this.minScore = 0.5, this.minSuppressionIou = 0.3}) : _anchors = _buildAnchors();

  static const inputSize = 128;
  static const anchorCount = 896;
  static const valuesPerAnchor = 16;

  final double minScore;
  final double minSuppressionIou;
  final List<NormalizedPoint> _anchors;

  /// Anchor centers: stride 8 -> 16x16 grid x 2 anchors, stride 16 (three layers) -> 8x8 x 6.
  /// Short-range anchors have a fixed size of 1, so only centers matter.
  static List<NormalizedPoint> _buildAnchors() {
    final anchors = <NormalizedPoint>[];
    for (final (stride, perCell) in const [(8, 2), (16, 6)]) {
      final cells = inputSize ~/ stride;
      for (var y = 0; y < cells; y++) {
        for (var x = 0; x < cells; x++) {
          for (var i = 0; i < perCell; i++) {
            anchors.add(NormalizedPoint((x + 0.5) / cells, (y + 0.5) / cells));
          }
        }
      }
    }
    assert(anchors.length == anchorCount);
    return anchors;
  }

  /// Faces in the model's 128x128 input space (0..1), highest score first.
  List<ObservedFace> decode(Float32List regressors, Float32List scores) {
    final candidates = <_Candidate>[];
    for (var i = 0; i < anchorCount; i++) {
      final score = sigmoid(scores[i]);
      if (score < minScore) continue;
      final o = i * valuesPerAnchor;
      final anchor = _anchors[i];
      double v(int k) => regressors[o + k] / inputSize;
      final cx = v(0) + anchor.x, cy = v(1) + anchor.y, w = v(2), h = v(3);
      final keypoints = List<double>.generate(12, (k) => v(4 + k) + (k.isEven ? anchor.x : anchor.y));
      candidates.add(_Candidate(score, [cx - w / 2, cy - h / 2, w, h], keypoints));
    }
    return _weightedNms(candidates);
  }

  List<ObservedFace> _weightedNms(List<_Candidate> candidates) {
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final faces = <ObservedFace>[];
    var remaining = candidates;
    while (remaining.isNotEmpty) {
      final top = remaining.first;
      final group = <_Candidate>[];
      final rest = <_Candidate>[];
      for (final c in remaining) {
        (_iou(top.box, c.box) > minSuppressionIou ? group : rest).add(c);
      }
      final total = group.fold<double>(0, (sum, c) => sum + c.score);
      List<double> blend(List<double> Function(_Candidate) pick, int n) => List<double>.generate(
        n,
        (k) => group.fold<double>(0, (sum, c) => sum + pick(c)[k] * c.score) / total,
      );
      final box = blend((c) => c.box, 4);
      final kp = blend((c) => c.keypoints, 12);
      faces.add(
        ObservedFace(
          box: NormalizedBox(box[0], box[1], box[2], box[3]),
          score: top.score,
          eyeA: NormalizedPoint(kp[0], kp[1]),
          eyeB: NormalizedPoint(kp[2], kp[3]),
          nose: NormalizedPoint(kp[4], kp[5]),
        ),
      );
      remaining = rest;
    }
    return faces;
  }

  static double _iou(List<double> a, List<double> b) {
    final ix = (_min(a[0] + a[2], b[0] + b[2]) - _max(a[0], b[0])).clamp(0.0, double.infinity);
    final iy = (_min(a[1] + a[3], b[1] + b[3]) - _max(a[1], b[1])).clamp(0.0, double.infinity);
    final inter = ix * iy;
    return inter / (a[2] * a[3] + b[2] * b[3] - inter + 1e-9);
  }

  static double _min(double a, double b) => a < b ? a : b;
  static double _max(double a, double b) => a > b ? a : b;
}

class _Candidate {
  _Candidate(this.score, this.box, this.keypoints);
  final double score;
  final List<double> box; // x, y, w, h
  final List<double> keypoints; // 6 points as x, y pairs
}
