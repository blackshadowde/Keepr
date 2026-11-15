// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/config/app_config.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/vibe/screens/call/call_page.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';

class CallOverlay extends StatelessWidget {
  final Widget child;
  const CallOverlay({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Matrix.of(context).activeCallRoomId,
      builder: (context, value, _) {
        final roomId = value;
        if (roomId == null) return child;
        return ValueListenableBuilder(
          valueListenable: Matrix.of(context).callPosition,
          builder: (context, value, _) {
            final callPosition = value;
            final callFullScreen = callPosition == .fullScreen;
            return Stack(
              children: [
                child,
                AnimatedPositioned(
                  duration: VibeThemes.animationDuration,
                  curve: VibeThemes.animationCurve,
                  top: callFullScreen
                      ? 0
                      : callPosition == .top
                      ? 86
                      : null,
                  left: callFullScreen ? 0 : null,
                  right: callFullScreen ? 0 : 8,
                  bottom: callFullScreen ? 0 : null,
                  height: callFullScreen ? null : 256,
                  width: callFullScreen ? null : 256,
                  child: Material(
                    elevation: callFullScreen ? 0 : 4,
                    clipBehavior: .hardEdge,
                    shape: callFullScreen
                        ? null
                        : RoundedRectangleBorder(
                            side: BorderSide(color: Colors.grey),
                            borderRadius: BorderRadius.circular(
                              AppConfig.borderRadius,
                            ),
                          ),
                    child: Navigator(
                      onDidRemovePage: (_) {
                        Matrix.of(context).activeCallRoomId.value = null;
                      },
                      pages: [
                        MaterialPage(
                          child: CallPage(
                            roomId: roomId,
                            video: Matrix.of(context).activeCallVideo,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
