// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/vibe_links.dart';
import 'package:vibe/vibe/vibe_low_data.dart';
import 'package:vibe/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Discord-style link preview card under a text message.
///
/// The preview is fetched by your homeserver (Matrix `preview_url`), so the
/// server learns which links appear in your chats. That is why it can be
/// switched off in Settings → Security & sign-in.
class VibeLinkPreview extends StatelessWidget {
  final Event event;

  /// Inside the message's card: an inset card, the picture on top.
  final bool inCard;
  const VibeLinkPreview({required this.event, this.inCard = false, super.key});

  static final RegExp _urlRegex = RegExp(
    r'https?://[^\s<>"]+[^\s<>".,;:!?)\]}' "'" r']',
    caseSensitive: false,
  );

  /// One request per link per app run.
  static final Map<String, Future<PreviewForUrl?>> _cache = {};

  /// The ones already here.
  static final Map<String, PreviewForUrl?> _got = {};

  /// The link at the start or end of [e]'s text, when it gets a preview
  /// card: the card opens it, so the text needn't show it too.
  static String? edgeUrl(Event e) {
    if (!enabledFor(e.room) || onlyLink(e)) return null;
    final url = firstUrl(e);
    if (url == null) return null;
    final body = e.body.trim();
    return body.startsWith(url) || body.endsWith(url) ? url : null;
  }

  static bool _shows(PreviewForUrl? p) =>
      p != null &&
      (_str(p, 'og:title') != null ||
          _str(p, 'og:description') != null ||
          (!VibeLowData.on && p.ogImage != null));

  /// Whether [url]'s card shows; null while it loads.
  static bool? showsNow(String url) =>
      _got.containsKey(url) ? _shows(_got[url]) : null;

  static Future<bool> shows(Event e, String url) => _fetch(
    e.room.client,
    url,
    e.originServerTs.millisecondsSinceEpoch,
  ).then(_shows);

  /// [html] without [url] at its start or end (as written, or as a link).
  static String withoutEdge(String html, String url) {
    final forms = {url, url.replaceAll('&', '&amp;')}.map(RegExp.escape).join('|');
    final link = '(?:<a\\b[^>]*>\\s*(?:$forms)\\s*</a>|(?:$forms))';
    const gap = r'(?:\s|<br\s*/?>)*';
    return html
        .replaceFirst(RegExp('^$gap$link$gap', caseSensitive: false), '')
        .replaceFirst(RegExp('$gap$link$gap' r'$', caseSensitive: false), '');
  }

  static String? firstUrl(Event e) {
    if (e.redacted || e.type != EventTypes.Message) return null;
    final type = e.messageType;
    if (type != MessageTypes.Text &&
        type != MessageTypes.Notice &&
        type != MessageTypes.Emote) {
      return null;
    }
    final m = _urlRegex.firstMatch(e.body);
    return m?.group(0);
  }

  /// The message is just one link: the card stands in for the text (the
  /// link itself shows only while loading or when there's no preview).
  /// Previews are fetched by the server, which would then see links sent
  /// in encrypted chats: there they're off unless you switch them on.
  static bool enabledFor(Room room) =>
      AppSettings.vibeLinkPreviews.value &&
      (!room.encrypted || AppSettings.vibeLinkPreviewsEncrypted.value);

  static bool onlyLink(Event e) {
    if (!enabledFor(e.room)) return false;
    final url = firstUrl(e);
    return url != null && e.body.trim() == url;
  }

  Widget _plainLink(BuildContext context, String url) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => launchUrlString(url, mode: LaunchMode.externalApplication),
      onLongPress: () => VibeLinks.options(context, url),
      child: Text(
        url,
        style: TextStyle(
          color: cs.primary,
          decoration: TextDecoration.underline,
          decorationColor: cs.primary,
        ),
      ),
    );
  }

  static Future<PreviewForUrl?> _fetch(Client client, String url, int ts) {
    return _cache.putIfAbsent(url, () async {
      final uri = Uri.parse(url);
      PreviewForUrl? p;
      try {
        p = await client.getUrlPreviewAuthed(uri, ts: ts);
      } catch (_) {
        try {
          // Older servers without authenticated media.
          p = await client.getUrlPreview(uri, ts: ts);
        } catch (e) {
          Logs().v('Keepr link preview failed for $url', e);
        }
      }
      return _got[url] = p;
    });
  }

  static String? _str(PreviewForUrl p, String key) {
    final v = p.additionalProperties[key];
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  /// Music links (Spotify, YouTube Music, ...) get a player-style card.
  static (String, Color)? _music(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    bool on(String h) => host == h || host.endsWith('.$h');
    if (on('open.spotify.com') || on('spotify.link')) {
      return ('Spotify', const Color(0xFF1DB954));
    }
    if (on('music.youtube.com')) return ('YouTube Music', const Color(0xFFFF0033));
    if (on('music.apple.com')) return ('Apple Music', const Color(0xFFFA243C));
    if (on('jiosaavn.com')) return ('JioSaavn', const Color(0xFF2BC5B4));
    if (on('soundcloud.com')) return ('SoundCloud', const Color(0xFFFF5500));
    if (on('gaana.com')) return ('Gaana', const Color(0xFFE72C30));
    if (on('wynk.in')) return ('Wynk Music', const Color(0xFFE5112E));
    if (on('deezer.com') || on('deezer.page.link')) {
      return ('Deezer', const Color(0xFFA238FF));
    }
    if (on('tidal.com')) return ('TIDAL', const Color(0xFF00FFFF));
    if (on('music.amazon.com') || on('music.amazon.in')) {
      return ('Amazon Music', const Color(0xFF25D1DA));
    }
    if (on('bandcamp.com')) return ('Bandcamp', const Color(0xFF1DA0C3));
    return null;
  }

  Widget _musicCard(
    BuildContext context,
    String url,
    (String, Color) music,
    String? title,
    String? desc,
    Uri? image,
  ) {
    final cs = Theme.of(context).colorScheme;
    final (app, brand) = music;
    void open() => launchUrlString(url, mode: LaunchMode.externalApplication);
    final onBrand = brand.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    // Discord's "Listening to Spotify" card: plain surface, app line on
    // top, big cover, title and artist, then a play button.
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Material(
          color: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: open,
            onLongPress: () => VibeLinks.options(context, url),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: brand,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.graphic_eq, size: 12, color: onBrand),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Listen on $app',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Icon(Icons.open_in_new, size: 16, color: cs.onSurfaceVariant),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 76,
                          height: 76,
                          child: image == null
                              ? ColoredBox(
                                  color: brand.withValues(alpha: 0.25),
                                  child: Icon(Icons.music_note, color: brand),
                                )
                              : MxcImage(
                                  client: event.room.client,
                                  uri: image,
                                  width: 76,
                                  height: 76,
                                  fit: BoxFit.cover,
                                  isThumbnail: true,
                                  cacheKey: 'vibe_link_preview_$image',
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (title != null)
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                              ),
                            if (desc != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                desc,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.3,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: open,
                    style: FilledButton.styleFrom(
                      backgroundColor: brand,
                      foregroundColor: onBrand,
                      minimumSize: const Size.fromHeight(40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      'Play on $app',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!enabledFor(event.room)) return const SizedBox.shrink();
    final url = firstUrl(event);
    if (url == null) return const SizedBox.shrink();

    return FutureBuilder<PreviewForUrl?>(
      future: _fetch(
        event.room.client,
        url,
        event.originServerTs.millisecondsSinceEpoch,
      ),
      builder: (context, snap) {
        final p = snap.data;
        final only = onlyLink(event);
        if (p == null) {
          return only ? _plainLink(context, url) : const SizedBox.shrink();
        }
        final title = _str(p, 'og:title');
        final desc = _str(p, 'og:description');
        final site = _str(p, 'og:site_name') ?? Uri.tryParse(url)?.host;
        final image = VibeLowData.on ? null : p.ogImage;
        if (title == null && desc == null && image == null) {
          return only ? _plainLink(context, url) : const SizedBox.shrink();
        }
        final music = _music(url);
        if (music != null) {
          return _musicCard(context, url, music, title, desc, image);
        }
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        if (inCard) return _inCard(context, url, site, title, desc, image);
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () =>
                    launchUrlString(url, mode: LaunchMode.externalApplication),
                onLongPress: () => VibeLinks.options(context, url),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: cs.outlineVariant, width: 4),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (site != null)
                        Text(
                          site,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      if (title != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF00A8FC),
                          ),
                        ),
                      ],
                      if (desc != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          desc,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            color: cs.onSurface.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                      if (image != null) ...[
                        const SizedBox(height: 10),
                        LayoutBuilder(
                          builder: (context, c) {
                            final w = c.maxWidth.isFinite ? c.maxWidth : 300.0;
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: MxcImage(
                                client: event.room.client,
                                uri: image,
                                width: w,
                                height: w * 0.52,
                                fit: BoxFit.cover,
                                isThumbnail: true,
                                cacheKey: 'vibe_link_preview_$image',
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// In the message's card: an inset card with the picture across its top,
  /// then the site, title and words. Tap opens the link, hold for options.
  Widget _inCard(
    BuildContext context,
    String url,
    String? site,
    String? title,
    String? desc,
    Uri? image,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      // the message's hold finds it too
      child: MetaData(
        metaData: VibeLinkHit(url),
        behavior: HitTestBehavior.translucent,
        child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Material(
          color: dark
              ? Colors.black.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () =>
                launchUrlString(url, mode: LaunchMode.externalApplication),
            onLongPress: () => VibeLinks.options(context, url),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (image != null)
                  LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth.isFinite ? c.maxWidth : 300.0;
                      return MxcImage(
                        client: event.room.client,
                        uri: image,
                        width: w,
                        height: w * 0.52,
                        fit: BoxFit.cover,
                        isThumbnail: true,
                        cacheKey: 'vibe_link_preview_$image',
                      );
                    },
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (site != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.link_rounded, size: 14, color: cs.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                site,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      if (title != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                      if (desc != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
