// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/vibe/vibe_event_body.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_lock.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/typing_animation.dart';
import 'package:vibe/widgets/vibe_app.dart';

/// The docked chat: when you jump to another chat (the pill at the top, or
/// pulling the chat's top bar down), the chat you were in slides down into a
/// slim strip under the text box. Swipe it up or tap it to bring it back;
/// the back button does the same. One docked chat at a time.
abstract class VibeChatDock {
  static final ValueNotifier<String?> docked = ValueNotifier(null);

  /// The strip's height above the phone's bottom edge (safe area extra).
  static const double height = 60;

  static bool get enabled => AppSettings.vibeChatDock.value;

  static String? currentRoomId() {
    final seg = VibeApp.router.routeInformationProvider.value.uri.pathSegments;
    if (seg.length >= 2 && seg[0] == 'rooms' && seg[1].startsWith('!')) {
      return seg[1];
    }
    return null;
  }

  /// Shown right now: something is docked and it isn't the open chat.
  static bool get showing {
    final id = docked.value;
    return id != null && enabled && id != currentRoomId();
  }

  /// Open [roomId]; the chat you're in docks under the text box.
  static void openKeeping(String roomId) {
    final cur = currentRoomId();
    if (enabled && cur != null && cur != roomId && !VibeLock.isLocked(cur)) {
      docked.value = cur;
    } else if (docked.value == roomId) {
      docked.value = null;
    }
    VibeApp.router.go('/rooms/$roomId');
  }

  /// Bring the docked chat back. With [swap], the chat you're in docks in
  /// its place, so you can go back and forth.
  static void restore({bool swap = true}) {
    final id = docked.value;
    if (id == null) return;
    final cur = currentRoomId();
    docked.value = swap && enabled && cur != null && cur != id ? cur : null;
    VibeHaptics.light();
    VibeApp.router.go('/rooms/$id');
  }

  /// Dock the open chat and go back to the chat list.
  static void dockCurrent() {
    final cur = currentRoomId();
    if (cur == null || !enabled || VibeLock.isLocked(cur)) return;
    docked.value = cur;
    VibeHaptics.medium();
    VibeApp.router.go('/rooms');
  }

  static void close() => docked.value = null;

  /// Is the keyboard up? (Read from the window: screens inside a Scaffold
  /// don't see the keyboard in their MediaQuery.)
  static bool keyboardOpen(BuildContext context) =>
      View.of(context).viewInsets.bottom > 0;

  /// A chat was opened some other way: if it was the docked one, it's no
  /// longer docked.
  static void opened(String roomId) {
    if (docked.value == roomId) docked.value = null;
  }
}

/// Room under the text box for the docked strip (nothing while typing).
/// The chat screen's own MediaQuery has the keyboard taken out, so this
/// listens to the window itself.
class VibeDockSpace extends StatefulWidget {
  const VibeDockSpace({super.key});

  @override
  State<VibeDockSpace> createState() => _VibeDockSpaceState();
}

class _VibeDockSpaceState extends State<VibeDockSpace>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: VibeChatDock.docked,
    builder: (context, _, _) {
      final show = VibeChatDock.showing && !VibeChatDock.keyboardOpen(context);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: show ? VibeChatDock.height : 0,
      );
    },
  );
}

/// Pull the chat's name bar down to dock the chat. The name follows the
/// finger a little; past the line it docks (with a tick of vibration).
class VibeDockPull extends StatefulWidget {
  final Widget child;
  const VibeDockPull({required this.child, super.key});

  @override
  State<VibeDockPull> createState() => _VibeDockPullState();
}

class _VibeDockPullState extends State<VibeDockPull> {
  static const _line = 70.0;
  double _dy = 0;
  bool _past = false;

  @override
  Widget build(BuildContext context) {
    if (!VibeChatDock.enabled) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (d) {
        final dy = (_dy + d.delta.dy).clamp(0.0, 140.0);
        final past = dy > _line;
        if (past && !_past) VibeHaptics.selection();
        setState(() {
          _dy = dy;
          _past = past;
        });
      },
      onVerticalDragEnd: (d) {
        final go = _past || (d.primaryVelocity ?? 0) > 900;
        setState(() {
          _dy = 0;
          _past = false;
        });
        if (go) VibeChatDock.dockCurrent();
      },
      onVerticalDragCancel: () => setState(() {
        _dy = 0;
        _past = false;
      }),
      child: AnimatedSlide(
        offset: Offset(0, _dy / 160),
        duration: Duration(milliseconds: _dy == 0 ? 220 : 0),
        curve: Curves.easeOutBack,
        child: Opacity(
          opacity: 1 - (_dy / 140) * 0.5,
          child: widget.child,
        ),
      ),
    );
  }
}

/// The strip itself, at the bottom of the app (put in the app-wide stack).
class VibeDockStrip extends StatelessWidget {
  final Client client;
  const VibeDockStrip({required this.client, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      VibeChatDock.docked,
      VibeApp.router.routeInformationProvider,
    ]),
    builder: (context, _) {
      final id = VibeChatDock.docked.value;
      final room = id == null ? null : client.getRoomById(id);
      final show = room != null &&
          VibeChatDock.showing &&
          MediaQuery.viewInsetsOf(context).bottom == 0;
      return IgnorePointer(
        ignoring: !show,
        child: AnimatedSlide(
          offset: show ? Offset.zero : const Offset(0, 1.2),
          duration: const Duration(milliseconds: 340),
          curve: show ? Curves.easeOutCubic : Curves.easeInCubic,
          child: room == null ? const SizedBox.shrink() : _Strip(room),
        ),
      );
    },
  );
}

class _Strip extends StatelessWidget {
  final Room room;
  const _Strip(this.room);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final name = room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    return GestureDetector(
      onTap: VibeChatDock.restore,
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -150) VibeChatDock.restore();
        if (v > 150) VibeChatDock.close();
      },
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0).abs() > 300) VibeChatDock.close();
      },
      child: Material(
        color: cs.surfaceContainerHigh,
        elevation: 8,
        shadowColor: Colors.black54,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 6, 10, 6 + bottom),
          child: SizedBox(
            height: VibeChatDock.height - 12,
            child: Column(
              children: [
                // handle: swipe up to open, down to close
                Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: StreamBuilder<Object?>(
                    stream: room.client.onSync.stream.where(
                      (u) => u.rooms?.join?.containsKey(room.id) ?? false,
                    ),
                    builder: (context, _) {
                      final typing = room.typingUsers
                          .where((u) => u.id != room.client.userID)
                          .isNotEmpty;
                      final last = room.lastEvent;
                      final unread = room.notificationCount;
                      // typing: picture + typing. Unread: picture + the
                      // newest message (+N when there are more). Neither:
                      // picture + name.
                      final Widget middle;
                      if (typing) {
                        middle = Row(
                          key: const ValueKey('typing'),
                          children: [
                            const TypingAnimation(size: 6),
                            const SizedBox(width: 8),
                            Text(
                              'typing…',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: cs.primary,
                              ),
                            ),
                          ],
                        );
                      } else if (unread > 0 && last != null) {
                        middle = Row(
                          key: ValueKey('unread$unread'),
                          children: [
                            Expanded(
                              child: Text(
                                last.vibeBodyFallback(
                                  MatrixLocals(L10n.of(context)),
                                  plaintextBody: true,
                                  hideReply: true,
                                  hideEdit: true,
                                  removeMarkdown: true,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                unread > 1 ? '+$unread' : '1',
                                style: TextStyle(
                                  color: cs.onPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        );
                      } else {
                        middle = Text(
                          name,
                          key: const ValueKey('name'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        );
                      }
                      return Row(
                        children: [
                          Avatar(
                            mxContent: room.avatar,
                            name: name,
                            size: 32,
                            client: room.client,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              transitionBuilder: (child, a) => FadeTransition(
                                opacity: a,
                                child: SlideTransition(
                                  position: Tween(
                                    begin: const Offset(0, 0.4),
                                    end: Offset.zero,
                                  ).animate(a),
                                  child: child,
                                ),
                              ),
                              layoutBuilder: (cur, prev) => Stack(
                                alignment: Alignment.centerLeft,
                                children: [...prev, ?cur],
                              ),
                              child: middle,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: VibeChatDock.close,
                          ),
                          Icon(Icons.keyboard_arrow_up, color: cs.primary),
                        ],
                      );
                    },
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
