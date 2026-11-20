// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crop_image/crop_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:vibe/vibe/vibe_haptics.dart';

/// Square crop for profile and chat pictures: a square box you move and
/// resize over the photo, with the round shape it will show in. Done gives
/// a square picture.
class VibePhotoCrop extends StatefulWidget {
  final Uint8List bytes;

  /// Keep PNG (pictures with see-through parts stay see-through).
  final bool png;

  const VibePhotoCrop({super.key, required this.bytes, this.png = false});

  /// Crop [bytes] to a square. Gives the new bytes and a file name, the same
  /// ones for moving pictures (GIF, animated WebP stay moving), or null when
  /// cancelled.
  static Future<(Uint8List, String)?> square(
    BuildContext context,
    Uint8List bytes,
    String name,
  ) async {
    if (moves(bytes, name)) return (bytes, name);
    final png = name.toLowerCase().endsWith('.png');
    final out = await Navigator.of(context, rootNavigator: true).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VibePhotoCrop(bytes: bytes, png: png),
      ),
    );
    if (out == null) return null;
    return (out, png ? 'picture.png' : 'picture.jpg');
  }

  /// A GIF, or a WebP with its "animated" flag set.
  static bool moves(Uint8List bytes, String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.gif')) return true;
    if (bytes.length > 21 &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP' &&
        String.fromCharCodes(bytes.sublist(12, 16)) == 'VP8X') {
      return bytes[20] & 0x02 != 0;
    }
    return false;
  }

  @override
  State<VibePhotoCrop> createState() => _VibePhotoCropState();
}

class _VibePhotoCropState extends State<VibePhotoCrop> {
  final _crop = CropController(aspectRatio: 1);
  bool _busy = false;

  @override
  void dispose() {
    _crop.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    if (_busy || _crop.getImage() == null) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final square = await _crop.croppedBitmap(maxSize: 720);
      final data = await square.toByteData(format: ui.ImageByteFormat.png);
      square.dispose();
      if (data == null) throw Exception('No picture');
      final png = data.buffer.asUint8List();
      final out = widget.png ? png : await compute(_jpg, png);
      VibeHaptics.light();
      navigator.pop(out);
    } catch (e, s) {
      Logs().w('Keepr crop: could not crop the picture', e, s);
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not crop this picture')),
      );
    }
  }

  // photos as JPEG: a fraction of the size
  static Uint8List _jpg(Uint8List png) {
    final src = img.decodePng(png);
    if (src == null) return png;
    return Uint8List.fromList(img.encodeJpg(src, quality: 88));
  }

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Cancel',
                    icon: const Icon(Icons.close_rounded, color: white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text(
                      'Move and resize',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 52),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: CropImage(
                  controller: _crop,
                  image: Image.memory(widget.bytes),
                  paddingSize: 16,
                  gridColor: white,
                  gridCornerColor: white,
                  gridInnerColor: Colors.white54,
                  gridThinWidth: 1.5,
                  gridThickWidth: 4,
                  gridCornerSize: 22,
                  scrimColor: Colors.black.withValues(alpha: 0.62),
                  // the round shape it shows in, inside the square
                  overlayWidget: ValueListenableBuilder<CropControllerValue>(
                    valueListenable: _crop,
                    builder: (_, v, _) => CustomPaint(painter: _Round(v.crop)),
                  ),
                  loadingPlaceholder: const CircularProgressIndicator(
                    color: white,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Rotate',
                    icon: const Icon(
                      Icons.rotate_90_degrees_ccw_rounded,
                      color: white,
                    ),
                    onPressed: _busy
                        ? null
                        : () {
                            VibeHaptics.selection();
                            _crop.rotateLeft();
                          },
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _busy ? null : _done,
                    style: FilledButton.styleFrom(
                      backgroundColor: white,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(96, 44),
                      shape: const StadiumBorder(),
                    ),
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text(
                            'Done',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Darkens the square's corners lightly and rings the circle, so you see
/// what shows in the round picture.
class _Round extends CustomPainter {
  final Rect crop;
  _Round(this.crop);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    if (r.isEmpty) return;
    final circle = Path()..addOval(r);
    final corners = Path.combine(
      PathOperation.difference,
      Path()..addRect(r),
      circle,
    );
    canvas.drawPath(corners, Paint()..color = Colors.black26);
    canvas.drawPath(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white70,
    );
  }

  @override
  bool shouldRepaint(_Round old) => old.crop != crop;
}
