import 'package:monkeycraft_client/stream/video/monkeycraft_video_decoder.dart';
import 'package:monkeycraft_client/stream/video/web_h264_decoder.dart';

MonkeycraftVideoDecoder createVideoDecoder() => WebH264Decoder();
