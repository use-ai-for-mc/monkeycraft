import 'package:monkeycraft_client/stream/hardware_h264_decoder.dart';
import 'package:monkeycraft_client/stream/video/monkeycraft_video_decoder.dart';

MonkeycraftVideoDecoder createVideoDecoder() => HardwareH264Decoder();
