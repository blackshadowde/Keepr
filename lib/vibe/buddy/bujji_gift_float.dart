// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:vibe/vibe/buddy/bujji_gifts.dart';
import 'package:vibe/vibe/screens/chat/chat.dart';
import 'package:vibe/vibe/vibe_haptics.dart';

/// With Bujji off, a reaction you'd miss floats just above the send button
/// (above the jump-to-present button when that shows). Tap it to go to the
/// message.
class BujjiGiftFloat extends StatelessWidget {
  final ChatController controller;
  const BujjiGiftFloat(this.controller, {super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double?>(
    valueListenable: controller.inputBarHeightNotifier,
    builder: (context, barHeight, _) =>
        ValueListenableBuilder<List<BujjiGift>>(
          valueListenable: BujjiGifts.list,
          builder: (context, gifts, _) {
            final calm = controller.selectedEvents.isEmpty;
            final show = gifts.isNotEmpty && !BujjiGifts.byBujji && calm;
            final jump = controller.showScrollDownButton && calm;
            return AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              // centred over the jump button (44 wide, 17 from the edge)
              right: 19,
              bottom: (barHeight ?? 72) + 10 + (jump ? 54 : 0),
              child: IgnorePointer(
                ignoring: !show,
                child: AnimatedScale(
                  scale: show ? 1 : 0.5,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  child: AnimatedOpacity(
                    opacity: show ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: gifts.isEmpty
                        ? const SizedBox.square(dimension: 40)
                        : _Bubble(
                            gift: gifts.first,
                            count: gifts.length,
                            onTap: () {
                              final g = gifts.first;
                              VibeHaptics.light();
                              BujjiGifts.drop(target: g.target);
                              controller.scrollToEventId(g.target);
                            },
                          ),
                  ),
                ),
              ),
            );
          },
        ),
  );
}

/// The emoji in a small round bubble, bobbing gently, with how many are
/// waiting.
class _Bubble extends StatefulWidget {
  final BujjiGift gift;
  final int count;
  final VoidCallback onTap;
  const _Bubble({required this.gift, required this.count, required this.onTap});

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final bubble = Semantics(
      label: 'Reaction ${widget.gift.key}. Go to the message',
      button: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: cs.secondaryContainer,
            shape: const CircleBorder(),
            elevation: 3,
            shadowColor: Colors.black38,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              child: SizedBox.square(
                dimension: 40,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, a) =>
                        ScaleTransition(scale: a, child: child),
                    child: Text(
                      widget.gift.key,
                      key: ValueKey(widget.gift.reaction),
                      style: const TextStyle(fontSize: 21, height: 1),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.count > 1)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '${widget.count}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.onPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (still) return bubble;
    // floats up and down, slowly
    return AnimatedBuilder(
      animation: _bob,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -3 * math.sin(_bob.value * math.pi * 2)),
        child: child,
      ),
      child: bubble,
    );
  }
}
