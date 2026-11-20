// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/utils/platform_infos.dart';

/// Tools for checking smoothness (About: tap the version five times).
abstract class VibeSmooth {
  /// The frame timing graph shows at the top of every screen.
  static final graph = ValueNotifier<bool>(false);

  static void start() {
    graph.value = AppSettings.vibeFrameGraph.value;
    _touch(AppSettings.vibeSmoothTouch.value);
  }

  static Future<void> setGraph(bool on) async {
    graph.value = on;
    await AppSettings.vibeFrameGraph.setItem(on);
  }

  static Future<void> setTouch(bool on) async {
    _touch(on);
    await AppSettings.vibeSmoothTouch.setItem(on);
  }

  // Smooth touch: the finger's path is evened out to the screen's frames,
  // a few milliseconds behind, so drags and scrolls move the same amount
  // every frame.
  static void _touch(bool on) {
    if (!PlatformInfos.isAndroid) return;
    GestureBinding.instance
      ..samplingOffset = const Duration(milliseconds: -20)
      ..resamplingEnabled = on;
  }
}

/// Puts the frame timing graph over the app when it's on. The app itself
/// always stays the first child, so nothing restarts when it's switched.
class VibeFrameGraph extends StatelessWidget {
  final Widget child;
  const VibeFrameGraph({required this.child, super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: VibeSmooth.graph,
    child: child,
    builder: (context, on, child) => Stack(
      fit: StackFit.expand,
      children: [
        child!,
        if (on)
          Positioned(
            top: MediaQuery.paddingOf(context).top,
            left: 0,
            right: 0,
            child: IgnorePointer(child: PerformanceOverlay.allEnabled()),
          ),
      ],
    ),
  );
}
