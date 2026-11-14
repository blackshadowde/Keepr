// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/screens/chat/events/map_bubble.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

class SendLocationDialog extends StatefulWidget {
  final Room room;

  const SendLocationDialog({required this.room, super.key});

  @override
  SendLocationDialogState createState() => SendLocationDialogState();
}

class SendLocationDialogState extends State<SendLocationDialog> {
  bool disabled = false;
  bool denied = false;
  bool isSending = false;
  Position? position;
  Object? error;
  final _map = MapController();

  /// The place under the pin once you've moved the map, else null.
  final _picked = ValueNotifier<LatLng?>(null);

  @override
  void dispose() {
    _picked.dispose();
    super.dispose();
  }

  void _toMe() {
    final p = position;
    if (p == null) return;
    try {
      _map.move(LatLng(p.latitude, p.longitude), 16);
    } catch (_) {}
    _picked.value = null;
  }

  void _noteMove() {
    if (!mounted) return;
    try {
      _picked.value = _map.camera.center;
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    requestLocation();
  }

  Future<void> requestLocation() async {
    if (!(await Geolocator.isLocationServiceEnabled())) {
      setState(() => disabled = true);
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => denied = true);
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() => denied = true);
      return;
    }
    try {
      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 30),
          ),
        );
      } on TimeoutException {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 30),
          ),
        );
      }
      if (!mounted) return;
      setState(() => this.position = position);
      if (_picked.value == null) _toMe();
    } catch (e) {
      setState(() => error = e);
    }
  }

  /// Sends where you are, or [place] (the spot under the pin).
  Future<void> sendAction([LatLng? place]) async {
    if (isSending) return;
    setState(() => isSending = true);
    final lat = place?.latitude ?? position!.latitude;
    final lon = place?.longitude ?? position!.longitude;
    final body =
        'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=16/$lat/$lon';
    final uri = place == null
        ? 'geo:$lat,$lon;u=${position!.accuracy}'
        : 'geo:$lat,$lon';
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => widget.room.sendLocation(body, uri),
    );
    if (!mounted) return;
    if (result.error != null) {
      setState(() => isSending = false);
      return;
    }
    Navigator.of(context, rootNavigator: false).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pos = position;
    final String? notice = pos != null
        ? null
        : disabled
        ? L10n.of(context).locationDisabledNotice
        : denied
        ? L10n.of(context).locationPermissionDeniedNotice
        : error != null
        ? L10n.of(context).errorObtainingLocation(error.toString())
        : L10n.of(context).obtainingLocation;
    Widget round(IconData icon, String tip, VoidCallback onTap) => Material(
      color: cs.surfaceContainerHigh,
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(tooltip: tip, icon: Icon(icon), onPressed: onTap),
    );
    return Dialog.fullscreen(
      backgroundColor: cs.surface,
      child: Stack(
        children: [
          // drag the map: the pin stays in the middle and marks the place
          Positioned.fill(
            child: Listener(
              onPointerUp: (_) {
                _noteMove();
                // the map glides on a little after a flick
                Future.delayed(const Duration(milliseconds: 700), () {
                  if (_picked.value != null) _noteMove();
                });
              },
              child: vibeMapTiles(
                context,
                map: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: const LatLng(20, 0),
                    initialZoom: 2,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [vibeTileLayer()],
                ),
              ),
            ),
          ),
          const IgnorePointer(child: Center(child: VibeMapPin())),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      round(
                        Icons.arrow_back,
                        L10n.of(context).cancel,
                        Navigator.of(context, rootNavigator: false).pop,
                      ),
                      const SizedBox(width: 10),
                      Material(
                        color: cs.surfaceContainerHigh,
                        shape: const StadiumBorder(),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 13,
                          ),
                          child: Text(
                            L10n.of(context).shareLocation,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (pos != null)
                        round(Icons.my_location, 'Where I am', _toMe),
                    ],
                  ),
                  const Spacer(),
                  Material(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(28),
                    elevation: 3,
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: ValueListenableBuilder<LatLng?>(
                        valueListenable: _picked,
                        builder: (context, picked, _) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (notice != null)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    if (!disabled && !denied && error == null)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 12),
                                        child: SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        notice,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (pos != null)
                              _Choice(
                                icon: Icons.my_location,
                                title: 'Send where I am',
                                sub: 'Accurate to ${pos.accuracy.round()} m',
                                filled: picked == null,
                                onTap: () => sendAction(),
                              ),
                            if (picked != null)
                              _Choice(
                                icon: Icons.place_rounded,
                                title: 'Send this place',
                                sub:
                                    '${picked.latitude.toStringAsFixed(5)}, '
                                    '${picked.longitude.toStringAsFixed(5)}',
                                filled: true,
                                onTap: () {
                                  _noteMove();
                                  sendAction(_picked.value ?? picked);
                                },
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  6,
                                  12,
                                  8,
                                ),
                                child: Text(
                                  'Move the map to send another place',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One way to send, in the sheet under the map.
class _Choice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final bool filled;
  final VoidCallback onTap;
  const _Choice({
    required this.icon,
    required this.title,
    required this.sub,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: filled ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: cs.onPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: filled ? cs.onPrimaryContainer : cs.onSurface,
                        ),
                      ),
                      Text(
                        sub,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: filled
                              ? cs.onPrimaryContainer.withValues(alpha: 0.75)
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
