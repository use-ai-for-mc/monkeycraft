import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

class KeyboardPrewarmer {
  static final KeyboardPrewarmer _instance = KeyboardPrewarmer._internal();
  factory KeyboardPrewarmer() => _instance;
  KeyboardPrewarmer._internal();

  bool _prewarmed = false;
  final FocusNode _focusNode = FocusNode();

  bool get isPrewarmed => _prewarmed;

  void prewarm(BuildContext context) {
    if (_prewarmed || !Platform.isIOS) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;

      final overlay = Overlay.of(context);
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (ctx) => Positioned(
          left: -10000,
          top: -10000,
          child: SizedBox(
            width: 1,
            height: 1,
            child: TextField(
              focusNode: _focusNode,
              autofocus: true,
              style: const TextStyle(fontSize: 0, color: Colors.transparent),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      );

      overlay.insert(entry);

      Future.delayed(const Duration(milliseconds: 100), () {
        _focusNode.unfocus();
        Future.delayed(const Duration(milliseconds: 100), () {
          entry.remove();
          _prewarmed = true;
        });
      });
    });
  }
}

class KeyboardPrewarmerWidget extends StatefulWidget {
  final Widget child;

  const KeyboardPrewarmerWidget({super.key, required this.child});

  @override
  State<KeyboardPrewarmerWidget> createState() =>
      _KeyboardPrewarmerWidgetState();
}

class _KeyboardPrewarmerWidgetState extends State<KeyboardPrewarmerWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      KeyboardPrewarmer().prewarm(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
