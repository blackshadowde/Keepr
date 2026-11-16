// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_dialog.dart';
import 'dart:typed_data';

import 'package:vibe/vibe/vibe_contact_share.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:cross_file/cross_file.dart';
import 'package:vibe/vibe/screens/chat/chat.dart';
import 'package:vibe/vibe/screens/chat/send_file_dialog.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:vibe/vibe/vibe_updater.dart';

/// "+" attachment sheet: gallery grid + Photos / Contacts / Files / Location.
abstract class VibeAttachSheet {
  static Future<void> show(BuildContext context, ChatController controller) {
    controller.inputFocus.unfocus();
    return showVibeSheet<void>(
      sheetAnimationStyle: vibeSheetStyle,
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.62,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _AttachSheet(controller: controller),
    );
  }
}

class _AttachSheet extends StatefulWidget {
  final ChatController controller;
  const _AttachSheet({required this.controller});

  @override
  State<_AttachSheet> createState() => _AttachSheetState();
}

class _AttachSheetState extends State<_AttachSheet> {
  final List<AssetEntity> _assets = [];
  final Set<String> _selected = {};
  final ScrollController _scroll = ScrollController();
  AssetPathEntity? _path;
  int _page = 0;
  bool _loading = false;
  bool _end = false;
  bool _denied = false;

  // each picture's thumbnail, made once: a tile that rebuilds (picking,
  // more loading) shows the same one instead of flashing grey
  final Map<String, Future<Uint8List?>> _thumbs = {};
  final Map<String, Uint8List?> _ready = {};

  Future<Uint8List?> _thumb(AssetEntity a) => _thumbs.putIfAbsent(a.id, () async {
    final data = await a.thumbnailDataWithSize(
      const ThumbnailSize(260, 260),
      quality: 85,
    );
    _ready[a.id] = data;
    return data;
  });

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
    _init();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    // Google Play build: no photo-library permission, so no inline gallery;
    // the system photo picker is used instead.
    if (VibeUpdater.fromPlay) return;
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.hasAccess) {
        if (mounted) setState(() => _denied = true);
        return;
      }
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
        // Newest photos and videos first.
        filterOption: FilterOptionGroup(
          orders: [
            const OrderOption(type: OrderOptionType.createDate, asc: false),
          ],
        ),
      );
      if (paths.isEmpty) {
        if (mounted) setState(() => _end = true);
        return;
      }
      _path = paths.first;
      await _loadMore();
    } catch (_) {
      if (mounted) setState(() => _end = true);
    }
  }

  Future<void> _loadMore() async {
    final path = _path;
    if (path == null || _loading || _end) return;
    _loading = true;
    try {
      final list = await path.getAssetListPaged(page: _page, size: 80);
      if (!mounted) return;
      setState(() {
        _assets.addAll(list);
        _page++;
        if (list.length < 80) _end = true;
      });
    } finally {
      _loading = false;
    }
  }

  Future<void> _sendSelected() async {
    // in the order they were picked
    final byId = {for (final a in _assets) a.id: a};
    final files = <XFile>[];
    for (final id in _selected) {
      final f = await byId[id]?.originFile;
      if (f != null) files.add(XFile(f.path));
    }
    await _openSend(files);
  }

  /// Android's own photo picker (needs no permission): every album, and
  /// Google Photos when it's set up there.
  Future<void> _pickSystem() async {
    final files = await ImagePicker().pickMultipleMedia();
    await _openSend(files);
  }

  Future<void> _openSend(List<XFile> files) async {
    final c = widget.controller;
    if (files.isEmpty) return;
    if (!mounted) return;
    Navigator.of(context).pop();
    if (!c.context.mounted) return;
    await showVibeDialog(
      context: c.context,
      builder: (_) => SendFileDialog(
        files: files,
        room: c.room,
        outerContext: c.context,
        threadRootEventId: c.activeThreadId,
        threadLastEventId: c.threadLastEventId,
      ),
    );
  }

  void _contacts() {
    final c = widget.controller;
    Navigator.of(context).pop();
    showVibeSheet<void>(
      sheetAnimationStyle: vibeSheetStyle,
      context: c.context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: VibeContactShareSheet(room: c.room),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = widget.controller;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        if (_denied)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Allow access to photos to attach media'),
                TextButton(
                  onPressed: PhotoManager.openSetting,
                  child: const Text('Open settings'),
                ),
                // Android's photo picker needs no access
                FilledButton.tonalIcon(
                  onPressed: _pickSystem,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose from all photos'),
                ),
              ],
            ),
          )
        else
          GridView.builder(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(8, 4, 8, 110 + bottom),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: VibeUpdater.fromPlay ? 2 : _assets.length + 2,
            itemBuilder: (context, i) {
              // every album and Google Photos, in Android's photo picker
              if (i == 1) {
                return Material(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _pickSystem,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.photo_library_outlined,
                            size: 28,
                            color: cs.onSurface,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'All photos',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Google Photos too',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              if (i == 0) {
                return InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    c.onAddPopupMenuButtonSelected(
                      AddPopupMenuActions.photoCamera,
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.photo_camera,
                      size: 40,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                );
              }
              final asset = _assets[i - 2];
              final order = _selected.toList().indexOf(asset.id);
              return _Tile(
                key: ValueKey(asset.id),
                asset: asset,
                thumb: _thumb(asset),
                ready: _ready[asset.id],
                order: order < 0 ? null : order + 1,
                onTap: () {
                  VibeHaptics.light();
                  setState(() {
                    if (!_selected.add(asset.id)) _selected.remove(asset.id);
                  });
                },
              );
            },
          ),
        Positioned(
          left: 14,
          right: 14,
          bottom: 12 + bottom,
          child: _selected.isNotEmpty
              ? SizedBox(
                  height: 60,
                  child: FilledButton.icon(
                    onPressed: _sendSelected,
                    icon: const Icon(Icons.send_rounded),
                    label: Text('Send ${_selected.length}'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      textStyle: const TextStyle(fontFamily: 'Figtree', 
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              : Material(
                  color: cs.surfaceContainerHigh,
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _Action(
                          icon: Icons.photo_outlined,
                          label: 'Photos',
                          active: true,
                          onTap: VibeUpdater.fromPlay
                              ? _pickSystem
                              : () => _scroll.animateTo(
                            0,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          ),
                        ),
                        _Action(
                          icon: Icons.person_outline_rounded,
                          label: 'Contacts',
                          onTap: _contacts,
                        ),
                        _Action(
                          icon: Icons.attach_file_rounded,
                          label: 'Files',
                          onTap: () {
                            Navigator.of(context).pop();
                            c.onAddPopupMenuButtonSelected(
                              AddPopupMenuActions.file,
                            );
                          },
                        ),
                        _Action(
                          icon: Icons.poll_outlined,
                          label: 'Poll',
                          onTap: () {
                            Navigator.of(context).pop();
                            c.onAddPopupMenuButtonSelected(
                              AddPopupMenuActions.poll,
                            );
                          },
                        ),
                        _Action(
                          icon: Icons.location_on_outlined,
                          label: 'Location',
                          onTap: () {
                            Navigator.of(context).pop();
                            c.onAddPopupMenuButtonSelected(
                              AddPopupMenuActions.location,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

}

/// One picture in the grid: its thumbnail fades in once and stays put;
/// picked, it shrinks a little and shows its number in the order picked.
class _Tile extends StatelessWidget {
  final AssetEntity asset;
  final Future<Uint8List?> thumb;
  final Uint8List? ready;
  final int? order;
  final VoidCallback onTap;
  const _Tile({
    required this.asset,
    required this.thumb,
    required this.ready,
    required this.order,
    required this.onTap,
    super.key,
  });

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final picked = order != null;
    const quick = Duration(milliseconds: 170);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: picked ? 0.88 : 1,
        duration: quick,
        curve: Curves.easeOutBack,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(picked ? 18 : 14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: cs.surfaceContainerHighest),
              FutureBuilder<Uint8List?>(
                future: thumb,
                initialData: ready,
                builder: (context, snap) {
                  final data = snap.data;
                  if (data == null) return const SizedBox.shrink();
                  return Image.memory(
                    data,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    // fades in the first time only
                    frameBuilder: (context, child, frame, sync) => sync
                        ? child
                        : AnimatedOpacity(
                            opacity: frame == null ? 0 : 1,
                            duration: const Duration(milliseconds: 180),
                            child: child,
                          ),
                  );
                },
              ),
              AnimatedOpacity(
                opacity: picked ? 1 : 0,
                duration: quick,
                child: ColoredBox(color: cs.primary.withValues(alpha: 0.18)),
              ),
              if (asset.type == AssetType.video)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videocam, size: 13, color: Colors.white),
                        const SizedBox(width: 3),
                        Text(
                          _fmt(asset.videoDuration),
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                top: 6,
                right: 6,
                child: AnimatedContainer(
                  duration: quick,
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: picked ? cs.primary : Colors.black26,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: picked
                      ? Text(
                          '$order',
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // a soft tonal pill with a plain icon, in the theme's colours
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: active ? cs.secondaryContainer : cs.surfaceContainerHighest,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: SizedBox(
                  width: 62,
                  height: 44,
                  child: Icon(
                    icon,
                    size: 24,
                    color: active
                        ? cs.onSecondaryContainer
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
