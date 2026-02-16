import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/services/hibernation_models.dart';

void main() {
  test('hibernationStartFromJson parses message', () {
    final ev = hibernationStartFromJson({'type': 'HIBERNATION_START', 'message': 'hello'});
    expect(ev, isNotNull);
    expect(ev!.message, 'hello');
  });

  test('hibernationStartFromJson defaults message', () {
    final ev = hibernationStartFromJson({'type': 'HIBERNATION_START'});
    expect(ev, isNotNull);
    expect(ev!.message, '');
  });

  test('hibernationEndFromJson parses', () {
    final ev = hibernationEndFromJson({'type': 'HIBERNATION_END'});
    expect(ev, isNotNull);
  });

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

  test('hibernationStatusFromJson requires active boolean', () {
    expect(
      hibernationStatusFromJson({'type': 'HIBERNATION_STATUS', 'active': 'true'}),
      isNull,
    );
  });
}
