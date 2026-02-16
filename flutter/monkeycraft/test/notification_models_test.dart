import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/services/notification_models.dart';

void main() {
  test('timedFromJson parses TIMED with null fireAtEpochMs', () {
    final msg = {
      'type': 'TIMED',
      'fireAtEpochMs': null,
      'title': 't',
      'body': 'b',
      'sound': true,
    };
    final timed = timedFromJson(msg);
    expect(timed, isNotNull);
    expect(timed!.fireAtEpochMs, isNull);
    expect(timed.title, 't');
    expect(timed.body, 'b');
    expect(timed.sound, true);
  });

  test('timedFromJson parses TIMED with epoch ms', () {
    final msg = {
      'type': 'TIMED',
      'fireAtEpochMs': 1730000000000,
      'title': 't',
      'body': 'b',
      'sound': false,
    };
    final timed = timedFromJson(msg);
    expect(timed, isNotNull);
    expect(timed!.fireAtEpochMs, 1730000000000);
    expect(timed.sound, false);
  });

  test('nudgeFromJson parses NUDGE', () {
    final msg = {
      'type': 'NUDGE',
      'title': 'hi',
      'body': 'there',
      'sound': true,
    };
    final nudge = nudgeFromJson(msg);
    expect(nudge, isNotNull);
    expect(nudge!.title, 'hi');
    expect(nudge.body, 'there');
    expect(nudge.sound, true);
  });

  test('parsers ignore other types', () {
    expect(timedFromJson({'type': 'X'}), isNull);
    expect(nudgeFromJson({'type': 'X'}), isNull);
  });
}
