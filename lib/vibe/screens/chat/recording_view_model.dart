// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as path_lib;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'events/audio_player.dart';

class RecordingViewModel extends StatefulWidget {
  final Widget Function(BuildContext, RecordingViewModelState) builder;

  const RecordingViewModel({required this.builder, super.key});

  @override
  RecordingViewModelState createState() => RecordingViewModelState();
}

class RecordingViewModelState extends State<RecordingViewModel> {
  Timer? _recorderSubscription;
  Duration duration = Duration.zero;

  bool get isRecording => _audioRecorder != null;

  AudioRecorder? _audioRecorder;
  final List<double> amplitudeTimeline = [];

  String? fileName;

  bool isPaused = false;

  /// Stopped to listen back before sending: the recorded file.
  String? reviewPath;
  bool get reviewing => reviewPath != null;
  AudioPlayer? _review;
  StreamSubscription? _reviewPos, _reviewState;

  /// Listening back: how far it has played (0 to 1), and whether it plays.
  final reviewAt = ValueNotifier<double>(0);
  final reviewPlaying = ValueNotifier<bool>(false);

  Future<void> startRecording(Room room) async {
    room.client.getConfig(); // Preload server file configuration.
    if (PlatformInfos.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (!mounted) return;
      if (info.version.sdkInt < 19) {
        showOkAlertDialog(
          context: context,
          title: L10n.of(context).unsupportedAndroidVersion,
          message: L10n.of(context).unsupportedAndroidVersionLong,
          okLabel: L10n.of(context).close,
        );
        return;
      }
    }
    if (await AudioRecorder().hasPermission() == false) return;

    final audioRecorder = _audioRecorder ??= AudioRecorder();
    setState(() {});

    try {
      final codec =
          !PlatformInfos
                  .isIOS && // Blocked by https://github.com/llfbandit/record/issues/560
              await audioRecorder.isEncoderSupported(AudioEncoder.opus)
          ? AudioEncoder.opus
          : AudioEncoder.aacLc;
      fileName =
          'voice_message_${DateTime.now().millisecondsSinceEpoch}.${codec.fileExtension}';
      String? path;
      if (!kIsWeb) {
        final tempDir = await getTemporaryDirectory();
        path = path_lib.join(tempDir.path, fileName);
      }

      final result = await audioRecorder.hasPermission();
      if (result != true) {
        if (!mounted) return;
        showOkAlertDialog(
          context: context,
          title: L10n.of(context).oopsSomethingWentWrong,
          message: L10n.of(context).noPermission,
        );
        return;
      }
      await WakelockPlus.enable();

      await audioRecorder.start(
        RecordConfig(
          bitRate: AppSettings.audioRecordingBitRate.value,
          sampleRate: AppSettings.audioRecordingSamplingRate.value,
          numChannels: AppSettings.audioRecordingNumChannels.value,
          autoGain: AppSettings.audioRecordingAutoGain.value,
          echoCancel: AppSettings.audioRecordingEchoCancel.value,
          noiseSuppress: AppSettings.audioRecordingNoiseSuppress.value,
          encoder: codec,
        ),
        path: path ?? '',
      );
      if (!mounted) return;
      setState(() => duration = Duration.zero);
      _subscribe();
    } catch (e, s) {
      Logs().w('Unable to start voice message recording', e, s);
      if (!mounted) return;
      showOkAlertDialog(
        context: context,
        title: L10n.of(context).oopsSomethingWentWrong,
        message: e.toString(),
      );
      setState(_reset);
    }
  }

  @override
  void dispose() {
    _reset();
    reviewAt.dispose();
    reviewPlaying.dispose();
    super.dispose();
  }

  void _subscribe() {
    _recorderSubscription?.cancel();
    _recorderSubscription = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) async {
      final amplitude = await _audioRecorder!.getAmplitude();
      var value = 100 + amplitude.current * 2;
      value = value < 1 ? 1 : value;
      amplitudeTimeline.add(value);
      setState(() {
        duration += const Duration(milliseconds: 100);
      });
    });
  }

  void _reset() {
    WakelockPlus.disable();
    _recorderSubscription?.cancel();
    _audioRecorder?.stop();
    _audioRecorder = null;
    _endReview();

    fileName = null;
    duration = Duration.zero;
    amplitudeTimeline.clear();
    isPaused = false;
  }

  void cancel() {
    setState(_reset);
  }

  void pause() {
    _audioRecorder?.pause();
    _recorderSubscription?.cancel();
    setState(() {
      isPaused = true;
    });
  }

  void resume() {
    _audioRecorder?.resume();
    _subscribe();
    setState(() {
      isPaused = false;
    });
  }

  /// Stop recording to listen back before sending.
  Future<void> stopToReview() async {
    _recorderSubscription?.cancel();
    final path = await _audioRecorder?.stop();
    if (path == null || !mounted) return;
    await WakelockPlus.disable();
    setState(() {
      reviewPath = path;
      isPaused = false;
    });
  }

  /// How long the recording is, once it can be played back.
  Duration get reviewLength => _review?.duration ?? duration;

  void _endReview() {
    _reviewPos?.cancel();
    _reviewState?.cancel();
    _review?.dispose();
    _review = null;
    reviewPath = null;
    reviewAt.value = 0;
    reviewPlaying.value = false;
  }

  /// Load the recording to listen back, if not loaded yet.
  Future<AudioPlayer?> _player() async {
    final path = reviewPath;
    if (path == null) return null;
    final loaded = _review;
    if (loaded != null) return loaded;
    final player = _review = AudioPlayer();
    if (kIsWeb) {
      await player.setUrl(path);
    } else {
      await player.setFilePath(path);
    }
    _reviewPos = player.positionStream.listen((pos) {
      final d = reviewLength.inMilliseconds;
      reviewAt.value = d <= 0 ? 0 : (pos.inMilliseconds / d).clamp(0.0, 1.0);
    });
    _reviewState = player.playerStateStream.listen((s) {
      final done = s.processingState == ProcessingState.completed;
      reviewPlaying.value = s.playing && !done;
      // played to the end: back to the start, ready to play again
      if (done) {
        player.pause();
        player.seek(Duration.zero);
      }
    });
    if (mounted) setState(() {});
    return player;
  }

  /// Play or pause what you recorded.
  Future<void> playReview() async {
    final player = await _player();
    if (player == null) return;
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  /// Jump to [f] (0 to 1) of the recording.
  Future<void> seekReview(double f) async {
    final player = await _player();
    if (player == null) return;
    final at = f.clamp(0.0, 1.0);
    reviewAt.value = at;
    await player.seek(Duration(milliseconds: (reviewLength.inMilliseconds * at).round()));
  }

  /// Throw it away and record again, without closing the pane.
  Future<void> recordAgain(Room room) async {
    setState(() {
      _endReview();
      amplitudeTimeline.clear();
      duration = Duration.zero;
      isPaused = false;
    });
    await startRecording(room);
  }

  Future<void> stopAndSend(
    Future<void> Function(
      String path,
      int duration,
      List<int> waveform,
      String fileName,
    )
    onSend,
  ) async {
    _recorderSubscription?.cancel();
    // listened back already: send that file
    final path = reviewPath ?? await _audioRecorder?.stop();

    if (path == null) throw ('Recording failed!');
    const waveCount = AudioPlayerWidget.wavesCount;
    final step = amplitudeTimeline.length < waveCount
        ? 1
        : (amplitudeTimeline.length / waveCount).round();
    final waveform = <int>[];
    for (var i = 0; i < amplitudeTimeline.length; i += step) {
      waveform.add((amplitudeTimeline[i] / 100 * 1024).round());
    }

    onSend(path, duration.inMilliseconds, waveform, fileName!);

    cancel();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, this);
}

extension on AudioEncoder {
  String get fileExtension {
    switch (this) {
      case AudioEncoder.aacLc:
      case AudioEncoder.aacEld:
      case AudioEncoder.aacHe:
        return 'm4a';
      case AudioEncoder.opus:
        return 'ogg';
      case AudioEncoder.wav:
        return 'wav';
      case AudioEncoder.amrNb:
      case AudioEncoder.amrWb:
      case AudioEncoder.flac:
      case AudioEncoder.pcm16bits:
        throw UnsupportedError('Not yet used');
    }
  }
}
