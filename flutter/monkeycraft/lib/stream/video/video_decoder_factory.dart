export 'video_decoder_factory_stub.dart'
    if (dart.library.io) 'video_decoder_factory_io.dart'
    if (dart.library.js_interop) 'video_decoder_factory_web.dart';
