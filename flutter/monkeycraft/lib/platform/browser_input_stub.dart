class BrowserPointerLockController {
  BrowserPointerLockController({void Function(double dx, double dy)? onMove});

  bool get isSupported => false;
  bool get isLocked => false;

  void setEnabled(bool enabled) {}

  void request() {}

  void release() {}

  void setMoveHandler(void Function(double dx, double dy)? onMove) {}

  void dispose() {}
}

class BrowserFullscreenController {
  bool get isSupported => false;
  bool get isFullscreen => false;

  void toggle() {}

  void dispose() {}
}

class BrowserInputLifecycle {
  BrowserInputLifecycle({required void Function() onInactive});

  void dispose() {}
}
