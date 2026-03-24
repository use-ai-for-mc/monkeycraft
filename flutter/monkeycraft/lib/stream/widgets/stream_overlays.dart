import 'package:flutter/material.dart';
import 'package:monkeycraft_client/main.dart';

class HibernationOverlay extends StatelessWidget {
  final String message;

  const HibernationOverlay({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: message
                  .split('\n')
                  .map(
                    (line) => Text(
                      line,
                      style: appSettings.textStyleWithFont(
                        const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class WaitingOverlay extends StatelessWidget {
  const WaitingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bedtime, color: Colors.white, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Waiting for video stream...',
                  style: appSettings.textStyleWithFont(
                    const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ResolutionMismatchOverlay extends StatelessWidget {
  final String message;

  const ResolutionMismatchOverlay({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.aspect_ratio, color: Colors.white, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Waiting for correct resolution...',
                  style: appSettings.textStyleWithFont(
                    const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: appSettings.textStyleWithFont(
                    const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
