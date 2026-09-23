import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/notifications/timed_notification_service.dart';

void main() {
  const channel = MethodChannel('monkeycraft/notifications');

  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'reads Android exact alarm access and opens settings on request',
    () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'getExactAlarmAccess') {
              return {'supported': true, 'granted': false};
            }
            if (call.method == 'openExactAlarmSettings') return true;
            return null;
          });
      final service = TimedNotificationService(isAndroid: true);

      final access = await service.getExactAlarmAccess();

      expect(access.supported, isTrue);
      expect(access.granted, isFalse);
      expect(await service.openExactAlarmSettings(), isTrue);
      expect(calls, ['getExactAlarmAccess', 'openExactAlarmSettings']);
    },
  );

  test('does not invoke a native channel off Android', () async {
    final service = TimedNotificationService(isAndroid: false);

    expect((await service.getExactAlarmAccess()).supported, isFalse);
    expect(await service.openExactAlarmSettings(), isFalse);
  });
}
