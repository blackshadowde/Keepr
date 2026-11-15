// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:keepr_pq/keepr_pq.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vibe/config/setting_keys.dart';

enum BujjiModelStatus { off, downloading, ready, failed }

/// Bujji's optional sentence model (all-MiniLM-L6-v2, about 23 MB), so it
/// understands questions worded differently from what you told it. Off
/// until you download it in its settings; it comes from Keepr's own GitHub
/// releases, is checked against a fixed SHA-256, and runs on the phone.
abstract class BujjiModel {
  static const _base =
      'https://github.com/blackshadowde/Keepr/releases/download/bujji-model-1';
  static const _files = {
    'model.onnx':
        'afdb6f1a0e45b715d0bb9b11772f032c399babd23bfc31fed1c170afc848bdb1',
    'tokenizer.json':
        'da0e79933b9ed51798a3ae27893d3c5fa4a201126cef75586296df9b4d2c62a0',
  };
  static const sizeMb = 23;
  static const _okKey = 'keepr.bujji.model.ok';
  static const _onKey = 'keepr.bujji.model.on';

  static final status = ValueNotifier<BujjiModelStatus>(BujjiModelStatus.off);

  /// 0..1 while downloading.
  static final progress = ValueNotifier<double>(0);

  static bool get downloaded => AppSettings.store.getBool(_okKey) ?? false;
  static bool get on => downloaded && (AppSettings.store.getBool(_onKey) ?? true);

  static Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}/bujji');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static void refresh() {
    if (status.value == BujjiModelStatus.downloading) return;
    status.value = on
        ? BujjiModelStatus.ready
        : downloaded
        ? BujjiModelStatus.off
        : status.value == BujjiModelStatus.failed
        ? BujjiModelStatus.failed
        : BujjiModelStatus.off;
  }

  static Future<void> setOn(bool v) async {
    await AppSettings.store.setBool(_onKey, v);
    if (!v) await _unload();
    refresh();
  }

  /// Downloads both files, checks them, and turns the model on.
  static Future<bool> download() async {
    if (status.value == BujjiModelStatus.downloading) return false;
    status.value = BujjiModelStatus.downloading;
    progress.value = 0;
    final dir = await _dir();
    final client = http.Client();
    try {
      var done = 0;
      const total = sizeMb * 1024 * 1024 + 712 * 1024;
      for (final e in _files.entries) {
        final part = File('${dir.path}/${e.key}.part');
        final res = await client.send(http.Request('GET', Uri.parse('$_base/${e.key}')));
        if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
        final sink = part.openWrite();
        await for (final chunk in res.stream) {
          sink.add(chunk);
          done += chunk.length;
          progress.value = math.min(0.99, done / total);
        }
        await sink.close();
        final path = part.path;
        final sum = await Isolate.run(() => SentenceModel.sha256File(path));
        if (sum != e.value) {
          await part.delete();
          throw Exception('checksum');
        }
        await part.rename('${dir.path}/${e.key}');
      }
      await AppSettings.store.setBool(_okKey, true);
      await AppSettings.store.setBool(_onKey, true);
      progress.value = 1;
      status.value = BujjiModelStatus.ready;
      return true;
    } catch (_) {
      status.value = BujjiModelStatus.failed;
      return false;
    } finally {
      client.close();
    }
  }

  /// Deletes the files and frees the memory.
  static Future<void> remove() async {
    await _unload();
    await AppSettings.store.setBool(_okKey, false);
    try {
      final d = await _dir();
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
    status.value = BujjiModelStatus.off;
  }

  static bool _loaded = false;
  static Future<bool>? _loading;

  static Future<bool> _ensureLoaded() async {
    if (_loaded) return true;
    return _loading ??= () async {
      final d = await _dir();
      final m = '${d.path}/model.onnx', t = '${d.path}/tokenizer.json';
      final ok = await Isolate.run(() => SentenceModel.load(m, t));
      _loaded = ok;
      _loading = null;
      return ok;
    }();
  }

  static Future<void> _unload() async {
    if (!_loaded) return;
    _loaded = false;
    _cache.clear();
    await Isolate.run(SentenceModel.unload);
  }

  static final _cache = <String, Float32List>{};

  /// The vector for [text], or null when the model is off.
  static Future<Float32List?> embed(String text) async {
    if (!on) return null;
    final hit = _cache[text];
    if (hit != null) return hit;
    try {
      if (!await _ensureLoaded()) return null;
      final v = await Isolate.run(() => SentenceModel.embed(text));
      if (v != null) {
        if (_cache.length > 300) _cache.clear();
        _cache[text] = v;
      }
      return v;
    } catch (_) {
      return null;
    }
  }

  static double similarity(Float32List a, Float32List b) {
    var s = 0.0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      s += a[i] * b[i];
    }
    return s;
  }
}
