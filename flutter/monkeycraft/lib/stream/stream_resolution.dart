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
  final visibleW = math.max(
    0.0,
    logicalSize.width - padding.left - padding.right,
  );
  final visibleH = math.max(
    0.0,
    logicalSize.height - padding.top - padding.bottom,
  );

  final rawW = visibleW * devicePixelRatio * scale;
  final rawH = visibleH * devicePixelRatio * scale;

  final scaleFactor = math.min(1.0, math.min(maxDim / rawW, maxDim / rawH));

  int w = (rawW * scaleFactor).round();
  int h = (rawH * scaleFactor).round();

  w = (w ~/ 2) * 2;
  h = (h ~/ 2) * 2;
  if (w < 2) w = 2;
  if (h < 2) h = 2;

  return StreamResolution(w, h);
}
