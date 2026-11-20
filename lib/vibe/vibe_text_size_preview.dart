// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_message.dart';
import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/vibe/vibe_profile_cache.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:matrix/matrix.dart';

/// Settings > Customisation: the Text size preview, drawn like the chat:
/// one card per message run with the picture nested in its curve and the
/// time inside, their card in their own colour, yours in the theme's, and
/// a reply showing the answered message as a smaller card above.
class VibeTextSizePreview extends StatelessWidget {
  /// The size being previewed (passing it makes the preview redraw while
  /// the slider moves).
  final int size;
  const VibeTextSizePreview({required this.size, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final client = Matrix.of(context).client;
    final textSize = (size + 1).toDouble(); // as VibeTextSize.message
    final now = DateTime.now();
    final t1 = DateFormat('h:mm a').format(now.subtract(const Duration(minutes: 2)));
    final t2 = DateFormat('h:mm a').format(now);
    // the same colours as the chat's cards
    final wall = VibePalette.isVibe
        ? (dark ? VibePalette.wallDark : VibePalette.wallLight) ?? cs
        : cs;
    final under = dark ? const Color(0xFF1B1B1F) : const Color(0xFFF1F1F4);
    final mine = Color.alphaBlend(wall.primaryContainer, under);
    final mineInk = wall.onPrimaryContainer;
    final theirs = VibeCardColours.theirs(context, 'Maya');
    final theirInk = VibeCardColours.theirInk(context);

    return MediaQuery(
      // Same as the chat: only message text follows the size.
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: VibeOwnProfileBuilder(
          client: client,
          builder: (context, me) {
            final myName = me?.displayName ?? client.userID?.localpart ?? 'You';
            final myPic = Avatar(
              mxContent: me?.avatarUrl,
              name: myName,
              size: _pic,
              client: client,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Card(
                  mine: false,
                  color: theirs,
                  ink: theirInk,
                  picture: const Avatar(name: 'Maya', size: _pic),
                  text: "Yes! I'll bring the board games",
                  time: t1,
                  textSize: textSize,
                  echo: _Echo(
                    fill: mine,
                    nameColor: dark
                        ? const Color(0xFFB5BAC1)
                        : const Color(0xFF4E5058),
                    lead: Avatar(
                      mxContent: me?.avatarUrl,
                      name: myName,
                      size: 16,
                      client: client,
                    ),
                    name: myName,
                    words: 'Hey! Still on for tonight? 🍕',
                    textSize: textSize,
                    dark: dark,
                  ),
                ),
                const SizedBox(height: 10),
                _Card(
                  mine: true,
                  color: mine,
                  ink: mineInk,
                  picture: myPic,
                  text: 'Perfect, see you at 8 🎲',
                  time: t2,
                  status: 'Delivered',
                  textSize: textSize,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// the chat's sizes: a small round picture, nested in the card's curve
const double _pic = 30;
const double _gap = 3;
const double _reach = _pic / 2 + _gap;

class _Card extends StatelessWidget {
  final bool mine;
  final Color color, ink;
  final Widget picture;
  final String text, time;
  final String? status;
  final double textSize;
  final Widget? echo;
  const _Card({
    required this.mine,
    required this.color,
    required this.ink,
    required this.picture,
    required this.text,
    required this.time,
    required this.textSize,
    this.status,
    this.echo,
  });

  @override
  Widget build(BuildContext context) {
    final meta = ink.withValues(alpha: 0.62);
    final card = CustomPaint(
      painter: VibeBubblePainter(
        color: color,
        left: !mine,
        top: 20,
        bottom: 20,
        reach: _reach,
        cut: true,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: VibeTimeFlow(
          content: Text(
            text,
            style: TextStyle(fontSize: textSize, height: 1.3, color: ink),
          ),
          trailing: Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 5,
              children: [
                Text(
                  time,
                  style: TextStyle(fontSize: 11, height: 1.2, color: meta),
                ),
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: Text(
                      status!,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: meta,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: mine ? TextDirection.rtl : TextDirection.ltr,
      children: [
        picture,
        const SizedBox(width: _gap),
        Flexible(child: card),
      ],
    );
    final echo = this.echo;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: echo == null
          ? row
          // the answered message peeks out above the card
          : Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 0,
                  left: mine ? 14 : _pic / 2 + 14,
                  right: mine ? _pic / 2 + 14 : 14,
                  child: echo,
                ),
                Padding(padding: const EdgeInsets.only(top: 26), child: row),
              ],
            ),
    );
  }
}

/// The answered message as a smaller card, in that person's colour.
class _Echo extends StatelessWidget {
  final Color fill, nameColor;
  final Widget lead;
  final String name, words;
  final double textSize;
  final bool dark;
  const _Echo({
    required this.fill,
    required this.nameColor,
    required this.lead,
    required this.name,
    required this.words,
    required this.textSize,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final small = textSize * 0.82;
    const shows = 26.0, tall = 44.0;
    return Container(
      height: tall,
      padding: const EdgeInsets.fromLTRB(7, 5, 12, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: nameColor.withValues(alpha: 0.14)),
        // the card's soft shade, just above its edge
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            fill,
            fill,
            Color.alphaBlend(
              Colors.black.withValues(alpha: dark ? 0.28 : 0.07),
              fill,
            ),
          ],
          stops: const [0, (shows - 9) / tall, shows / tall],
        ),
      ),
      alignment: Alignment.topLeft,
      child: SizedBox(
        height: 18,
        child: Row(
          children: [
            lead,
            const SizedBox(width: 6),
            Flexible(
              flex: 0,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: small,
                  fontWeight: FontWeight.w700,
                  color: nameColor,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                words,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: small,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
