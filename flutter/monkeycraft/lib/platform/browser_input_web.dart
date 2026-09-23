import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

class BrowserPointerLockController {
  BrowserPointerLockController({void Function(double dx, double dy)? onMove})
    : _onMove = onMove,
      _testSupported = null,
      _testIsTargetLocked = null,
      _testRequest = null,
      _testExit = null {
    _attachListeners();
  }

  BrowserPointerLockController.forTesting({
    required bool Function() isTargetLocked,
    required JSAny? Function() requestPointerLock,
    required void Function() exitPointerLock,
    bool supported = true,
  }) : _onMove = null,
       _testSupported = supported,
       _testIsTargetLocked = isTargetLocked,
       _testRequest = requestPointerLock,
       _testExit = exitPointerLock {
    _attachListeners();
  }

  void _attachListeners() {
    _changeListener = ((web.Event _) {
      final isTargetLocked = _isTargetLocked();
      _locked = isTargetLocked;
      final epoch = _activeEpoch;
      if (isTargetLocked &&
          (_disposed || !_enabled || (epoch != null && !_isCurrent(epoch)))) {
        release();
      }
      _settle(epoch);
    }).toJS;
    _errorListener = ((web.Event _) {
      _settle(_activeEpoch);
    }).toJS;
    web.document.addEventListener('pointerlockchange', _changeListener);
    web.document.addEventListener('pointerlockerror', _errorListener);
    _moveListener = ((web.MouseEvent event) {
      if (_locked && _enabled && !_disposed) {
        _onMove?.call(event.movementX, event.movementY);
      }
    }).toJS;
    web.document.addEventListener('mousemove', _moveListener);
  }

  late final JSFunction _changeListener;
  late final JSFunction _errorListener;
  late final JSFunction _moveListener;
  void Function(double dx, double dy)? _onMove;
  final bool? _testSupported;
  final bool Function()? _testIsTargetLocked;
  final JSAny? Function()? _testRequest;
  final void Function()? _testExit;
  bool _enabled = true;
  bool _locked = false;
  bool _disposed = false;
  bool _listenersAttached = true;
  int _generation = 0;
  int? _activeEpoch;

  web.Element? get _target => web.document.body;

  bool get isSupported {
    final testSupported = _testSupported;
    if (testSupported != null) return testSupported;
    final target = _target;
    return target != null && (target as JSObject).has('requestPointerLock');
  }

  bool get isLocked => _locked;

  void setEnabled(bool enabled) {
    if (_disposed || _enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) {
      release();
    }
  }

  void request() {
    if (_disposed ||
        !_enabled ||
        _locked ||
        _activeEpoch != null ||
        !isSupported) {
      return;
    }
    final target = _target;
    if (target == null && _testRequest == null) return;
    final epoch = _generation;
    _activeEpoch = epoch;
    try {
      final result =
          _testRequest?.call() ??
          (target as JSObject).callMethod<JSAny?>('requestPointerLock'.toJS);
      if (result != null && (result as JSObject).has('then')) {
        (result as JSPromise<JSAny?>).toDart.then<void>((_) {
          if (!_isCurrent(epoch)) _exitLock();
        }, onError: (_) => _settle(epoch));
      }
    } catch (_) {
      _settle(epoch);
    }
  }

  void release() {
    _generation += 1;
    _exitLock();
  }

  void _exitLock() {
    try {
      if (_isTargetLocked()) {
        if (_testExit != null) {
          _testExit();
        } else {
          web.document.exitPointerLock();
        }
      }
    } catch (_) {}
    _locked = false;
  }

  void setMoveHandler(void Function(double dx, double dy)? onMove) {
    _onMove = onMove;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _enabled = false;
    release();
    _detachIfIdle();
  }

  bool _isCurrent(int? epoch) {
    return !_disposed && _enabled && epoch != null && epoch == _generation;
  }

  bool _isTargetLocked() {
    return _testIsTargetLocked?.call() ??
        (web.document.pointerLockElement == _target);
  }

  void _settle(int? epoch) {
    if (epoch != null && _activeEpoch == epoch) _activeEpoch = null;
    _detachIfIdle();
  }

  void _detachIfIdle() {
    if (!_disposed || _activeEpoch != null || !_listenersAttached) return;
    _listenersAttached = false;
    web.document.removeEventListener('pointerlockchange', _changeListener);
    web.document.removeEventListener('pointerlockerror', _errorListener);
    web.document.removeEventListener('mousemove', _moveListener);
  }
}

class BrowserFullscreenController {
  BrowserFullscreenController() {
    _changeListener = ((web.Event _) {
      _fullscreen = web.document.fullscreenElement != null;
    }).toJS;
    web.document.addEventListener('fullscreenchange', _changeListener);
  }

  late final JSFunction _changeListener;
  bool _fullscreen = false;
  bool _disposed = false;

  bool get isSupported {
    final target = web.document.documentElement;
    return target != null && (target as JSObject).has('requestFullscreen');
  }

  bool get isFullscreen => _fullscreen;

  void toggle() {
    if (_disposed || !isSupported) return;
    final target = web.document.documentElement;
    final receiver = _fullscreen ? web.document : target;
    final method = _fullscreen ? 'exitFullscreen' : 'requestFullscreen';
    if (receiver == null) return;
    try {
      final result = (receiver as JSObject).callMethod<JSAny?>(method.toJS);
      if (result != null && (result as JSObject).has('then')) {
        (result as JSPromise<JSAny?>).toDart.then<void>(
          (_) {},
          onError: (_) {},
        );
      }
    } catch (_) {}
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    web.document.removeEventListener('fullscreenchange', _changeListener);
  }
}

class BrowserInputLifecycle {
  BrowserInputLifecycle({required this.onInactive}) {
    _blurListener = ((web.Event _) => onInactive()).toJS;
    _visibilityListener = ((web.Event _) {
      if (web.document.hidden) onInactive();
    }).toJS;
    web.window.addEventListener('blur', _blurListener);
    web.document.addEventListener('visibilitychange', _visibilityListener);
  }

  final void Function() onInactive;
  late final JSFunction _blurListener;
  late final JSFunction _visibilityListener;

  void dispose() {
    web.window.removeEventListener('blur', _blurListener);
    web.document.removeEventListener('visibilitychange', _visibilityListener);
  }
}
