import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:monkeycraft_client/audio/audio_operation_queue.dart';

abstract interface class AudioBackgroundBackend {
  Future<void> start();
  Future<void> stop();
}

class MethodChannelAudioBackgroundBackend implements AudioBackgroundBackend {
  const MethodChannelAudioBackgroundBackend();

  static const _channel = MethodChannel('monkeycraft/audio_background');

  @override
  Future<void> start() => _channel.invokeMethod<void>('start');

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}

class NoopAudioBackgroundBackend implements AudioBackgroundBackend {
  const NoopAudioBackgroundBackend();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

class AudioBackgroundSession {
  AudioBackgroundSession._();

  static final _owners = <Object>{};
  static var _operations = AudioOperationQueue();
  static AudioBackgroundBackend _backend = _defaultBackend();

  static AudioBackgroundBackend _defaultBackend() {
    if (Platform.isAndroid || Platform.isIOS) {
      return const MethodChannelAudioBackgroundBackend();
    }
    return const NoopAudioBackgroundBackend();
  }

  static Future<bool> acquire(Object owner) => _operations.enqueue(() async {
    if (_owners.contains(owner)) return true;
    if (_owners.isEmpty) {
      try {
        await _backend.start();
      } catch (_) {
        return false;
      }
    }
    _owners.add(owner);
    return true;
  });

  static Future<bool> release(Object owner) => _operations.enqueue(() async {
    if (!_owners.contains(owner)) return true;
    if (_owners.length > 1) {
      _owners.remove(owner);
      return true;
    }
    try {
      await _backend.stop();
      _owners.remove(owner);
      return true;
    } catch (_) {
      return false;
    }
  });

  static int get activeLeases => _owners.length;

  static void configureForTest(AudioBackgroundBackend backend) {
    _owners.clear();
    _backend = backend;
  }

  static void resetForTest() {
    _owners.clear();
    _operations = AudioOperationQueue();
    _backend = _defaultBackend();
  }
}
