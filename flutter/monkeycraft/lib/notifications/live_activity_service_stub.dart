class LiveActivityService {
  Future<void> init() async {}

  Future<void> startCountdown({
    required int fireAtEpochMs,
    required String title,
    String body = '',
    String countDownText = 'TBA',
  }) async {}

  Future<void> updateCountdown({
    required int fireAtEpochMs,
    required String title,
    String body = '',
    String countDownText = 'TBA',
  }) async {}

  Future<void> cancel() async {}

  Future<void> dispose() async {}
}
