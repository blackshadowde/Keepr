// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/screens/chat/trust_user_key_dialog.dart';
import 'package:vibe/utils/localized_exception_extension.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class StartPollBottomSheet extends StatefulWidget {
  final Room room;
  const StartPollBottomSheet({required this.room, super.key});

  @override
  State<StartPollBottomSheet> createState() => _StartPollBottomSheetState();
}

class _StartPollBottomSheetState extends State<StartPollBottomSheet> {
  final TextEditingController _bodyController = TextEditingController();
  bool _allowMultipleAnswers = false;
  final List<TextEditingController> _answers = [
    TextEditingController(),
    TextEditingController(),
  ];
  PollKind _pollKind = PollKind.disclosed;

  bool _canCreate = false;

  bool isLoading = false;

  String? _txid;

  Future<void> _createPoll() async {
    final proceed = await showTrustUserInRoomDialog(context, widget.room);
    if (!proceed || !mounted) return;
    try {
      var id = 0;
      _txid ??= widget.room.client.generateUniqueTransactionId();
      await widget.room.startPoll(
        question: _bodyController.text.trim(),
        answers: _answers
            .map(
              (answerController) => PollAnswer(
                id: (++id).toString(),
                mText: answerController.text.trim(),
              ),
            )
            .toList(),
        kind: _pollKind,
        maxSelections: _allowMultipleAnswers ? _answers.length : 1,
        txid: _txid,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e, s) {
      Logs().w('Unable to create poll', e, s);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    }
  }

  void _updateCanCreate([_]) {
    final newCanCreate =
        _bodyController.text.trim().isNotEmpty &&
        !_answers.any((controller) => controller.text.trim().isEmpty);
    if (_canCreate != newCanCreate) {
      setState(() {
        _canCreate = newCanCreate;
      });
    }
  }

  @override
  void dispose() {
    _bodyController.dispose();
    for (final answerController in _answers) {
      answerController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const maxAnswers = 10;
    final cs = Theme.of(context).colorScheme;
    InputDecoration field(String hint, {Widget? suffix, Widget? prefix}) =>
        InputDecoration(
          hintText: hint,
          counter: const SizedBox.shrink(),
          filled: true,
          fillColor: cs.surfaceContainerHigh,
          prefixIcon: prefix,
          suffixIcon: suffix,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        );
    return Scaffold(
      appBar: AppBar(
        leading: CloseButton(onPressed: Navigator.of(context).pop),
        title: Text(
          L10n.of(context).startPoll,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // the question
          TextField(
            controller: _bodyController,
            minLines: 2,
            maxLines: 4,
            maxLength: 1024,
            autofocus: true,
            onChanged: _updateCanCreate,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            decoration: field(L10n.of(context).pollQuestion),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Answers',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          // the answers, numbered
          for (var i = 0; i < _answers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                key: ObjectKey(_answers[i]),
                controller: _answers[i],
                onChanged: _updateCanCreate,
                maxLength: 64,
                decoration: field(
                  L10n.of(context).answerOption,
                  prefix: Padding(
                    padding: const EdgeInsets.all(12),
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: cs.primary.withValues(alpha: 0.18),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                  suffix: _answers.length == 2
                      ? null
                      : IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() {
                            _answers.remove(_answers[i]..dispose());
                            _updateCanCreate();
                          }),
                        ),
                ),
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.add_rounded),
              onPressed: _answers.length < maxAnswers
                  ? () => setState(() {
                      _answers.add(TextEditingController());
                      _updateCanCreate();
                    })
                  : null,
              label: Text(L10n.of(context).addAnswerOption),
            ),
          ),
          const SizedBox(height: 18),
          Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: _pollKind == PollKind.disclosed,
                  onChanged: (allow) => setState(() {
                    _pollKind = allow
                        ? PollKind.disclosed
                        : PollKind.undisclosed;
                  }),
                  title: Text(L10n.of(context).answersVisible),
                ),
                SwitchListTile.adaptive(
                  value: _allowMultipleAnswers,
                  onChanged: (allow) => setState(() {
                    _allowMultipleAnswers = allow;
                  }),
                  title: Text(L10n.of(context).allowMultipleAnswers),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: !isLoading && _canCreate ? _createPoll : null,
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      L10n.of(context).startPoll,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
