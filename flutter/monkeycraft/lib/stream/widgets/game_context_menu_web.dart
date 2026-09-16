import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class GameContextMenuGuard extends StatefulWidget {
  const GameContextMenuGuard({super.key, required this.child});

  final Widget child;

  @override
  State<GameContextMenuGuard> createState() => _GameContextMenuGuardState();
}

class _GameContextMenuGuardState extends State<GameContextMenuGuard> {
  late final JSFunction _handler;

  @override
  void initState() {
    super.initState();
    _handler = ((web.MouseEvent e) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final origin = box.localToGlobal(Offset.zero);
      final rect = origin & box.size;
      if (!rect.contains(
        Offset(e.clientX.toDouble(), e.clientY.toDouble()),
      )) {
        return;
      }
      e.preventDefault();
    }).toJS;
    web.document.addEventListener('contextmenu', _handler);
  }

  @override
  void dispose() {
    web.document.removeEventListener('contextmenu', _handler);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
