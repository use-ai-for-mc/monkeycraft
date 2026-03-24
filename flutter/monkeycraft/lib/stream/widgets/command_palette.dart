import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monkeycraft_client/main.dart';
import 'package:monkeycraft_client/stream/stream_proxy.dart';

Future<void> showCommandPalette({
  required BuildContext context,
  required StreamProxy proxy,
}) async {
  final controller = TextEditingController(text: '/');

  Future<void> submit(BuildContext ctx) async {
    final text = controller.text.trim();
    if (!text.startsWith('/')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Command must start with /')),
      );
      return;
    }
    final sent = proxy.trySendRunCommand(text);
    if (!sent) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not connected')));
      return;
    }
    if (!ctx.mounted) return;
    Navigator.of(ctx).pop();
  }

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return Center(
        child: GestureDetector(
          onTap: () => FocusScope.of(ctx).unfocus(),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            constraints: const BoxConstraints(maxWidth: 400),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Material(
                  color: const Color(0xCC111111),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Command',
                          style: appSettings.textStyleWithFont(
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: controller,
                          autofocus: true,
                          textInputAction: TextInputAction.send,
                          style: appSettings.textStyleWithFont(
                            const TextStyle(color: Colors.white),
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[ -~]'),
                            ),
                          ],
                          decoration: InputDecoration(
                            hintText: '/warp home',
                            hintStyle: appSettings.textStyleWithFont(
                              const TextStyle(color: Colors.white38),
                            ),
                            helperText: 'Must start with /',
                            helperStyle: appSettings.textStyleWithFont(
                              const TextStyle(color: Colors.white54),
                            ),
                            filled: true,
                            fillColor: const Color(0x33111111),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) => submit(ctx),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => submit(ctx),
                                child: const Text('Send'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(animation),
          child: child,
        ),
      );
    },
  );
}
