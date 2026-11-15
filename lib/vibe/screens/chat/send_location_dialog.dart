// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/vibe_dialog.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_live_location.dart';
import 'package:vibe/vibe/vibe_live_map.dart';
import 'package:vibe/vibe/vibe_map.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';

/// Send a location: one sheet. Drag the map and the pin (your picture)
/// lifts, then drops with a bounce where you let go; the street sits
/// underneath. Send this spot, share live, check in, or send only roughly
/// where you are.
class SendLocationDialog extends StatefulWidget {
  final Room room;

  const SendLocationDialog({required this.room, super.key});

  @override
  SendLocationDialogState createState() => SendLocationDialogState();
}

class SendLocationDialogState extends State<SendLocationDialog> {
  final _map = GlobalKey<VibeMapState>();
  bool disabled = false;
  bool denied = false;
  bool isSending = false;
  Position? position;
  Object? error;

  /// The spot under the pin once you've moved the map, else null (you).
  LatLng? _picked;
  bool _moved = false;
  bool _dragging = false;
  bool _tilted = false;

  /// Only roughly where (about 1 km).
  bool _approx = false;

  (String, String)? _name;
  bool _looking = false;

  LatLng? get _me =>
      position == null ? null : LatLng(position!.latitude, position!.longitude);
  LatLng? get _spot => _picked ?? _me;

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
      if (!_moved) _toMe();
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  void _toMe() {
    final me = _me;
    if (me == null) return;
    _map.currentState?.glide(me, zoom: 16.5);
    setState(() {
      _picked = null;
      _moved = false;
    });
    _lookup(me);
  }

  void _onDrag() {
    if (!_dragging) {
      setState(() {
        _dragging = true;
        _name = null;
      });
    }
    _moved = true;
  }

  void _onIdle(LatLng center) {
    if (!_moved) return;
    final was = _dragging;
    setState(() {
      _picked = center;
      _dragging = false;
    });
    // the pin lands
    if (was) VibeHaptics.light();
    _lookup(center);
  }

  Future<void> _lookup(LatLng at) async {
    if (!VibePlaces.on) return;
    setState(() => _looking = true);
    final n = await VibePlaces.lookup(at);
    if (!mounted || _spot != at) return;
    setState(() {
      _name = n;
      _looking = false;
    });
  }

  Future<void> _askNames() async {
    final yes = await showVibeDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Show street names?'),
        content: const Text(
          'Keepr asks Photon (built on OpenStreetMap) for the name of the '
          'spot under the pin. Only that spot is sent to it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Show names'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await AppSettings.vibeMapNames.setItem(true);
    final s = _spot;
    if (s != null) _lookup(s);
  }

  Future<void> _live(Duration d) async {
    VibeHaptics.medium();
    final r = await showFutureLoadingDialog(
      context: context,
      future: () => VibeLive.startLive(widget.room, DateTime.now().add(d)),
    );
    if (!mounted) return;
    if (r.result == true) Navigator.of(context).pop();
  }

  Future<void> _checkIn() async {
    final place = _picked;
    final name = TextEditingController();
    final arrive = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.viewInsetsOf(c).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Check in',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                "They're told when you get there. If you don't check in, "
                'they get your live location for an hour.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: Theme.of(c).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              if (place != null) ...[
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'Name of the place (Home, Office…)',
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _Choice(
                  icon: Icons.flag_rounded,
                  title: 'When I get to the pin',
                  sub: 'Checks in by itself when you arrive',
                  filled: true,
                  onTap: () => Navigator.of(c).pop(true),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'To check in on arriving, move the map to the place first.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(c).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              _Choice(
                icon: Icons.timer_outlined,
                title: 'After a timer',
                sub: 'You confirm you are OK when it ends',
                filled: place == null,
                onTap: () => Navigator.of(c).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
    final placeName = name.text.trim();
    name.dispose();
    if (arrive == null || !mounted) return;
    final until = await _pickUntil(
      context,
      arrive ? 'I should be there in' : 'Check in after',
      const [
        ('30 minutes', Duration(minutes: 30)),
        ('1 hour', Duration(hours: 1)),
        ('2 hours', Duration(hours: 2)),
      ],
    );
    if (until == null || !mounted) return;
    final r = await showFutureLoadingDialog(
      context: context,
      future: () => VibeLive.startCheckIn(
        widget.room,
        until,
        place: arrive ? place : null,
        name: arrive && placeName.isNotEmpty
            ? placeName
            : arrive
            ? _name?.$1
            : null,
      ),
    );
    if (!mounted) return;
    final id = r.result;
    if (id == null) return;
    final nav = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop();
    nav.push(
      MaterialPageRoute(builder: (_) => VibeCheckInView(eventId: id)),
    );
  }

  /// Sends the spot under the pin (or where you are).
  Future<void> sendAction() async {
    final spot = _spot;
    if (isSending || spot == null) return;
    setState(() => isSending = true);
    VibeHaptics.medium();
    final at = _approx
        ? LatLng(
            double.parse(spot.latitude.toStringAsFixed(2)),
            double.parse(spot.longitude.toStringAsFixed(2)),
          )
        : spot;
    final name = _name;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => VibeLive.sendPlace(
        widget.room,
        at,
        acc: _approx
            ? 1000
            : _picked == null
            ? position?.accuracy
            : null,
        // roughly: only the area, not the street
        name: _approx
            ? (name == null || name.$2.isEmpty ? null : (name.$2, ''))
            : name,
      ),
    );
    if (!mounted) return;
    if (result.error != null) {
      setState(() => isSending = false);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pos = position;
    final me = _me;
    final spot = _spot;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final client = widget.room.client;
    final myself = widget.room.unsafeGetUserFromMemoryOrFallback(
      client.userID!,
    );
    final String? notice = pos != null
        ? null
        : disabled
        ? L10n.of(context).locationDisabledNotice
        : denied
        ? L10n.of(context).locationPermissionDeniedNotice
        : error != null
        ? L10n.of(context).errorObtainingLocation(error.toString())
        : L10n.of(context).obtainingLocation;
    final title = spot == null
        ? null
        : _name?.$1 ??
              (_looking
                  ? 'Finding the street…'
                  : '${spot.latitude.toStringAsFixed(5)}, '
                        '${spot.longitude.toStringAsFixed(5)}');
    final sub = [
      if (_name != null && _name!.$2.isNotEmpty) _name!.$2,
      if (_approx)
        'about 1 km'
      else if (_picked == null && pos != null)
        'accurate to ${pos.accuracy.round()} m'
      else if (_picked != null)
        'the spot under the pin',
    ].join(' · ');
    const pinSize = 40.0;
    final pinBox = VibePicturePin.box(pinSize);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.88,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: ColoredBox(
          color: cs.surfaceContainerLowest,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: VibeMap(
                          key: _map,
                          center: me ?? const LatLng(20, 0),
                          zoom: me == null ? 2 : 16.5,
                          padding: const EdgeInsets.only(bottom: 84),
                          onDrag: _onDrag,
                          onIdle: _onIdle,
                          marks: [
                            if (me != null && (_picked != null || _approx))
                              VibeMapMark(
                                id: 'me',
                                at: me,
                                size: const Size.square(18),
                                child: const VibeMeDot(),
                              ),
                            if (me != null && _picked == null && !_approx)
                              VibeMapMark(
                                id: 'acc',
                                at: me,
                                meters: pos!.accuracy.clamp(5.0, 300.0),
                                size: Size.zero,
                                child: const SizedBox.shrink(),
                              ),
                            if (spot != null && _approx && !_dragging)
                              VibeMapMark(
                                id: 'area',
                                at: spot,
                                meters: 1000,
                                size: Size.zero,
                                child: const SizedBox.shrink(),
                              ),
                          ],
                        ),
                      ),
                      // the title over the top of the map
                      IgnorePointer(
                        child: Container(
                          height: 92,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                cs.surfaceContainerLowest,
                                cs.surfaceContainerLowest.withValues(alpha: 0),
                              ],
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const VibeSheetHandle(),
                              const SizedBox(height: 12),
                              Text(
                                'Send a location',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // the pin: your picture, lifted while you drag
                      if (spot != null)
                        IgnorePointer(
                          child: Center(
                            child: Transform.translate(
                              offset: Offset(0, -pinBox.height / 2),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(end: _dragging ? 1 : 0),
                                duration: still
                                    ? Duration.zero
                                    : Duration(
                                        milliseconds: _dragging ? 180 : 650,
                                      ),
                                curve: _dragging
                                    ? Curves.easeOut
                                    : Curves.elasticOut,
                                builder: (context, lift, _) => VibePicturePin(
                                  size: pinSize,
                                  lift: lift.clamp(-0.3, 1.2),
                                  picture: Avatar(
                                    mxContent: myself.avatarUrl,
                                    name: myself.calcDisplayname(),
                                    size: pinSize,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 14,
                        bottom: 86,
                        child: Column(
                          children: [
                            if (me != null)
                              VibeMapButton(
                                icon: Icons.my_location_rounded,
                                tip: 'Where I am',
                                onTap: _toMe,
                              ),
                            const SizedBox(height: 12),
                            VibeMapButton(
                              icon: Icons.view_in_ar_rounded,
                              tip: _tilted ? 'Flat' : '3D',
                              onTap: () {
                                setState(() => _tilted = !_tilted);
                                _map.currentState?.tilt(_tilted ? 50 : 0);
                              },
                            ),
                          ],
                        ),
                      ),
                      // the street under the pin
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 14,
                        child: Material(
                          color: cs.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(18),
                          elevation: 3,
                          shadowColor: Colors.black26,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                            child: Row(
                              children: [
                                if (notice != null &&
                                    !disabled &&
                                    !denied &&
                                    error == null)
                                  const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  Icon(
                                    Icons.place_rounded,
                                    size: 20,
                                    color: cs.primary,
                                  ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        notice ?? title ?? '',
                                        maxLines: notice == null ? 1 : 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: notice == null ? 15 : 13.5,
                                          fontWeight: notice == null
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                          color: cs.onSurface,
                                        ),
                                      ),
                                      if (notice == null && sub.isNotEmpty)
                                        Text(
                                          sub,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (notice == null && !VibePlaces.on)
                                  TextButton(
                                    onPressed: _askNames,
                                    child: const Text('Street name'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 58),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: spot == null || isSending ? null : sendAction,
                        icon: const Icon(Icons.place_rounded),
                        label: Text(
                          _approx ? 'Send roughly where' : 'Send this spot',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.sensors_rounded,
                                  size: 20,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Share live',
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'updates as you move',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                for (final (label, d, main) in const [
                                  ('15 min', Duration(minutes: 15), false),
                                  ('1 hour', Duration(hours: 1), true),
                                  ('8 hours', Duration(hours: 8), false),
                                ]) ...[
                                  _Length(
                                    label: label,
                                    main: main,
                                    onTap: pos == null ? null : () => _live(d),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 52),
                                shape: const StadiumBorder(),
                                backgroundColor: cs.surfaceContainer,
                                foregroundColor: cs.onSurface,
                              ),
                              onPressed: pos == null ? null : _checkIn,
                              icon: Icon(Icons.flag_rounded, color: cs.primary),
                              label: const Text('Check in'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Material(
                              color: cs.surfaceContainer,
                              shape: const StadiumBorder(),
                              child: InkWell(
                                customBorder: const StadiumBorder(),
                                onTap: () {
                                  VibeHaptics.selection();
                                  setState(() => _approx = !_approx);
                                },
                                child: SizedBox(
                                  height: 52,
                                  child: Row(
                                    children: [
                                      const SizedBox(width: 14),
                                      Icon(
                                        Icons.radio_button_checked_rounded,
                                        size: 20,
                                        color: cs.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Approximate',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: cs.onSurface,
                                          ),
                                        ),
                                      ),
                                      Transform.scale(
                                        scale: 0.75,
                                        child: Switch(
                                          value: _approx,
                                          onChanged: (v) {
                                            VibeHaptics.selection();
                                            setState(() => _approx = v);
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
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

/// 15 min / 1 hour / 8 hours: a tap starts sharing for that long.
class _Length extends StatelessWidget {
  final String label;
  final bool main;
  final VoidCallback? onTap;
  const _Length({required this.label, required this.main, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: main ? cs.primary : cs.surfaceContainerHighest,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: main ? cs.onPrimary : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// One way to check in, in the sheet.
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

/// How long: a few quick choices, or "Until…" a time you pick.
Future<DateTime?> _pickUntil(
  BuildContext context,
  String title,
  List<(String, Duration)> choices,
) async {
  final picked = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final (label, d) in choices)
              _Choice(
                icon: Icons.schedule_rounded,
                title: label,
                sub: 'Until ${VibeLive.time(DateTime.now().add(d).millisecondsSinceEpoch)}',
                filled: false,
                onTap: () => Navigator.of(c).pop(d),
              ),
            _Choice(
              icon: Icons.edit_calendar_rounded,
              title: 'Until…',
              sub: 'Pick the time',
              filled: false,
              onTap: () => Navigator.of(c).pop('pick'),
            ),
          ],
        ),
      ),
    ),
  );
  if (picked is Duration) return DateTime.now().add(picked);
  if (picked != 'pick' || !context.mounted) return null;
  final now = DateTime.now();
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
  );
  if (t == null) return null;
  var at = DateTime(now.year, now.month, now.day, t.hour, t.minute);
  // a time earlier than now means tomorrow
  if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
  return at;
}
