// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:vibe/vibe/vibe_live_location.dart';
import 'package:vibe/vibe/vibe_map.dart';

/// A shared place as a card the shape of a message bubble: a small map with
/// the sender's picture as the pin, the place and how far it is underneath.
/// Tap to open the map.
class MapBubble extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double zoom;
  final double width;
  final double height;
  final VoidCallback? onTap;
  final String? title;
  final String? sub;

  /// "Live · 42 min left", on the map.
  final String? tag;

  /// Live location: the tag's dot pulses.
  final bool live;

  /// The pin: usually the sender's picture.
  final Widget? picture;

  /// Only roughly here: a circle this many metres round instead of a pin.
  final double? meters;

  /// At the end of the text (Stop sharing).
  final Widget? action;
  final Color? color;
  final Color? ink;

  const MapBubble({
    required this.latitude,
    required this.longitude,
    this.zoom = 15.0,
    this.width = 264,
    this.height = 148,
    this.onTap,
    this.title,
    this.sub,
    this.tag,
    this.live = false,
    this.picture,
    this.meters,
    this.action,
    this.color,
    this.ink,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        color ??
        Color.alphaBlend(
          cs.surfaceContainerHigh,
          dark ? const Color(0xFF1B1B1F) : const Color(0xFFF1F1F4),
        );
    final fg = ink ?? cs.onSurface;
    final at = LatLng(latitude, longitude);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _Later(
                          child: VibeMap(
                            key: ValueKey('$latitude,$longitude'),
                            center: at,
                            zoom: meters != null && meters! > 300 ? 13 : zoom,
                            interactive: false,
                            marks: [
                              if (meters != null)
                                VibeMapMark(
                                  id: 'area',
                                  at: at,
                                  meters: meters,
                                  size: Size.zero,
                                  child: const SizedBox.shrink(),
                                )
                              else if (picture != null)
                                VibeMapMark(
                                  id: 'pin',
                                  at: at,
                                  size: VibePicturePin.box(34),
                                  anchor: Alignment.bottomCenter,
                                  child: VibePicturePin(
                                    picture: picture!,
                                    size: 34,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (tag != null)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: VibeLiveTag(text: tag!, live: live),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 10, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title ?? 'Location',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                              color: fg,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sub ??
                                '${latitude.toStringAsFixed(5)}, '
                                    '${longitude.toStringAsFixed(5)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: fg.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ?action,
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

/// "● Live · 42 min left" in a small white pill.
class VibeLiveTag extends StatelessWidget {
  final String text;
  final bool live;
  const VibeLiveTag({required this.text, this.live = true, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x26000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[const VibeLiveDot(), const SizedBox(width: 6)],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// The map in a card starts a moment after the card shows, so flicking
/// through the chat doesn't start a map for every card going by.
class _Later extends StatefulWidget {
  final Widget child;
  const _Later({required this.child});

  @override
  State<_Later> createState() => _LaterState();
}

class _LaterState extends State<_Later> {
  bool _show = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(milliseconds: 280), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _show ? widget.child : const VibeMapShimmer();
}
