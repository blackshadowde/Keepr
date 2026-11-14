// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:vibe/config/app_config.dart';

/// Map tiles in dark mode: the same map, turned dark and grey.
const vibeMapNight = ColorFilter.matrix(<double>[
  -0.2126, -0.7152, -0.0722, 0, 255,
  -0.2126, -0.7152, -0.0722, 0, 255,
  -0.2126, -0.7152, -0.0722, 0, 255,
  0, 0, 0, 1, 0,
]);

/// The map itself, dark in dark mode.
Widget vibeMapTiles(BuildContext context, {required Widget map}) =>
    Theme.of(context).brightness == Brightness.dark
    ? ColorFiltered(colorFilter: vibeMapNight, child: map)
    : map;

TileLayer vibeTileLayer() => TileLayer(
  maxZoom: 20,
  minZoom: 0,
  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: AppConfig.appId,
  subdomains: const ['a', 'b', 'c'],
);

/// A round pin in the theme colour; its tip marks the middle of the map
/// it's centred on.
class VibeMapPin extends StatelessWidget {
  const VibeMapPin({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Transform.translate(
      offset: const Offset(0, -19),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Container(width: 3, height: 10, color: cs.primary),
        ],
      ),
    );
  }
}

/// A shared place as a card: the map on top, what it is underneath. Tap to
/// open it in a maps app.
class MapBubble extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double zoom;
  final double width;
  final double height;
  final double radius;
  final VoidCallback? onTap;

  const MapBubble({
    required this.latitude,
    required this.longitude,
    this.zoom = 15.0,
    this.width = 280,
    this.height = 150,
    this.radius = 20.0,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Material(
        color: Color.alphaBlend(
          cs.surfaceContainerHigh,
          dark ? const Color(0xFF1B1B1F) : const Color(0xFFF1F1F4),
        ),
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // the map doesn't move here; a tap opens it
                    IgnorePointer(
                      child: vibeMapTiles(
                        context,
                        map: FlutterMap(
                          key: ValueKey('$latitude,$longitude'),
                          options: MapOptions(
                            initialCenter: LatLng(latitude, longitude),
                            initialZoom: zoom,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.none,
                            ),
                          ),
                          children: [vibeTileLayer()],
                        ),
                      ),
                    ),
                    const Center(child: VibeMapPin()),
                    Positioned(
                      right: 8,
                      bottom: 5,
                      child: Text(
                        '© OpenStreetMap',
                        style: TextStyle(
                          fontSize: 9,
                          color: dark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    Icon(Icons.place_rounded, size: 20, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Location',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            '${latitude.toStringAsFixed(5)}, '
                            '${longitude.toStringAsFixed(5)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: L10n.of(context).openInMaps,
                      child: Icon(
                        Icons.north_east_rounded,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
