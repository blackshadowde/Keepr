// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/vibe_glass.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';

/// A theme listed in HyDE's gallery (github.com/HyDE-Project/hyde-gallery).
class VibeHydeGalleryTheme {
  final String name, link, author, description;
  final List<Color> colors;
  const VibeHydeGalleryTheme(
    this.name,
    this.link,
    this.author,
    this.description,
    this.colors,
  );
}

/// Import HyDE themes, like `hyde theme import` on Hyprland: pick one from
/// HyDE's gallery or paste a theme's GitHub link. Keepr reads the theme's
/// colours (its `theme.dcol`) and finds its wallpapers folder; the theme then
/// sits next to the built-in palettes of the Glass look. Nothing of the theme
/// is shipped with Keepr: it is fetched from its author's GitHub when you
/// import it.
abstract class VibeHydeImport {
  static const _key = 'chat.keepr.glass_imported';
  static const _themes = 'Configs/.config/hyde/themes/';
  static final _pic = RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false);

  static List<Map<String, Object?>>? _entries;

  static List<Map<String, Object?>> get _list {
    final e = _entries;
    if (e != null) return e;
    try {
      final raw = AppSettings.store.getString(_key);
      return _entries = raw == null
          ? []
          : [
              for (final m in jsonDecode(raw) as List)
                if (m is Map) m.cast<String, Object?>(),
            ];
    } catch (_) {
      return _entries = [];
    }
  }

  /// The imported themes, as Glass palettes.
  static List<VibeGlassPalette> get palettes => [
    for (final m in _list) _fromMap(m),
  ];

  static bool isImported(String id) => _list.any((m) => m['id'] == id);

  static VibeGlassPalette _fromMap(Map<String, Object?> m) {
    Color c(String k) => Color((m[k] as int?) ?? 0xFF888888);
    return VibeGlassPalette(
      id: m['id'] as String,
      name: m['name'] as String,
      hydeRepo: m['repo'] as String? ?? 'HyDE-Project/hyde-themes',
      hydeBranch: m['branch'] as String?,
      hydeDir: m['dir'] as String?,
      accent: c('accent'),
      onAccent: c('onAccent'),
      base: c('base'),
      mantle: c('mantle'),
      crust: c('crust'),
      s0: c('s0'),
      s1: c('s1'),
      text: c('text'),
      sub: c('sub'),
      tert: c('tert'),
    );
  }

  static Map<String, Object?> _toMap(VibeGlassPalette p) => {
    'id': p.id,
    'name': p.name,
    'repo': p.hydeRepo,
    'branch': p.hydeBranch,
    'dir': p.hydeDir,
    'accent': p.accent.toARGB32(),
    'onAccent': p.onAccent.toARGB32(),
    'base': p.base.toARGB32(),
    'mantle': p.mantle.toARGB32(),
    'crust': p.crust.toARGB32(),
    's0': p.s0.toARGB32(),
    's1': p.s1.toARGB32(),
    'text': p.text.toARGB32(),
    'sub': p.sub.toARGB32(),
    'tert': p.tert.toARGB32(),
  };

  static Future<void> _save() =>
      AppSettings.store.setString(_key, jsonEncode(_list));

  static Future<void> remove(String id) async {
    _list.removeWhere((m) => m['id'] == id);
    await _save();
    if (VibeGlass.paletteId == id) {
      await VibeGlass.setPalette('wallbash');
    } else {
      VibeGlass.version.value++;
    }
  }

  // ---- fetching -----------------------------------------------------------

  static Future<Map<String, Object?>> _api(
    String path, [
    Map<String, String>? query,
  ]) async {
    final r = await http.get(
      Uri.https('api.github.com', path, query),
      headers: {'Accept': 'application/vnd.github+json'},
    );
    if (r.statusCode == 403 || r.statusCode == 429) {
      throw Exception('GitHub is busy. Try again in a while');
    }
    if (r.statusCode == 404) throw Exception('That repository wasn\'t found');
    if (r.statusCode != 200) throw Exception('GitHub said ${r.statusCode}');
    return (jsonDecode(r.body) as Map).cast<String, Object?>();
  }

  /// HyDE's gallery: every listed theme with its two preview colours.
  static Future<List<VibeHydeGalleryTheme>> gallery() async {
    final r = await http.get(
      Uri.https(
        'raw.githubusercontent.com',
        '/HyDE-Project/hyde-gallery/master/hyde-themes.json',
      ),
    );
    if (r.statusCode != 200) throw Exception('Gallery: ${r.statusCode}');
    final out = <VibeHydeGalleryTheme>[];
    for (final t in jsonDecode(utf8.decode(r.bodyBytes)) as List) {
      if (t is! Map) continue;
      final name = t['THEME'] as String? ?? '';
      final link = t['LINK'] as String? ?? '';
      if (name.isEmpty || link.isEmpty) continue;
      final owner = (t['OWNER'] as String? ?? '').split('/').last;
      out.add(
        VibeHydeGalleryTheme(
          name,
          link,
          owner,
          t['DESCRIPTION'] as String? ?? '',
          [
            for (final c in (t['COLORSCHEME'] as List? ?? const []))
              if (_hex(c as String? ?? '') case final col?) col,
          ],
        ),
      );
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  static Color? _hex(String s) {
    final v = s.replaceAll('#', '').trim();
    if (v.length < 6) return null;
    final n = int.tryParse(v.substring(0, 6), radix: 16);
    return n == null ? null : Color(0xFF000000 | n);
  }

  /// Import the HyDE theme at [link] (a GitHub repository, or a branch of
  /// one: github.com/owner/repo/tree/branch). [fallback] are the gallery's
  /// colours, used when the theme has no colour file.
  static Future<VibeGlassPalette> importLink(
    String link, {
    List<Color> fallback = const [],
  }) async {
    final m = RegExp(
      r'github\.com/([^/\s]+)/([^/\s#?]+)(?:/tree/([^\s#?]+))?',
    ).firstMatch(link.trim());
    if (m == null) throw Exception('That isn\'t a GitHub link');
    final owner = m[1]!;
    final repo = m[2]!.replaceAll(RegExp(r'\.git$'), '');
    var branch = m[3]?.replaceAll(RegExp(r'/$'), '');
    branch ??= (await _api('/repos/$owner/$repo'))['default_branch'] as String?;
    if (branch == null) throw Exception('That repository has no branch');

    final tree = await _api('/repos/$owner/$repo/git/trees/$branch', {
      'recursive': '1',
    });
    final paths = [
      for (final e in (tree['tree'] as List? ?? const []))
        if (e is Map && e['type'] == 'blob') e['path'] as String,
    ];
    final inThemes = paths.where((p) => p.startsWith(_themes)).toList();
    if (inThemes.isEmpty) throw Exception('No HyDE theme in that repository');
    final dcol = inThemes.firstWhere(
      (p) => p.endsWith('/theme.dcol'),
      orElse: () => '',
    );
    final themeDir = dcol.isNotEmpty
        ? dcol.substring(0, dcol.lastIndexOf('/'))
        : _themes + inThemes.first.substring(_themes.length).split('/').first;
    final name = themeDir.split('/').last;

    // the wallpapers: the folder inside the theme with the most pictures
    final counts = <String, int>{};
    for (final p in paths) {
      if (!p.startsWith('$themeDir/') || !_pic.hasMatch(p)) continue;
      final d = p.substring(0, p.lastIndexOf('/'));
      if (d != themeDir) counts[d] = (counts[d] ?? 0) + 1;
    }
    String? wallDir;
    var most = 0;
    for (final e in counts.entries) {
      if (e.value > most) {
        wallDir = e.key;
        most = e.value;
      }
    }

    final id = 'hyde-${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';
    VibeGlassPalette? p;
    if (dcol.isNotEmpty) {
      final r = await http.get(
        Uri.https('raw.githubusercontent.com', '/$owner/$repo/$branch/$dcol'),
      );
      if (r.statusCode == 200) {
        p = _fromDcol(id, name, '$owner/$repo', branch, wallDir, utf8.decode(r.bodyBytes));
      }
    }
    if (p == null && fallback.isNotEmpty) {
      p = _seeded(id, name, '$owner/$repo', branch, wallDir, fallback.last);
    }
    if (p == null) throw Exception('That theme has no colours to use');

    _list.removeWhere((e) => e['id'] == id);
    _list.add(_toMap(p));
    await _save();
    await VibeGlass.setPalette(id);
    return p;
  }

  /// HyDE's colour file: `dcol_pry1` the background, `dcol_txt1` the text,
  /// `dcol_1xa1`…`dcol_1xa9` the accent from dark to bright.
  static VibeGlassPalette? _fromDcol(
    String id,
    String name,
    String repo,
    String branch,
    String? wallDir,
    String file,
  ) {
    final d = <String, String>{};
    for (final line in const LineSplitter().convert(file)) {
      final m = RegExp(r'^\s*(\w+)\s*=\s*"?([^"\s]*)"?').firstMatch(line);
      if (m != null) d[m[1]!] = m[2]!;
    }
    Color? c(String k) => d[k] == null ? null : _hex(d[k]!);
    final base = c('dcol_pry1');
    final text = c('dcol_txt1');
    var accent = c('dcol_1xa7') ?? c('dcol_1xa6');
    if (base == null || text == null || accent == null) {
      final seed = accent ?? c('dcol_1xa5') ?? base;
      return seed == null ? null : _seeded(id, name, repo, branch, wallDir, seed);
    }
    // Keepr's glass is dark: a light HyDE theme gives its accent only
    if (d['dcol_mode'] == 'light' || base.computeLuminance() > 0.4) {
      return _seeded(id, name, repo, branch, wallDir, accent);
    }
    // an accent too close to the background (monochrome themes): the
    // brightest shade
    if (_contrast(accent, base) < 3) accent = c('dcol_1xa9') ?? text;
    return VibeGlassPalette(
      id: id,
      name: name,
      hydeRepo: repo,
      hydeBranch: wallDir == null ? null : branch,
      hydeDir: wallDir,
      accent: accent,
      onAccent: accent.computeLuminance() > 0.45
          ? const Color(0xFF111111)
          : Colors.white,
      base: base,
      mantle: Color.lerp(base, Colors.black, 0.25)!,
      crust: Color.lerp(base, Colors.black, 0.45)!,
      s0: c('dcol_1xa2') ?? Color.lerp(base, text, 0.12)!,
      s1: c('dcol_1xa3') ?? Color.lerp(base, text, 0.22)!,
      text: text,
      sub: Color.lerp(text, base, 0.3)!,
      tert: c('dcol_3xa7') ?? c('dcol_2xa7') ?? accent,
    );
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
  }

  /// A dark palette around one colour (like "From wallpaper").
  static VibeGlassPalette _seeded(
    String id,
    String name,
    String repo,
    String branch,
    String? wallDir,
    Color seed,
  ) {
    final s = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    return VibeGlassPalette(
      id: id,
      name: name,
      hydeRepo: repo,
      hydeBranch: wallDir == null ? null : branch,
      hydeDir: wallDir,
      accent: s.primary,
      onAccent: s.onPrimary,
      base: s.surface,
      mantle: s.surfaceContainerLow,
      crust: s.surfaceContainerLowest,
      s0: s.surfaceContainerHigh,
      s1: s.surfaceContainerHighest,
      text: s.onSurface,
      sub: s.onSurfaceVariant,
      tert: s.tertiary,
    );
  }

  // ---- the import sheet ---------------------------------------------------

  static Future<void> open(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _ImportSheet(),
  );

  /// Long-press on an imported palette: remove it.
  static Future<void> confirmRemove(BuildContext context, VibeGlassPalette p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${p.name}?'),
        content: const Text('You can import it again any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await remove(p.id);
  }
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet();

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  late Future<List<VibeHydeGalleryTheme>> _gallery = VibeHydeImport.gallery();
  final _link = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _import(String link, {List<Color> fallback = const []}) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final r = await showFutureLoadingDialog(
      context: context,
      future: () => VibeHydeImport.importLink(link, fallback: fallback),
    );
    final p = r.result;
    if (p == null) {
      if (r.error != null) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not import that theme: ${r.error}')),
        );
      }
      return;
    }
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text('${p.name} imported and in use')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              'Import a HyDE theme',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'From HyDE\'s gallery, or paste the GitHub link of any HyDE theme. '
              'Its colours and wallpapers are fetched from its author\'s GitHub.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _link,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'github.com/owner/theme',
                      isDense: true,
                    ),
                    onSubmitted: (v) => v.trim().isEmpty ? null : _import(v),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final v = _link.text.trim();
                    if (v.isNotEmpty) _import(v);
                  },
                  child: const Text('Import'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search the gallery',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<VibeHydeGalleryTheme>>(
              future: _gallery,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _gallery = VibeHydeImport.gallery()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Couldn\'t load the gallery. Retry'),
                    ),
                  );
                }
                final all = snap.data;
                if (all == null) {
                  return const Center(child: CircularProgressIndicator.adaptive());
                }
                final list = _filter.isEmpty
                    ? all
                    : all
                          .where(
                            (t) =>
                                t.name.toLowerCase().contains(_filter) ||
                                t.description.toLowerCase().contains(_filter),
                          )
                          .toList();
                return ListView.builder(
                  controller: scroll,
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final t = list[i];
                    final id =
                        'hyde-${t.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';
                    return ListTile(
                      leading: _Swatch(t.colors),
                      title: Text(t.name),
                      subtitle: Text(
                        [
                          if (t.description.isNotEmpty) t.description,
                          if (t.author.isNotEmpty) 'by ${t.author}',
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: VibeHydeImport.isImported(id)
                          ? Icon(Icons.check_circle, color: cs.primary)
                          : null,
                      onTap: () => _import(t.link, fallback: t.colors),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The gallery's two colours, as a split circle.
class _Swatch extends StatelessWidget {
  final List<Color> colors;
  const _Swatch(this.colors);

  @override
  Widget build(BuildContext context) {
    final a = colors.isNotEmpty ? colors.first : Colors.grey;
    final b = colors.length > 1 ? colors[1] : a;
    return Container(
      width: 40,
      height: 40,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(child: ColoredBox(color: a)),
          Expanded(child: ColoredBox(color: b)),
        ],
      ),
    );
  }
}
