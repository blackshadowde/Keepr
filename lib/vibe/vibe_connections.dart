// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/utils/url_launcher.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_status.dart';
import 'package:vibe/widgets/mxc_image.dart';

/// A song someone is playing, from a connected account.
class VibeTrack {
  final String title, artist, album, via;
  final String? cover, url;
  final int duration; // ms, 0 when the service doesn't say
  final int start; // when it started (ms), our best guess
  final bool sad;
  const VibeTrack({
    required this.title,
    required this.artist,
    this.album = '',
    required this.via,
    this.cover,
    this.url,
    this.duration = 0,
    required this.start,
    this.sad = false,
  });

  String get key => '$title|$artist';

  VibeTrack copyWith({int? duration, int? start, bool? sad}) => VibeTrack(
    title: title,
    artist: artist,
    album: album,
    via: via,
    cover: cover,
    url: url,
    duration: duration ?? this.duration,
    start: start ?? this.start,
    sad: sad ?? this.sad,
  );
}

/// The services you can connect. Only your username is needed.
enum VibeService {
  lastfm('Last.fm', Icons.graphic_eq_rounded, Color(0xFFFFDAD6), Color(0xFFB3261E), Color(0xFF5C1A15), Color(0xFFFFB4AB)),
  listenbrainz('ListenBrainz', Icons.multitrack_audio_rounded, Color(0xFFFFE0C2), Color(0xFF8A4B00), Color(0xFF4A2A07), Color(0xFFFFB870));

  final String label;
  final IconData icon;
  final Color tile, ink, darkTile, darkInk;
  const VibeService(this.label, this.icon, this.tile, this.ink, this.darkTile, this.darkInk);
}

/// Connections: what you're listening to. Your phone asks the connected
/// service what you're playing every 30 seconds while Keepr is running and
/// shares it with the people you chat with, like your status (the profile
/// card and the line by your name). No notification access is needed.
abstract class VibeConnections {
  /// Set when the app is built (a repository secret), never in the code.
  static const _lastfmKey = String.fromEnvironment('LASTFM_API_KEY');
  static bool available(VibeService s) =>
      s != VibeService.lastfm || _lastfmKey.isNotEmpty;

  static const _kService = 'keepr.conn.service';
  static const _kUser = 'keepr.conn.user';
  static const _kOn = 'keepr.conn.on';
  static const _kProfile = 'keepr.conn.profile';
  static const _kPill = 'keepr.conn.pill';
  static const _kPrev = 'keepr.conn.prev';

  /// What you're playing right now (Bujji listens along).
  static final playing = ValueNotifier<VibeTrack?>(null);

  /// Bumped when a connection or its settings change.
  static final changed = ValueNotifier<int>(0);

  static VibeService? get service {
    final n = AppSettings.store.getString(_kService);
    for (final s in VibeService.values) {
      if (s.name == n) return s;
    }
    return null;
  }

  static String get user => AppSettings.store.getString(_kUser) ?? '';
  static bool get sharing => AppSettings.store.getBool(_kOn) ?? true;
  static bool get onProfile => AppSettings.store.getBool(_kProfile) ?? true;
  static bool get inPill => AppSettings.store.getBool(_kPill) ?? true;

  static Client? _client;
  static Timer? _timer;
  static bool _busy = false;

  /// Called once per account; follows the first one.
  static void start(Client client) {
    _client ??= client;
    _restart();
  }

  static void _restart() {
    _timer?.cancel();
    _timer = null;
    if (_client == null || service == null || !sharing) return;
    poke();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => poke());
  }

  static Future<void> connect(
    VibeService s,
    String name, {
    required bool profile,
    required bool pill,
  }) async {
    await AppSettings.store.setString(_kService, s.name);
    await AppSettings.store.setString(_kUser, name.trim());
    await AppSettings.store.setBool(_kOn, true);
    await AppSettings.store.setBool(_kProfile, profile);
    await AppSettings.store.setBool(_kPill, pill);
    _last = null;
    changed.value++;
    _restart();
  }

  static Future<void> disconnect() async {
    await AppSettings.store.remove(_kService);
    await AppSettings.store.remove(_kUser);
    playing.value = null;
    changed.value++;
    _restart();
    await _restore();
  }

  /// Sharing on or off, keeping the account.
  static Future<void> setSharing(bool on) async {
    await AppSettings.store.setBool(_kOn, on);
    changed.value++;
    if (!on) {
      playing.value = null;
      await _restore();
    }
    _restart();
  }

  // ---- asking the services

  /// Whether [name] has an account, and what it's playing now (if anything).
  static Future<({bool found, VibeTrack? track})> lookUp(
    VibeService s,
    String name,
  ) async {
    name = name.trim();
    if (name.isEmpty || !available(s)) return (found: false, track: null);
    try {
      return switch (s) {
        VibeService.lastfm => await _lastfm(name),
        VibeService.listenbrainz => await _listenbrainz(name),
      };
    } catch (e) {
      Logs().v('Connections: could not ask ${s.label}', e);
      return (found: false, track: null);
    }
  }

  static Future<({bool found, VibeTrack? track})> _lastfm(String name) async {
    final r = await http.get(Uri.https('ws.audioscrobbler.com', '/2.0/', {
      'method': 'user.getrecenttracks',
      'user': name,
      'api_key': _lastfmKey,
      'format': 'json',
      'limit': '1',
    })).timeout(const Duration(seconds: 12));
    final j = jsonDecode(r.body);
    if (j is! Map || j['error'] != null) return (found: false, track: null);
    final list = (j['recenttracks'] as Map?)?['track'];
    final t = list is List && list.isNotEmpty ? list.first : list;
    if (t is! Map) return (found: true, track: null);
    final now = (t['@attr'] as Map?)?['nowplaying'] == 'true';
    if (!now) return (found: true, track: null);
    String text(Object? o) => o is Map ? '${o['#text'] ?? ''}' : '${o ?? ''}';
    String? cover;
    final images = t['image'];
    if (images is List) {
      for (final i in images.reversed) {
        final u = i is Map ? '${i['#text'] ?? ''}' : '';
        if (u.startsWith('https://')) {
          cover = u;
          break;
        }
      }
    }
    return (
      found: true,
      track: VibeTrack(
        title: text(t['name']),
        artist: text(t['artist']),
        album: text(t['album']),
        via: VibeService.lastfm.label,
        cover: cover,
        url: t['url'] is String ? t['url'] as String : null,
        start: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  static Future<({bool found, VibeTrack? track})> _listenbrainz(String name) async {
    final r = await http
        .get(Uri.https('api.listenbrainz.org', '/1/user/${Uri.encodeComponent(name)}/playing-now'))
        .timeout(const Duration(seconds: 12));
    if (r.statusCode == 404) return (found: false, track: null);
    final j = jsonDecode(r.body);
    final payload = j is Map ? j['payload'] : null;
    final listens = payload is Map ? payload['listens'] : null;
    if (listens is! List || listens.isEmpty) return (found: true, track: null);
    final m = (listens.first as Map?)?['track_metadata'];
    if (m is! Map) return (found: true, track: null);
    final info = m['additional_info'] is Map ? m['additional_info'] as Map : const {};
    final mbid = info['release_mbid'];
    final ms = info['duration_ms'] ?? (info['duration'] is num ? (info['duration'] as num) * 1000 : null);
    return (
      found: true,
      track: VibeTrack(
        title: '${m['track_name'] ?? ''}',
        artist: '${m['artist_name'] ?? ''}',
        album: '${m['release_name'] ?? ''}',
        via: VibeService.listenbrainz.label,
        cover: mbid is String && mbid.isNotEmpty
            ? 'https://coverartarchive.org/release/$mbid/front-250'
            : null,
        url: info['origin_url'] is String
            ? info['origin_url'] as String
            : 'https://listenbrainz.org/user/${Uri.encodeComponent(name)}/',
        duration: ms is num ? ms.round() : 0,
        start: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  // sad songs: from the song's tags when Last.fm knows it, else its words
  static const _sadTags = {
    'sad', 'melancholy', 'melancholic', 'depressing', 'depressive', 'heartbreak',
    'heartbroken', 'breakup', 'break up', 'lonely', 'grief', 'sorrow', 'tearjerker',
    'crying', 'sad songs', 'emotional', 'heartache',
  };
  static final _sadWords = RegExp(
    r'\b(sad|cry|crying|tears?|alone|lonely|goodbye|broken|heartbreak|hurts?|miss you|sorrow|lost)\b',
    caseSensitive: false,
  );

  static Future<VibeTrack> _more(VibeTrack t) async {
    var sad = _sadWords.hasMatch(t.title);
    var duration = t.duration;
    if (_lastfmKey.isNotEmpty) {
      try {
        final r = await http.get(Uri.https('ws.audioscrobbler.com', '/2.0/', {
          'method': 'track.getinfo',
          'artist': t.artist,
          'track': t.title,
          'api_key': _lastfmKey,
          'format': 'json',
          'autocorrect': '1',
        })).timeout(const Duration(seconds: 12));
        final j = jsonDecode(r.body);
        final info = j is Map ? j['track'] : null;
        if (info is Map) {
          final d = int.tryParse('${info['duration'] ?? ''}') ?? 0;
          if (duration == 0 && d > 0) duration = d;
          final tags = (info['toptags'] as Map?)?['tag'];
          if (tags is List) {
            final names = tags
                .take(8)
                .map((x) => x is Map ? '${x['name']}'.toLowerCase() : '')
                .toSet();
            if (names.any(_sadTags.contains)) sad = true;
          }
        }
      } catch (_) {}
    }
    return t.copyWith(duration: duration, sad: sad);
  }

  // ---- sharing it

  static VibeTrack? _last;

  /// Ask now (also every 30 s).
  static Future<void> poke() async {
    final client = _client, s = service;
    if (client == null || s == null || !sharing || _busy) return;
    _busy = true;
    try {
      final got = (await lookUp(s, user)).track;
      if (got == null) {
        _last = null;
        playing.value = null;
        await _restore();
        return;
      }
      var t = got;
      final last = _last;
      if (last != null && last.key == t.key) {
        t = last; // same song: keep when it started, its length and mood
      } else {
        // it started a little before we saw it
        t = await _more(t.copyWith(start: DateTime.now().millisecondsSinceEpoch - 10000));
        _last = t;
      }
      playing.value = t;
      await _publish(client, t);
    } catch (e, st) {
      Logs().w('Connections: sharing what you play failed', e, st);
    } finally {
      _busy = false;
    }
  }

  static bool _ours(VibeStatus? s) => s?.activity?['by'] == 'connection';

  static Future<void> _publish(Client client, VibeTrack t) async {
    final text = t.artist.isEmpty ? t.title : '${t.title} · ${t.artist}';
    final now = DateTime.now().millisecondsSinceEpoch;
    final mine = VibeStatus.mine(client);
    final ours = mine != null && _ours(mine) && mine.active;
    final left = (mine?.untilMs ?? 0) - now;
    // same song and not about to run out: nothing to send
    if (ours && mine.text == text && left > 3 * 60 * 1000) return;
    if (!ours) {
      // the status you had, to put back afterwards
      await AppSettings.store.setString(_kPrev, jsonEncode(mine?.toContent() ?? const {}));
    }
    await VibeStatus.publish(
      client,
      VibeStatus(
        text: text,
        // runs out by itself if Keepr is closed mid-song
        untilMs: now + 10 * 60 * 1000,
        activity: {
          'kind': 'listening',
          'by': 'connection',
          'app': t.via,
          'title': t.title,
          'artist': t.artist,
          if (t.album.isNotEmpty) 'album': t.album,
          if (t.duration > 0) 'duration': t.duration,
          'start': t.start,
          'cover': ?t.cover,
          'url': ?t.url,
          if (t.sad) 'sad': true,
          if (!onProfile) 'card': false,
          if (!inPill) 'pill': false,
        },
      ),
    );
  }

  static Future<void> _restore() async {
    final client = _client;
    final raw = AppSettings.store.getString(_kPrev);
    if (client == null || raw == null) return;
    await AppSettings.store.remove(_kPrev);
    final mine = VibeStatus.mine(client);
    // you changed it yourself meanwhile: keep yours
    if (mine != null && mine.active && !_ours(mine)) return;
    var prev = const VibeStatus();
    try {
      prev = VibeStatus.fromContent(Map<String, Object?>.from(jsonDecode(raw) as Map));
    } catch (_) {}
    if (!prev.active) prev = const VibeStatus();
    await VibeStatus.publish(client, prev);
  }
}

/// The service's little tile: its colour and a plain icon.
class VibeServiceTile extends StatelessWidget {
  final VibeService service;
  final double size;
  const VibeServiceTile(this.service, {this.size = 40, super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: dark ? service.darkTile : service.tile,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(service.icon, size: size * 0.55, color: dark ? service.darkInk : service.ink),
    );
  }
}

/// "Listening now": the cover, the song, the artist and album, and a bar
/// that moves while it plays (bars that bounce when its length isn't known).
class VibeListeningCard extends StatefulWidget {
  final String title, artist, album, via;
  final String? cover, url;
  final int duration, start;
  final bool sad, button;
  final Client? client;
  const VibeListeningCard({
    required this.title,
    required this.artist,
    this.album = '',
    required this.via,
    this.cover,
    this.url,
    this.duration = 0,
    required this.start,
    this.sad = false,
    this.button = false,
    this.client,
    super.key,
  });

  factory VibeListeningCard.of(VibeTrack t, {bool button = false, Key? key}) => VibeListeningCard(
    key: key,
    title: t.title,
    artist: t.artist,
    album: t.album,
    via: t.via,
    cover: t.cover,
    url: t.url,
    duration: t.duration,
    start: t.start,
    sad: t.sad,
    button: button,
  );

  @override
  State<VibeListeningCard> createState() => _VibeListeningCardState();
}

class _VibeListeningCardState extends State<VibeListeningCard> with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  static String _clock(int ms) {
    final s = (ms / 1000).floor();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _cover(ColorScheme cs) {
    final c = widget.cover;
    final placeholder = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.4, -0.5),
          radius: 1.1,
          colors: [Color(0xFFFFB36B), Color(0xFFE2577B), Color(0xFF4B2A7B)],
        ),
      ),
      child: Icon(Icons.music_note_rounded, color: Colors.white.withValues(alpha: 0.85)),
    );
    Widget img;
    if (c == null || c.isEmpty) {
      img = placeholder;
    } else if (c.startsWith('mxc://') && widget.client != null) {
      img = MxcImage(
        client: widget.client!,
        uri: Uri.parse(c),
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        isThumbnail: true,
        cacheKey: 'vibe_activity_$c',
      );
    } else if (c.startsWith('https://')) {
      img = Image.network(
        c,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
      );
    } else {
      img = placeholder;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(dimension: 56, child: img),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant);
    final d = widget.duration;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.headphones_rounded, size: 15, color: cs.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'LISTENING NOW · ${widget.via.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _cover(cs),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [widget.artist, widget.album].where((x) => x.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    AnimatedBuilder(
                      animation: _beat,
                      builder: (context, _) {
                        if (d <= 0) {
                          // its length isn't known: a few bars bounce along
                          return Row(
                            children: [
                              for (var i = 0; i < 5; i++)
                                Container(
                                  width: 3,
                                  height: 4 + 9 * (0.5 + 0.5 * math.sin((_beat.value + i * 0.23) * math.pi * 2)).abs(),
                                  margin: const EdgeInsets.only(right: 3),
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              const SizedBox(width: 6),
                              Text('Playing now', style: sub),
                            ],
                          );
                        }
                        final at = (DateTime.now().millisecondsSinceEpoch - widget.start).clamp(0, d);
                        return Row(
                          children: [
                            Text(_clock(at), style: sub),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: at / d,
                                  minHeight: 4,
                                  color: cs.primary,
                                  backgroundColor: cs.surfaceContainerHighest,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(_clock(d), style: sub),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.button && widget.url != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: VibePressable(
                child: OutlinedButton.icon(
                  onPressed: () => UrlLauncher(context, widget.url!).launchUrl(),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text('Open on ${widget.via}'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// On your profile: the accounts you can connect, and what's playing.
class VibeConnectionsCard extends StatelessWidget {
  final Color color;
  const VibeConnectionsCard({required this.color, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: VibeConnections.changed,
      builder: (context, _, _) => ValueListenableBuilder<VibeTrack?>(
        valueListenable: VibeConnections.playing,
        builder: (context, now, _) {
          final on = VibeConnections.service;
          Widget row(VibeService s) {
            final mine = on == s;
            final ready = VibeConnections.available(s);
            return VibePressable(
              child: InkWell(
                onTap: ready ? () => VibeConnectSheet.show(context, s) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      AnimatedScale(
                        scale: mine ? 1.08 : 1,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        child: VibeServiceTile(s),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.label, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              mine
                                  ? '@${VibeConnections.user} · shows what you play'
                                  : ready
                                  ? 'Not connected'
                                  : 'Not in this version of Keepr',
                              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      if (mine)
                        Switch(
                          value: VibeConnections.sharing,
                          onChanged: (v) {
                            VibeHaptics.selection();
                            VibeConnections.setSharing(v);
                          },
                        )
                      else if (ready)
                        OutlinedButton(
                          onPressed: () => VibeConnectSheet.show(context, s),
                          child: const Text('Connect'),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }

          return Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                  child: Text(
                    'CONNECTIONS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.9,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                row(VibeService.lastfm),
                // what's playing, right under the account it came from
                AnimatedSize(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  child: on == VibeService.lastfm && now != null && VibeConnections.sharing
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: VibeListeningCard.of(now),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                row(VibeService.listenbrainz),
                AnimatedSize(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  child: on == VibeService.listenbrainz && now != null && VibeConnections.sharing
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: VibeListeningCard.of(now),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_rounded, size: 18, color: cs.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Use Spotify, YouTube Music or another app? Link it to Last.fm or '
                          'ListenBrainz once, and what you play shows here.',
                          style: TextStyle(fontSize: 12.5, height: 1.45, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Connect a service: type your username, Keepr checks it and shows what
/// you're playing right away.
class VibeConnectSheet extends StatefulWidget {
  final VibeService service;
  const VibeConnectSheet({required this.service, super.key});

  static Future<void> show(BuildContext context, VibeService s) => showVibeSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => VibeConnectSheet(service: s),
  );

  @override
  State<VibeConnectSheet> createState() => _VibeConnectSheetState();
}

class _VibeConnectSheetState extends State<VibeConnectSheet> {
  late final _name = TextEditingController(
    text: VibeConnections.service == widget.service ? VibeConnections.user : '',
  );
  Timer? _wait;
  bool _checking = false, _done = false;
  ({bool found, VibeTrack? track})? _result;
  String _checked = '';
  late bool _profile = VibeConnections.onProfile, _pill = VibeConnections.inPill;

  bool get _mine => VibeConnections.service == widget.service;

  @override
  void initState() {
    super.initState();
    if (_name.text.isNotEmpty) _check();
  }

  @override
  void dispose() {
    _wait?.cancel();
    _name.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _wait?.cancel();
    setState(() => _result = null);
    // checks once you stop typing for a moment
    _wait = Timer(const Duration(milliseconds: 650), _check);
  }

  Future<void> _check() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _checking = true);
    final r = await VibeConnections.lookUp(widget.service, name);
    if (!mounted || _name.text.trim() != name) return;
    if (r.found) VibeHaptics.light();
    setState(() {
      _checking = false;
      _result = r;
      _checked = name;
    });
  }

  Future<void> _connect() async {
    VibeHaptics.medium();
    await VibeConnections.connect(widget.service, _checked, profile: _profile, pill: _pill);
    if (!mounted) return;
    setState(() => _done = true);
    await Future<void>.delayed(const Duration(milliseconds: 520));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.service;
    final r = _result;
    final ok = r != null && r.found && _checked == _name.text.trim();
    Widget toggle(IconData icon, String title, String sub, bool v, ValueChanged<bool> on) => SwitchListTile(
      value: v,
      onChanged: (x) {
        VibeHaptics.selection();
        on(x);
      },
      secondary: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 20, color: cs.onSurface),
      ),
      title: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
      subtitle: Text(sub, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              VibeStagger(
                index: 0,
                dy: 10,
                child: Row(
                  children: [
                    AnimatedScale(
                      scale: ok ? 1.1 : 1,
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      child: VibeServiceTile(s, size: 52),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Connect ${s.label}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(
                            'Only your username. No password.',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'YOUR ${s.label.toUpperCase()} USERNAME',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                autofocus: _name.text.isEmpty,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onChanged: _changed,
                onSubmitted: (_) => _check(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.person_rounded, color: cs.onSurfaceVariant),
                  suffixIcon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: _checking
                        ? const Padding(
                            key: ValueKey('wait'),
                            padding: EdgeInsets.all(14),
                            child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : ok
                        ? Padding(
                            key: const ValueKey('ok'),
                            padding: const EdgeInsets.all(12),
                            child: Container(
                              decoration: const BoxDecoration(color: Color(0xFF22A55B), shape: BoxShape.circle),
                              child: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('none')),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: cs.primary, width: 2),
                  ),
                ),
              ),
              // what it found: playing now, nothing playing, or no such account
              AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: r == null || _checked != _name.text.trim()
                      ? const SizedBox(width: double.infinity, height: 8)
                      : !r.found
                      ? Padding(
                          key: const ValueKey('none'),
                          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                          child: Text(
                            'No ${s.label} account with that name',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: cs.error),
                          ),
                        )
                      : r.track == null
                      ? Padding(
                          key: const ValueKey('quiet'),
                          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                          child: Text(
                            'Found you. Nothing is playing right now; play something and it shows up.',
                            style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant),
                          ),
                        )
                      : Padding(
                          key: ValueKey(r.track!.key),
                          padding: const EdgeInsets.only(top: 14),
                          child: VibeListeningCard.of(r.track!),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    toggle(Icons.person_rounded, 'Show on my profile', 'People you chat with see it', _profile,
                        (v) => setState(() => _profile = v)),
                    toggle(Icons.label_rounded, 'Show in my pill', 'Next to your name on your messages', _pill,
                        (v) => setState(() => _pill = v)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_mine)
                    TextButton(
                      onPressed: () async {
                        VibeHaptics.medium();
                        await VibeConnections.disconnect();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      child: Text('Disconnect', style: TextStyle(color: cs.error)),
                    ),
                  const Spacer(),
                  VibePressable(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  VibePressable(
                    child: FilledButton(
                      onPressed: ok && !_done ? _connect : null,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                        child: _done
                            ? const Icon(Icons.check_rounded, key: ValueKey('done'), size: 20)
                            : Text(_mine ? 'Save' : 'Connect', key: const ValueKey('go')),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
