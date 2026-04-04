import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:monkeycraft_client/shared/protocol_models.dart';
import 'package:monkeycraft_client/stream/stream_proxy.dart';
import 'package:monkeycraft_client/stream/session_controller.dart';
import 'package:monkeycraft_client/stream/game_input_controller.dart';
import 'package:monkeycraft_client/stream/widgets/virtual_joystick.dart';
import 'package:monkeycraft_client/stream/widgets/jump_button.dart';
import 'package:monkeycraft_client/stream/widgets/shift_button.dart';
import 'package:monkeycraft_client/stream/widgets/hotbar_selector.dart';

class MapScreen extends StatefulWidget {
  final StreamProxy proxy;
  final SessionController session;

  const MapScreen({
    super.key,
    required this.proxy,
    required this.session,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final GameInputController _input;
  StreamSubscription<MapData>? _mapDataSub;

  MapData? _currentMapData;
  bool _hotbarExpanded = false;
  int _selectedHotbarSlot = 0;

  // Entity tap detection
  MapEntity? _selectedEntity;

  @override
  void initState() {
    super.initState();
    _input = GameInputController(
      (key, pressed) => widget.proxy.sendCommand({
        'type': 'INPUT',
        'key': key,
        'pressed': pressed,
      }),
    );

    _mapDataSub = widget.proxy.mapDataEvents.listen(_handleMapData);
  }

  void _handleMapData(MapData data) {
    if (!mounted) return;
    setState(() {
      _currentMapData = data;
    });
  }

  void _onVideoTap(TapUpDetails details, BoxConstraints constraints) {
    final data = _currentMapData;
    if (data == null) return;

    // The video texture fills the entire screen
    final screenW = constraints.maxWidth;
    final screenH = constraints.maxHeight;

    final tapX = details.localPosition.dx;
    final tapY = details.localPosition.dy;

    // We need to map screen tap to world coordinates.
    // The camera is ~20 blocks above the player looking straight down.
    // The visible area depends on the FOV and aspect ratio.
    // For a 70-degree FOV at 20 blocks height, visible half-width ≈ 20 * tan(35°) ≈ 14 blocks
    // This is approximate — exact values depend on Minecraft's FOV setting.
    const cameraHeight = 20.0;
    const fovDeg = 70.0;
    final halfFovRad = (fovDeg / 2) * math.pi / 180;
    final halfVisibleHeight = cameraHeight * math.tan(halfFovRad);
    final aspectRatio = screenW / screenH;
    final halfVisibleWidth = halfVisibleHeight * aspectRatio;

    // Map tap position to world offset from player
    final worldOffsetX = (tapX / screenW - 0.5) * 2 * halfVisibleWidth;
    final worldOffsetZ = (tapY / screenH - 0.5) * 2 * halfVisibleHeight;

    final worldX = data.playerX + worldOffsetX;
    final worldZ = data.playerZ + worldOffsetZ;

    // Find nearest entity within 3 blocks
    MapEntity? nearest;
    double nearestDist = 3.0;
    for (final entity in data.entities) {
      final dist = math.sqrt(
        math.pow(entity.x - worldX, 2) + math.pow(entity.z - worldZ, 2),
      );
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = entity;
      }
    }

    setState(() => _selectedEntity = nearest);

    if (nearest != null && nearest.isRideable) {
      _showEntityAction(nearest);
    }
  }

  void _showEntityAction(MapEntity entity) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entity.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Position: ${entity.x.toStringAsFixed(1)}, ${entity.z.toStringAsFixed(1)}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  widget.proxy.sendMapInteract(entity.entityId);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.directions_car),
                label: const Text('Ride'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _input.releaseAll();
    _mapDataSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final pad = mq.padding;
    final screenSize = mq.size;
    final isPortrait = screenSize.width < screenSize.height;
    final safeW = screenSize.width - pad.left - pad.right;
    final safeH = screenSize.height - pad.top - pad.bottom;
    final shortSide = math.min(safeW, safeH);

    final joystickSize = isPortrait
        ? shortSide.clamp(140.0, 190.0)
        : (shortSide * 0.65).clamp(110.0, 150.0);
    final jumpSize = isPortrait
        ? (shortSide * 0.42).clamp(74.0, 104.0)
        : (shortSide * 0.42).clamp(62.0, 86.0);
    final shiftSize = jumpSize;
    const buttonGap = 12.0;
    const hotbarToggleSize = 48.0;
    const hotbarGap = 8.0;
    final hotbarButtonSize = isPortrait
        ? 44.0
        : (((safeW - (20 * 2) - 16) - (hotbarGap * 8)) / 9.0).clamp(28.0, 40.0);
    final topBarY = pad.top + 12;

    final textureId = widget.session.textureId;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video texture (full screen)
          LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onTapUp: (details) => _onVideoTap(details, constraints),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: textureId != null
                      ? Texture(textureId: textureId)
                      : const Center(
                          child: Text(
                            'Waiting for video...',
                            style: TextStyle(color: Colors.white54, fontSize: 16),
                          ),
                        ),
                ),
              );
            },
          ),

          // Coordinate display
          if (_currentMapData != null)
            Positioned(
              bottom: pad.bottom + joystickSize + 24,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'X: ${_currentMapData!.playerX.toStringAsFixed(0)}  Z: ${_currentMapData!.playerZ.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),

          // Top bar: close button
          Positioned(
            top: topBarY,
            right: pad.right + 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // Hotbar toggle
          Positioned(
            top: topBarY,
            left: pad.left + 20,
            child: HotbarToggleButton(
              size: hotbarToggleSize,
              expanded: _hotbarExpanded,
              onPressed: () => setState(() => _hotbarExpanded = !_hotbarExpanded),
            ),
          ),
          if (_hotbarExpanded)
            Positioned(
              top: topBarY + hotbarToggleSize + 8,
              left: pad.left + 20,
              child: HotbarGrid(
                buttonSize: hotbarButtonSize,
                gap: hotbarGap,
                selectedSlot: _selectedHotbarSlot,
                singleRow: !isPortrait,
                onSelect: (slot) {
                  setState(() {
                    _selectedHotbarSlot = slot;
                    _hotbarExpanded = false;
                  });
                  widget.proxy.sendCommand({
                    'type': 'HOTBAR_SELECT',
                    'slot': slot,
                  });
                },
              ),
            ),

          // Movement controls
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: VirtualJoystick(
                    size: joystickSize,
                    onChanged: _input.updateMoveVector,
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      JumpButton(
                        size: jumpSize,
                        onChanged: _input.setJumpPressed,
                      ),
                      const SizedBox(height: buttonGap),
                      ShiftButton(
                        size: shiftSize,
                        onChanged: _input.setShiftPressed,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
