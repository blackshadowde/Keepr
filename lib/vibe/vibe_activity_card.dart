// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:vibe/vibe/vibe_status.dart';
import 'package:vibe/vibe/vibe_connections.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// "Listening now" on a profile: the cover, song and artist, and a bar
/// that moves while the song plays.
class VibeActivityCard extends StatefulWidget {
  final VibeStatus? status;
  final Client client;
  const VibeActivityCard({
    required this.status,
    required this.client,
    super.key,
  });

  @override
  State<VibeActivityCard> createState() => _VibeActivityCardState();
}

class _VibeActivityCardState extends State<VibeActivityCard> {
  Timer? _tick;

  Map<String, Object?>? get _a {
    final s = widget.status;
    final a = s?.activity;
    if (s == null || !s.active || a == null || a['kind'] != 'listening') {
      return null;
    }
    return a;
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _a != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    // its owner chose not to show it on the profile
    if (a == null || a['card'] == false) return const SizedBox.shrink();
    String str(String k) => a[k] is String ? a[k] as String : '';
    final app = str('app');
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: VibeListeningCard(
        title: str('title'),
        artist: str('artist'),
        album: str('album'),
        via: app.isEmpty ? 'music' : app,
        cover: a['cover'] is String ? a['cover'] as String : null,
        url: a['url'] is String ? a['url'] as String : null,
        duration: a['duration'] is int ? a['duration'] as int : 0,
        start: a['start'] is int ? a['start'] as int : 0,
        sad: a['sad'] == true,
        button: true,
        client: widget.client,
      ),
    );
  }
}
