// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:vibe/vibe/vibe_sticker.dart';
import 'package:vibe/config/app_config.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/utils/file_description.dart';
import 'package:vibe/utils/url_launcher.dart';
import 'package:vibe/vibe/vibe_low_data.dart';
import 'package:vibe/widgets/mxc_image.dart';
import 'package:vibe/vibe/vibe_stable_id.dart';
import 'package:vibe/vibe/vibe_text_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:matrix/matrix.dart';

import 'package:vibe/widgets/blur_hash.dart';

class ImageBubble extends StatelessWidget {
  final Event event;
  final bool tapToView;
  final BoxFit fit;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? linkColor;
  final bool thumbnailOnly;
  final bool animated;
  final double width;
  final double height;
  final void Function()? onTap;
  final BorderRadius? borderRadius;
  final Timeline? timeline;

  const ImageBubble(
    this.event, {
    this.tapToView = true,
    this.backgroundColor,
    this.fit = BoxFit.contain,
    this.thumbnailOnly = true,
    this.width = 400,
    this.height = 300,
    this.animated = false,
    this.onTap,
    this.borderRadius,
    this.timeline,
    this.textColor,
    this.linkColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    var borderRadius =
        this.borderRadius ?? BorderRadius.circular(AppConfig.borderRadius);

    final fileDescription = event.fileDescription;
    final textColor = this.textColor;

    if (fileDescription != null) {
      borderRadius = borderRadius.copyWith(
        bottomLeft: Radius.zero,
        bottomRight: Radius.zero,
      );
    }

    return Column(
      mainAxisSize: .min,
      spacing: 8,
      children: [
        Material(
          color: Colors.transparent,
          clipBehavior: Clip.hardEdge,
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: BorderSide(
              color: event.isVibeSticker
                  ? Colors.transparent
                  : theme.dividerColor,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: borderRadius,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Hero(
                  tag: event.eventId,
                  child: VibeTapToLoad(
                    event: event,
                    placeholder: _ImageBubblePlaceholder(
                      event: event,
                      width: width,
                      height: height,
                      fit: fit,
                    ),
                    child: AppSettings.showThumbnailsInTimeline.value
                      ? MxcImage(
                          cacheKey: VibeStableId.of(event),
                          cacheName: event.room.id,
                          event: event,
                          width: width,
                          height: height,
                          fit: fit,
                          animated: animated && !VibeLowData.on,
                          isThumbnail: thumbnailOnly,
                          placeholder: (_) => _ImageBubblePlaceholder(
                            event: event,
                            width: width,
                            height: height,
                            fit: fit,
                          ),
                        )
                      : _ImageBubblePlaceholder(
                          event: event,
                          width: width,
                          height: height,
                          fit: fit,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (fileDescription != null && textColor != null)
          SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Linkify(
                text: fileDescription,
                textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
                style: TextStyle(
                  color: textColor,
                  fontSize: VibeTextSize.message,
                ),
                options: const LinkifyOptions(humanize: false),
                linkStyle: TextStyle(
                  color: linkColor,
                  fontSize: VibeTextSize.message,
                  decoration: TextDecoration.underline,
                  decorationColor: linkColor,
                ),
                onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
              ),
            ),
          ),
      ],
    );
  }
}

class _ImageBubblePlaceholder extends StatelessWidget {
  final Event event;
  final double width, height;
  final BoxFit fit;

  const _ImageBubblePlaceholder({
    required this.event,
    required this.width,
    required this.height,
    required this.fit,
  });

  @override
  Widget build(BuildContext context) {
    final blurHashString = event.infoMap.tryGet<String>(
      'xyz.amorgan.blurhash',
    );
    // a photo with its own preview shows its colours while it loads
    if (blurHashString != null && !event.isVibeSticker) {
      return SizedBox(
        width: width,
        height: height,
        child: BlurHash(
          blurhash: blurHashString,
          width: width,
          height: height,
          fit: fit,
        ),
      );
    }
    // stickers, and pictures without one: a soft shape in the app's colours
    return _LoadingShimmer(
      width: width,
      height: height,
      sticker: event.isVibeSticker,
    );
  }
}

/// A tonal rounded shape with a light sweeping across it and a small icon:
/// what a sticker or picture looks like until it arrives.
class _LoadingShimmer extends StatefulWidget {
  final double width, height;
  final bool sticker;
  const _LoadingShimmer({
    required this.width,
    required this.height,
    required this.sticker,
  });

  @override
  State<_LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<_LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.surfaceContainerHigh;
    final light = Color.lerp(cs.surfaceContainerHighest, cs.primary, 0.1)!;
    final side = math.min(widget.width, widget.height);
    final still = MediaQuery.of(context).disableAnimations;
    if (still) _sweep.stop();
    final icon = Icon(
      widget.sticker ? Icons.emoji_emotions_outlined : Icons.image_outlined,
      size: (side * 0.26).clamp(18.0, 34.0),
      color: cs.onSurfaceVariant.withValues(alpha: 0.45),
    );
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        // stickers have no frame, so the shape carries its own corners
        borderRadius: BorderRadius.circular(widget.sticker ? side * 0.22 : 0),
        child: AnimatedBuilder(
          animation: _sweep,
          child: Center(child: icon),
          builder: (context, icon) {
            final t = still ? 0.5 : _sweep.value;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-2.2 + 3.4 * t, -0.4),
                  end: Alignment(-1.0 + 3.4 * t, 0.4),
                  colors: [base, light, base],
                  stops: const [0.1, 0.5, 0.9],
                ),
              ),
              child: icon,
            );
          },
        ),
      ),
    );
  }
}
