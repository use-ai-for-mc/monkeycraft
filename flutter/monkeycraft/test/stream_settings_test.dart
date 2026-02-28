import 'package:flutter_test/flutter_test.dart';
import 'package:monkeycraft_client/stream/stream_settings.dart';

void main() {
  test('resolutionScale matches preset', () {
    expect(
      const StreamSettings(
        fps: 20,
        colorMode: 0,
        resolutionPreset: ResolutionPreset.low,
        invertLookY: true,
        autoSwitchRideChat: false,
        autoFaceMovement: false,
      ).resolutionScale,
      0.5,
    );
    expect(
      const StreamSettings(
        fps: 20,
        colorMode: 0,
        resolutionPreset: ResolutionPreset.medium,
        invertLookY: true,
        autoSwitchRideChat: false,
        autoFaceMovement: false,
      ).resolutionScale,
      0.75,
    );
    expect(
      const StreamSettings(
        fps: 20,
        colorMode: 0,
        resolutionPreset: ResolutionPreset.high,
        invertLookY: true,
        autoSwitchRideChat: false,
        autoFaceMovement: false,
      ).resolutionScale,
      1.0,
    );
  });
}
