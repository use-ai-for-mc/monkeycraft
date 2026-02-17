import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/services/hibernation_models.dart';

void main() {
  test('hibernationStatusFromJson parses active + message', () {
    final ev = hibernationStatusFromJson({
      'type': 'HIBERNATION_STATUS',
      'active': true,
      'message': 'm',
    });
    expect(ev, isNotNull);
    expect(ev!.active, true);
    expect(ev.message, 'm');
  });

  test('hibernationStatusFromJson parses inactive without message', () {
    final ev = hibernationStatusFromJson({
      'type': 'HIBERNATION_STATUS',
      'active': false,
    });
    expect(ev, isNotNull);
    expect(ev!.active, false);
    expect(ev.message, isNull);
  });

  test('hibernationStatusFromJson requires active boolean', () {
    expect(
      hibernationStatusFromJson({
        'type': 'HIBERNATION_STATUS',
        'active': 'true',
      }),
      isNull,
    );
  });

  test('hibernationStatusFromJson returns null for wrong type', () {
    expect(hibernationStatusFromJson({'type': 'HIBERNATION_START'}), isNull);
  });
}
