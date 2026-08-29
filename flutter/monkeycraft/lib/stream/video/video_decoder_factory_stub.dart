import 'package:monkeycraft_client/stream/video/monkeycraft_video_decoder.dart';
import 'package:monkeycraft_client/stream/video/noop_h264_decoder.dart';

MonkeycraftVideoDecoder createVideoDecoder() => NoopH264Decoder();
