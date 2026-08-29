export 'video_surface_stub.dart'
    if (dart.library.io) 'video_surface_io.dart'
    if (dart.library.js_interop) 'video_surface_web.dart';
