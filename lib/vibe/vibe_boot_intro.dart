// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/vibe_launch.dart';

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

  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _leftAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left != null &&
          DateTime.now().difference(left) >= VibeBootIntro.away &&
          AppSettings.vibeBootIntro.value) {
        // the dots hop again, then the rows slide in
        VibeLaunch.replayRequest.value++;
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
