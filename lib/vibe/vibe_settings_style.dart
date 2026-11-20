// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';
import 'package:flutter/material.dart';

/// Vibgram's Discord-style settings look, shared by Settings and every page
/// under it: a soft grey page, rounded cards a shade lighter, grey section
/// titles inside the cards, filled white (dark) / black (light) icons.
abstract class VibeSettingsStyle {
  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color page(BuildContext context) => !VibePalette.fixed(context)
      ? Theme.of(context).colorScheme.surface
      : _dark(context) ? const Color(0xFF1C1B20) : const Color(0xFFFFFFFF);

  static Color card(BuildContext context) => !VibePalette.fixed(context)
      ? Theme.of(context).colorScheme.surfaceContainer
      : _dark(context) ? const Color(0xFF26252B) : const Color(0xFFF2F3F5);

  static Color line(BuildContext context) => !VibePalette.fixed(context)
      ? Theme.of(context).colorScheme.outlineVariant
      : _dark(context) ? const Color(0xFF33323A) : const Color(0xFFE1E2E6);

  static Color get accent => VibePalette.accent;

  /// The small grey tile behind a row's icon, a step darker than the card.
  static Color tile(BuildContext context) => !VibePalette.fixed(context)
      ? _dark(context)
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Theme.of(context).colorScheme.surfaceContainerHigh
      : _dark(context) ? const Color(0xFF34333B) : const Color(0xFFE4E5E9);

  /// The small green dot for something that's working (encryption on).
  static Color ok(BuildContext context) =>
      _dark(context) ? const Color(0xFF6DD58C) : const Color(0xFF2E9E5B);

  /// The chevron at the end of a row: quieter than the words.
  static Color chevron(BuildContext context) =>
      text2(context).withValues(alpha: 0.75);

  /// Row text inside settings cards. Built on the app's text theme so it
  /// uses the app font (a bare TextStyle here fell back to the system font,
  /// because list tiles replace the inherited style instead of merging).
  static TextStyle rowTitle(BuildContext context) =>
      (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(
        fontSize: 16.5,
        fontWeight: FontWeight.w600,
        color: text(context),
        height: 1.25,
        letterSpacing: 0,
      );

  static TextStyle rowSubtitle(BuildContext context) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: 13.5,
        color: text2(context),
        height: 1.3,
        letterSpacing: 0,
      );

  /// Compact list rows for every settings card.
  static ListTileThemeData listTiles(BuildContext context) =>
      ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 11,
        minTileHeight: 52,
        horizontalTitleGap: 14,
        iconColor: text(context),
        titleTextStyle: rowTitle(context),
        subtitleTextStyle: rowSubtitle(context),
        visualDensity: const VisualDensity(vertical: -1),
      );

  /// Slim Discord-style switch colours for any Material [Switch] left over.
  static SwitchThemeData switches(BuildContext context) {
    final dark = _dark(context);
    return SwitchThemeData(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      thumbIcon: const WidgetStatePropertyAll(null),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Colors.white
            : (dark ? const Color(0xFFDBDEE1) : const Color(0xFF80848E)),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? accent
            : !VibePalette.fixed(context)
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : (dark ? const Color(0xFF4E5058) : const Color(0xFFE3E5E8)),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      trackOutlineWidth: const WidgetStatePropertyAll(0),
    );
  }

  static Color text(BuildContext context) => !VibePalette.fixed(context)
      ? Theme.of(context).colorScheme.onSurface
      : _dark(context) ? const Color(0xFFF2F3F5) : const Color(0xFF060607);

  static Color text2(BuildContext context) => !VibePalette.fixed(context)
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : _dark(context) ? const Color(0xFFB5BAC1) : const Color(0xFF5C5E66);
}

/// Wraps a settings page: page colour behind everything, header bar in the
/// same colour (also while scrolling), grey section titles, no tinting.
class VibeSettingsTheme extends StatelessWidget {
  final Widget child;
  const VibeSettingsTheme({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = VibeSettingsStyle.page(context);
    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: page,
        canvasColor: page,
        colorScheme: theme.colorScheme.copyWith(
          // FluffyChat colours section titles with "secondary": Vibgram's are grey.
          secondary: VibeSettingsStyle.text2(context),
        ),
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: page,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          // page titles ("Settings", "Notifications"): big and heavy
          titleTextStyle: (theme.textTheme.titleLarge ?? const TextStyle())
              .copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: VibeSettingsStyle.text(context),
              ),
        ),
        dividerTheme: theme.dividerTheme.copyWith(
          color: VibeSettingsStyle.line(context),
        ),
        listTileTheme: VibeSettingsStyle.listTiles(context),
        switchTheme: VibeSettingsStyle.switches(context),
        // back and close sit in a round button, like on the Settings page
        actionIconTheme: ActionIconThemeData(
          backButtonIconBuilder: (context) =>
              const VibeRoundIcon(Icons.arrow_back_rounded),
          closeButtonIconBuilder: (context) =>
              const VibeRoundIcon(Icons.close_rounded),
        ),
      ),
      child: child,
    );
  }
}

/// Drop-in for a settings Column: every run of rows between two [Divider]s
/// becomes one rounded card (Discord style), with a thin line between rows.
/// A bold header row at the start of a run (FluffyChat's section titles)
/// becomes a plain grey label above its card.
class VibeGroups extends StatelessWidget {
  final List<Widget> children;
  const VibeGroups({required this.children, super.key});

  /// FluffyChat's section title: a ListTile with only a bold title.
  static String? _headerText(Widget w) {
    if (w is! ListTile) return null;
    if (w.onTap != null ||
        w.subtitle != null ||
        w.leading != null ||
        w.trailing != null) {
      return null;
    }
    final t = w.title;
    if (t is Text && t.style?.fontWeight == FontWeight.bold) return t.data;
    return null;
  }

  /// A row's plain icon gets the small grey tile the Settings page has.
  static Widget _tiled(Widget w) {
    if (w is! ListTile) return w;
    final icon = w.leading;
    if (icon is! Icon) return w;
    return ListTile(
      key: w.key,
      leading: VibeIconTile(icon.icon, color: icon.color),
      title: w.title,
      subtitle: w.subtitle,
      trailing: w.trailing,
      isThreeLine: w.isThreeLine,
      dense: w.dense,
      visualDensity: w.visualDensity,
      shape: w.shape,
      style: w.style,
      selectedColor: w.selectedColor,
      iconColor: w.iconColor,
      textColor: w.textColor,
      titleTextStyle: w.titleTextStyle,
      subtitleTextStyle: w.subtitleTextStyle,
      leadingAndTrailingTextStyle: w.leadingAndTrailingTextStyle,
      contentPadding: w.contentPadding,
      enabled: w.enabled,
      onTap: w.onTap,
      onLongPress: w.onLongPress,
      onFocusChange: w.onFocusChange,
      mouseCursor: w.mouseCursor,
      selected: w.selected,
      focusColor: w.focusColor,
      hoverColor: w.hoverColor,
      splashColor: w.splashColor,
      focusNode: w.focusNode,
      autofocus: w.autofocus,
      tileColor: w.tileColor,
      selectedTileColor: w.selectedTileColor,
      enableFeedback: w.enableFeedback,
      horizontalTitleGap: w.horizontalTitleGap,
      minVerticalPadding: w.minVerticalPadding,
      minLeadingWidth: w.minLeadingWidth,
      minTileHeight: w.minTileHeight,
      titleAlignment: w.titleAlignment,
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = <({String? title, List<Widget> rows})>[];
    String? title;
    var rows = <Widget>[];
    void flush() {
      if (rows.isNotEmpty || title != null) {
        groups.add((title: title, rows: rows));
      }
      title = null;
      rows = [];
    }

    for (final c in children) {
      if (c is Divider) {
        flush();
        continue;
      }
      final h = _headerText(c);
      if (h != null && rows.isEmpty) {
        title = h;
        continue;
      }
      rows.add(c);
    }
    flush();
    return ListTileTheme.merge(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      minVerticalPadding: 11,
      minTileHeight: 52,
      minLeadingWidth: 38,
      horizontalTitleGap: 14,
      titleTextStyle: VibeSettingsStyle.rowTitle(context).copyWith(fontSize: 15.5),
      subtitleTextStyle: VibeSettingsStyle.rowSubtitle(context).copyWith(fontSize: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          for (var i = 0; i < groups.length; i++) ...[
            // two cards in a row without a title between them: a small gap
            if (i > 0 && groups[i].title == null) const SizedBox(height: 12),
            if (groups[i].title != null) VibeSectionLabel(groups[i].title!),
            if (groups[i].rows.isNotEmpty)
              VibeCard(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                children: [for (final r in groups[i].rows) _tiled(r)],
              ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Small grey title above a card ("ACCOUNT", "APP"), in capitals.
class VibeSectionLabel extends StatelessWidget {
  final String text;
  const VibeSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 18, 32, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.96,
        color: VibeSettingsStyle.text2(context),
      ),
    ),
  );
}

/// Rounded card holding rows, a shade off the page; no lines between rows.
class VibeCard extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  const VibeCard({
    required this.children,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 6),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: VibeSettingsStyle.card(context),
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// A row's icon in a small rounded grey tile.
class VibeIconTile extends StatelessWidget {
  final IconData? icon;
  final Color? color;
  const VibeIconTile(this.icon, {this.color, super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: VibeSettingsStyle.tile(context),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(icon, size: 20, color: color ?? VibeSettingsStyle.text(context)),
  );
}

/// A round button in the card colour: close, back, search.
class VibeRoundButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onTap;
  const VibeRoundButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final button = VibePressable(
      scale: 0.92,
      child: Material(
        color: VibeSettingsStyle.card(context),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: 44,
            child: Icon(icon, size: 22, color: VibeSettingsStyle.text(context)),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// The look of the back and close icons on settings pages: a round button.
class VibeRoundIcon extends StatelessWidget {
  final IconData icon;
  const VibeRoundIcon(this.icon, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: VibeSettingsStyle.card(context),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: 22, color: VibeSettingsStyle.text(context)),
  );
}

/// A settings page with a big title that moves up into the bar as you
/// scroll; a round back (or close) button at the top.
class VibeTitledPage extends StatefulWidget {
  final String title;
  final List<Widget> children;

  /// A close button (Settings itself) instead of back.
  final bool close;
  final VoidCallback? onLeading;

  /// No back button (tablets, where the page sits beside the list).
  final bool leading;
  final List<Widget>? actions;
  const VibeTitledPage({
    required this.title,
    required this.children,
    this.close = false,
    this.onLeading,
    this.leading = true,
    this.actions,
    super.key,
  });

  @override
  State<VibeTitledPage> createState() => _VibeTitledPageState();
}

class _VibeTitledPageState extends State<VibeTitledPage> {
  final _small = ValueNotifier(false);

  @override
  void dispose() {
    _small.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = VibeSettingsStyle.text(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: widget.leading ? 68 : 0,
        leading: widget.leading
            ? Center(
                child: VibeRoundButton(
                  icon: widget.close
                      ? Icons.close_rounded
                      : Icons.arrow_back_rounded,
                  tooltip: widget.close
                      ? MaterialLocalizations.of(context).closeButtonTooltip
                      : MaterialLocalizations.of(context).backButtonTooltip,
                  onTap:
                      widget.onLeading ?? () => Navigator.of(context).maybePop(),
                ),
              )
            : null,
        titleSpacing: widget.leading ? 0 : 24,
        // the small title shows once the big one has scrolled away
        title: ValueListenableBuilder<bool>(
          valueListenable: _small,
          builder: (context, small, _) => AnimatedOpacity(
            opacity: small ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Text(
              widget.title,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: text),
            ),
          ),
        ),
        actions: widget.actions,
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
            _small.value = n.metrics.pixels > 34;
          }
          return false;
        },
        child: MaxWidthBody(
          // plain list rows on these pages match the settings rows
          child: ListTileTheme.merge(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            minVerticalPadding: 11,
            minTileHeight: 56,
            minLeadingWidth: 38,
            horizontalTitleGap: 14,
            titleTextStyle: VibeSettingsStyle.rowTitle(context).copyWith(fontSize: 15.5),
            subtitleTextStyle: VibeSettingsStyle.rowSubtitle(context).copyWith(fontSize: 13),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 32,
                    height: 1,
                    letterSpacing: -0.3,
                    fontWeight: FontWeight.w800,
                    color: text,
                  ),
                ),
              ),
              ...widget.children,
              const SizedBox(height: 32),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

/// A switch in the theme's colour; its dot grows when it's on.
class VibeSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const VibeSwitch({required this.value, this.onChanged, super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onChanged != null;
    final track = value
        ? VibeSettingsStyle.accent
        : !VibePalette.fixed(context)
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : (dark ? const Color(0xFF4E5058) : const Color(0xFFDADCE0));
    final knob = value ? Colors.white : VibeSettingsStyle.text2(context);
    final size = value ? 20.0 : 16.0;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: 46,
            height: 28,
            padding: EdgeInsets.all(value ? 4 : 6),
            decoration: BoxDecoration(
              color: track,
              borderRadius: BorderRadius.circular(14),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: size,
                height: size,
                decoration: BoxDecoration(color: knob, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A settings row with a [VibeSwitch]; tap anywhere on the row to toggle.
class VibeSwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  const VibeSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) => VibeSettingsRow(
    icon: icon,
    title: title,
    subtitle: subtitle,
    wrap: true,
    trailing: VibeSwitch(value: value, onChanged: onChanged),
    onTap: onChanged == null ? null : () => onChanged!(!value),
  );
}

/// One row in a settings card: the icon in a small grey tile, the title
/// with a few words under it, and a value, a switch or a chevron at the end.
class VibeSettingsRow extends StatelessWidget {
  final IconData? icon;

  /// Shown instead of the icon tile (a chat's picture).
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? value;
  final Color? valueColor;

  /// A small dot before the value: green when something is on, the theme
  /// colour when something waits for you.
  final Color? dot;

  /// Title and icon colour (Sign out).
  final Color? color;

  /// In place of the value or chevron (a switch).
  final Widget? trailing;
  final bool chevron;

  /// Let the words under the title run onto more lines.
  final bool wrap;
  final VoidCallback? onTap;

  /// Kept for older callers; rows no longer draw lines between them.
  final bool last;

  const VibeSettingsRow({
    required this.title,
    this.icon,
    this.leading,
    this.onTap,
    this.subtitle,
    this.value,
    this.valueColor,
    this.dot,
    this.color,
    this.trailing,
    this.chevron = true,
    this.wrap = false,
    this.last = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final text = color ?? VibeSettingsStyle.text(context);
    final sub = VibeSettingsStyle.text2(context);
    final font = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
    final lead = leading ?? (icon == null ? null : VibeIconTile(icon, color: color));
    final end = trailing ??
        (value != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dot != null) ...[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    value!,
                    style: font.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: valueColor ?? sub,
                    ),
                  ),
                ],
              )
            : chevron && onTap != null
            ? Icon(Icons.chevron_right_rounded, size: 22, color: VibeSettingsStyle.chevron(context))
            : null);
    return VibePressable(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: EdgeInsets.fromLTRB(lead == null ? 16 : 14, 11, 14, 11),
            child: Row(
              children: [
                if (lead != null) ...[lead, const SizedBox(width: 14)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: font.copyWith(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          letterSpacing: 0,
                          color: text,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            maxLines: wrap ? 4 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: font.copyWith(
                              fontSize: 13,
                              height: 1.3,
                              letterSpacing: 0,
                              color: sub,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (end != null) ...[const SizedBox(width: 14), end],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A settings group: a small grey title above a rounded card of rows.
class VibeSettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> rows;
  const VibeSettingsGroup({required this.title, required this.rows, super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) VibeSectionLabel(title!),
        VibeCard(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          children: rows,
        ),
      ],
    );
  }
}
