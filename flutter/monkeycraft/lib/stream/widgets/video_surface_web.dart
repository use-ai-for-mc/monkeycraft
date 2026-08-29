import 'package:flutter/material.dart';
import 'package:monkeycraft_client/stream/video/monkeycraft_video_decoder.dart';

class VideoSurface extends StatelessWidget {
  final MonkeycraftVideoDecoder? decoder;
  final Widget? placeholder;

  const VideoSurface({super.key, required this.decoder, this.placeholder});

  @override
  Widget build(BuildContext context) {
    final viewType = decoder?.platformViewType;
    if (viewType == null) {
      return placeholder ?? const SizedBox.expand();
    }
    return HtmlElementView(viewType: viewType);
  }
}
