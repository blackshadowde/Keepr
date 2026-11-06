// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Back and "more" along the top of a middle pane (person or community).
class VibeTreeTop extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onMore;
  const VibeTreeTop({required this.onBack, this.onMore, super.key});

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: Icon(Icons.chevron_left_rounded, size: 30, color: fg),
            onPressed: onBack,
          ),
          const Spacer(),
          if (onMore != null)
            IconButton(
              tooltip: 'More',
              icon: Icon(Icons.more_horiz_rounded, color: fg),
              onPressed: onMore,
            ),
        ],
      ),
    );
  }
}

/// A folding section: a small arrow and title, then its rows hanging off
/// one faint guide line. No boxes or borders around anything.
class VibeTreeSection extends StatefulWidget {
  final String title;

  /// Small text at the end of the title ("3 in voice").
  final String? note;

  /// "+" at the end of the title (add a channel).
  final VoidCallback? onAdd;
  final List<Widget> children;
  const VibeTreeSection({
    required this.title,
    required this.children,
    this.note,
    this.onAdd,
    super.key,
  });

  @override
  State<VibeTreeSection> createState() => _VibeTreeSectionState();
}

class _VibeTreeSectionState extends State<VibeTreeSection> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    final small = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: sub);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _open ? 0 : -0.25,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more_rounded, size: 16, color: sub),
                ),
                const SizedBox(width: 6),
                Text(widget.title, style: small),
                const Spacer(),
                if (widget.note != null)
                  Text(widget.note!, style: small.copyWith(fontSize: 12)),
                if (widget.onAdd != null)
                  GestureDetector(
                    onTap: widget.onAdd,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.add_rounded, size: 18, color: sub),
                    ),
                  ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Container(
                  margin: const EdgeInsets.only(left: 26),
                  padding: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: sub.withAlpha(0x38)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.children,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// One row in a [VibeTreeSection]: icon, name, small text at the end and
/// an unread count. [selected] gives it a soft tint; [nested] indents it
/// under the row above (a thread under its channel).
class VibeTreeRow extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String label;
  final String? meta;
  final int unread;
  final bool bold;
  final bool selected;
  final bool nested;
  final Color? color;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const VibeTreeRow({
    required this.label,
    this.icon,
    this.leading,
    this.meta,
    this.unread = 0,
    this.bold = false,
    this.selected = false,
    this.nested = false,
    this.color,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = bold || unread > 0;
    final sub = cs.onSurfaceVariant;
    final fg = color ?? (on ? cs.onSurface : sub);
    final ic = iconColor ?? (on ? sub : sub.withAlpha(0x99));
    return Padding(
      padding: EdgeInsets.fromLTRB(nested ? 22 : 0, 1, 12, 1),
      child: Material(
        color: selected ? cs.primary.withAlpha(0x29) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 42),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: leading ??
                        Icon(icon ?? Icons.tag_rounded, size: 17, color: ic),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        color: fg,
                      ),
                    ),
                  ),
                  if (meta != null && meta!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        meta!,
                        style: TextStyle(fontSize: 13, color: sub),
                      ),
                    ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ] else if (unread > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
