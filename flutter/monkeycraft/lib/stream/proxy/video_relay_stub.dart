class VideoRelay {
  int get port => 0;
  String get url => '';

  Future<void> start() async {}

  void onVideoFrame(List<int> h264Data, bool isIdr) {}

  void updateFps(int fps) {}

  void reset() {}

  Future<void> stop() async {}
}
