import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monkeycraft_client/chat/chat_models.dart';
import 'package:monkeycraft_client/stream/stream_proxy.dart';
import 'package:monkeycraft_client/audio/openaudiomc_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatRichText extends StatefulWidget {
  final List<ChatSegment> segments;
  final TextStyle? baseStyle;
  final StreamProxy? proxy;
  final OpenAudioMcService? openAudioMc;
  final void Function(String command)? onSuggestCommand;

  const ChatRichText({
    super.key,
    required this.segments,
    this.baseStyle,
    this.proxy,
    this.openAudioMc,
    this.onSuggestCommand,
  });

  @override
  State<ChatRichText> createState() => _ChatRichTextState();
}

class _ChatRichTextState extends State<ChatRichText> {
  OverlayEntry? _tooltipOverlay;

  Color? _parseColor(String? colorStr) {
    if (colorStr == null || !colorStr.startsWith('#') || colorStr.length != 7) {
      return null;
    }
    final value = int.tryParse(colorStr.substring(1), radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 + value);
  }

  @override
  void dispose() {
    _removeTooltip();
    super.dispose();
  }

  void _removeTooltip() {
    _tooltipOverlay?.remove();
    _tooltipOverlay = null;
  }

  void _showTooltip(List<ChatSegment> segments, Offset position) {
    _removeTooltip();

    final screenSize = MediaQuery.of(context).size;
    double left = position.dx;

    const tooltipHeight = 100.0;

    bool showAbove = position.dy + tooltipHeight > screenSize.height;

    double top = showAbove
        ? position.dy - tooltipHeight - 30
        : position.dy + 25;

    if (left + 200 > screenSize.width) {
      left = screenSize.width - 210;
    }
    if (left < 10) left = 10;
    if (top < 10) top = 10;

    final spans = <InlineSpan>[];
    for (final seg in segments) {
      final color = _parseColor(seg.color);
      spans.add(
        TextSpan(
          text: seg.text,
          style: TextStyle(
            color: color ?? Colors.white,
            fontSize: 13,
            fontWeight: seg.bold ? FontWeight.bold : null,
            fontStyle: seg.italic ? FontStyle.italic : null,
            decoration: TextDecoration.combine([
              if (seg.underlined) TextDecoration.underline,
              if (seg.strikethrough) TextDecoration.lineThrough,
            ]),
          ),
        ),
      );
    }

    final overlay = Overlay.of(context);
    _tooltipOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
            child: Text.rich(TextSpan(children: spans)),
          ),
        ),
      ),
    );
    overlay.insert(_tooltipOverlay!);

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _removeTooltip();
    });
  }

  void _handleClick(ClickAction action) {
    switch (action.action) {
      case 'open_url':
        final uri = Uri.tryParse(action.value);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          if (OpenAudioMcService.isOpenAudioMcUrl(action.value)) {
            widget.openAudioMc?.connect(action.value);
          } else {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
        break;
      case 'run_command':
        widget.proxy?.trySendRunCommand(action.value);
        break;
      case 'suggest_command':
        widget.onSuggestCommand?.call(action.value);
        break;
      case 'copy_to_clipboard':
        Clipboard.setData(ClipboardData(text: action.value));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Copied to clipboard'),
              duration: Duration(seconds: 1),
            ),
          );
        }
        break;
    }
  }

  TextStyle _getStyleForSegment(ChatSegment seg, Color? color) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final base = widget.baseStyle ?? defaultStyle;
    return base.copyWith(
      color: color ?? base.color,
      fontWeight: seg.bold ? FontWeight.bold : null,
      fontStyle: seg.italic ? FontStyle.italic : null,
      decoration: TextDecoration.combine([
        if (seg.underlined) TextDecoration.underline,
        if (seg.strikethrough) TextDecoration.lineThrough,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.segments.isEmpty) return const SizedBox.shrink();

    final spans = <InlineSpan>[];

    for (final seg in widget.segments) {
      final color = _parseColor(seg.color);

      final style = _getStyleForSegment(seg, color);
      final hasClick = seg.clickAction != null;
      final hasHover =
          seg.hoverAction != null &&
          seg.hoverAction!.action == 'show_text' &&
          seg.hoverAction!.segments.isNotEmpty;

      if (!hasClick && !hasHover) {
        spans.add(TextSpan(text: seg.text, style: style));
        continue;
      }

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (hasClick) {
                _handleClick(seg.clickAction!);
              } else if (hasHover) {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null) {
                  final pos = box.localToGlobal(Offset.zero);
                  _showTooltip(
                    seg.hoverAction!.segments,
                    Offset(pos.dx + 50, pos.dy),
                  );
                }
              }
            },
            onLongPress: () {
              if (hasHover) {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null) {
                  final pos = box.localToGlobal(Offset.zero);
                  _showTooltip(
                    seg.hoverAction!.segments,
                    Offset(pos.dx + 50, pos.dy),
                  );
                }
              }
            },
            child: Text(
              seg.text,
              style: style.copyWith(
                height: 1.0,
                decoration: TextDecoration.combine([
                  if (seg.underlined) TextDecoration.underline,
                  if (seg.strikethrough) TextDecoration.lineThrough,
                  if (hasClick && !seg.underlined) TextDecoration.underline,
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return SelectableText.rich(
      TextSpan(children: spans, style: widget.baseStyle),
    );
  }
}
