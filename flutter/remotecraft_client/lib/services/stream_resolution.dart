import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class StreamResolution {
  final int width;
  final int height;

  const StreamResolution(this.width, this.height);
}

StreamResolution computeTargetResolution({
  required Size logicalSize,
  EdgeInsets padding = EdgeInsets.zero,
  required double devicePixelRatio,
  required double scale,
  int maxDim = 1920,
}) {
  final visibleW = math.max(0.0, logicalSize.width - padding.left - padding.right);
  final visibleH = math.max(0.0, logicalSize.height - padding.top - padding.bottom);

  final rawW = (visibleW * devicePixelRatio * scale).round();
  final rawH = (visibleH * devicePixelRatio * scale).round();

  int w = math.max(2, math.min(maxDim, rawW));
  int h = math.max(2, math.min(maxDim, rawH));

  w = (w ~/ 2) * 2;
  h = (h ~/ 2) * 2;
  if (w < 2) w = 2;
  if (h < 2) h = 2;

  return StreamResolution(w, h);
}
