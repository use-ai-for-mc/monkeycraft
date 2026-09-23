import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/notifications/browser_notification_backend.dart';

void main() {
  test('non-web backend is unavailable without side effects', () async {
    expect(browserNotificationBackend.supported, isFalse);
    expect(browserNotificationBackend.permissionGranted, isFalse);
    expect(
      await browserNotificationBackend.requestPermissionFromUserGesture(),
      isFalse,
    );
    await browserNotificationBackend.schedule(
      fireAtEpochMs: 4102444800000,
      title: 'Test',
      body: 'Body',
      sound: true,
    );
    await browserNotificationBackend.cancel();
    await browserNotificationBackend.showImmediate(
      title: 'Test',
      body: 'Body',
      sound: false,
    );
    await browserNotificationBackend.playTestSound();
  });
}
