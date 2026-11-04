// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:vibe/config/setting_keys.dart';

/// When Keepr opens (after being closed or removed from recents) or comes
/// back after a while away, the home screen's rows slide in one after
/// another, quickly. Settings > Customisation > "Start-up animation".
abstract class VibeHomeIntro {
  /// When the last run started, and when its first row showed up (the
  /// home can take a moment to load after a cold start).
  static DateTime? _startedAt, _firstRowAt;
  static final ValueNotifier<int> run = ValueNotifier(0);

  /// Rows that appear within this time of the first one slide in too.
  static const window = Duration(milliseconds: 700);

  static bool get active {
    final s = _startedAt;
    final now = DateTime.now();
    if (s == null || now.difference(s) > const Duration(seconds: 5)) {
      return false;
    }
    final first = _firstRowAt ??= now;
    return now.difference(first) < window;
  }

  static void start() {
    if (!AppSettings.vibeBootIntro.value) return;
    _startedAt = DateTime.now();
    _firstRowAt = null;
    run.value++;
  }
}

/// Watches Keepr opening and coming back, and starts the rows' slide-in.
/// Draws nothing itself.
class VibeBootIntro extends StatefulWidget {
  const VibeBootIntro({super.key});

  /// Away at least this long counts as "after sleep".
  static const away = Duration(minutes: 3);

  @override
  State<VibeBootIntro> createState() => _VibeBootIntroState();
}

class _VibeBootIntroState extends State<VibeBootIntro>
    with WidgetsBindingObserver {
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // a cold start: the rows built now slide in
    VibeHomeIntro.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _leftAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left != null && DateTime.now().difference(left) >= VibeBootIntro.away) {
        VibeHomeIntro.start();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// One row of the home screen: slides in from the side and fades up,
/// [index] steps after the first, when the intro runs.
class VibeStagger extends StatefulWidget {
  final int index;
  final Widget child;

  /// Slide from below instead of from the right (the rail).
  final bool vertical;
  const VibeStagger({
    required this.index,
    required this.child,
    this.vertical = false,
    super.key,
  });

  /// Only the first rows animate (the rest are off screen anyway).
  static const maxIndex = 14;

  @override
  State<VibeStagger> createState() => _VibeStaggerState();
}

class _VibeStaggerState extends State<VibeStagger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    VibeHomeIntro.run.addListener(_go);
    _go();
  }

  void _go() {
    if (!mounted || widget.index > VibeStagger.maxIndex) return;
    if (!VibeHomeIntro.active) return;
    // people who turned animations off in Android don't get it (read from
    // the platform: this also runs from initState, before any context)
    if (WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
      return;
    }
    _c.value = 0;
    Future.delayed(Duration(milliseconds: 40 * widget.index), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    VibeHomeIntro.run.removeListener(_go);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(
          begin: widget.vertical ? const Offset(0, 0.4) : const Offset(0.18, 0),
          end: Offset.zero,
        ).animate(a),
        child: widget.child,
      ),
    );
  }
}
