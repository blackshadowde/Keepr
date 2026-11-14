// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:async/async.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/url_launcher.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:vibe/vibe/vibe_text_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:matrix/matrix.dart' hide Result;

class PollWidget extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  final Color textColor;
  final Color linkColor;
  const PollWidget({
    required this.event,
    required this.timeline,
    required this.textColor,
    required this.linkColor,
    super.key,
  });

  void _endPoll(BuildContext context) =>
      showFutureLoadingDialog(context: context, future: event.endPoll);

  void _toggleVote(BuildContext context, String answerId, int maxSelection) {
    final userId = event.room.client.userID!;
    final answerIds = event.getPollResponses(timeline)[userId] ?? {};
    if (!answerIds.remove(answerId)) {
      answerIds.add(answerId);
      if (answerIds.length > maxSelection) {
        answerIds.clear();
        answerIds.add(answerId);
      }
    }

    showFutureLoadingDialog(
      context: context,
      future: () => event.answerPoll(answerIds.toList()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventContentResult = Result(() => event.parsedPollEventContent);
    final eventContent = eventContentResult.asValue?.value;
    if (eventContent == null) {
      Logs().w('Invalid poll event', eventContentResult.error);
      return const Text('Unable to parse poll event...');
    }
    final responses = event.getPollResponses(timeline);
    final pollHasBeenEnded = event.getPollHasBeenEnded(timeline);
    final canVote =
        event.room.canSendEvent(PollEventContent.responseType) &&
        !pollHasBeenEnded;
    final maxPolls = responses.length;
    final answersVisible =
        eventContent.pollStartContent.kind == PollKind.disclosed ||
        pollHasBeenEnded;

    final cs = Theme.of(context).colorScheme;
    final me = event.room.client.userID!;
    final multi = eventContent.pollStartContent.maxSelections > 1;
    final mine = responses[me] ?? const <String>{};

    // one card: "POLL", the question, each answer as a rounded row that
    // fills with its share of the votes, and a line about the votes
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Row(
            children: [
              Icon(Icons.poll_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                multi ? 'POLL · PICK ANY' : 'POLL',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Linkify(
            text: eventContent.pollStartContent.question.mText,
            textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
            style: TextStyle(
              color: textColor,
              fontSize: VibeTextSize.message,
              fontWeight: FontWeight.w600,
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
          const SizedBox(height: 10),
          ...eventContent.pollStartContent.answers.map((answer) {
            final votedUserIds = responses.entries
                .where((entry) => entry.value.contains(answer.id))
                .map((entry) => entry.key)
                .toSet();
            final picked = mine.contains(answer.id);
            final share = maxPolls == 0 ? 0.0 : votedUserIds.length / maxPolls;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: !canVote
                      ? null
                      : () => _toggleVote(
                          context,
                          answer.id,
                          eventContent.pollStartContent.maxSelections,
                        ),
                  child: Stack(
                    children: [
                      // the share of votes, filling from the left
                      if (answersVisible)
                        Positioned.fill(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(end: share),
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                            builder: (context, v, _) => FractionallySizedBox(
                              alignment: AlignmentDirectional.centerStart,
                              widthFactor: v,
                              child: ColoredBox(
                                color: cs.primary.withValues(
                                  alpha: picked ? 0.30 : 0.16,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              picked
                                  ? (multi
                                        ? Icons.check_box_rounded
                                        : Icons.radio_button_checked_rounded)
                                  : (multi
                                        ? Icons.check_box_outline_blank_rounded
                                        : Icons.radio_button_unchecked_rounded),
                              size: 20,
                              color: picked ? cs.primary : cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                answer.mText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: VibeTextSize.message - 1,
                                  fontWeight: picked
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (answersVisible) ...[
                              // who picked it, then the share
                              for (final id in votedUserIds.take(3))
                                Padding(
                                  padding: const EdgeInsets.only(left: 2),
                                  child: Builder(
                                    builder: (context) {
                                      final user = event.room
                                          .getState(EventTypes.RoomMember, id)
                                          ?.asUser(event.room);
                                      return Avatar(
                                        mxContent: user?.avatarUrl,
                                        name:
                                            user?.calcDisplayname() ??
                                            id.localpart,
                                        size: 16,
                                      );
                                    },
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Text(
                                '${(share * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  pollHasBeenEnded
                      ? '${L10n.of(context).countVotes(maxPolls)} · ${L10n.of(context).pollHasBeenEnded}'
                      : answersVisible
                      ? L10n.of(context).countVotes(maxPolls)
                      : L10n.of(context).answersWillBeVisibleWhenPollHasEnded,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
              if (!pollHasBeenEnded && event.senderId == me)
                TextButton(
                  onPressed: () => _endPoll(context),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: cs.primary,
                  ),
                  child: Text(L10n.of(context).endPoll),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
