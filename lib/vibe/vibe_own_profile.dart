// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_photo_crop.dart';
import 'package:vibe/vibe/vibe_set_status.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vibe/utils/file_selector.dart';
import 'package:matrix/matrix.dart';

/// Your profile: one page for your picture, name, status, Keepr ID and the
/// rest (it used to be two, and one was easy to miss).
abstract class VibeOwnProfile {
  static Future<void> show(BuildContext context, Client client) =>
      VibeSetStatusPage.open(context, client);

  /// Take a photo, pick one, or remove yours. True when it changed.
  static Future<bool> changePhoto(
    BuildContext context,
    Client client, {
    required bool hasPhoto,
  }) async {
    final action = await showVibeSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (hasPhoto)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                title: Text(
                  'Remove photo',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return false;
    if (action == 'remove') {
      final r = await showFutureLoadingDialog(
        context: context,
        future: () => client.setAvatar(null),
      );
      return r.error == null;
    }
    // Gallery goes through the file picker as it is, so animated pictures
    // (GIF, WebP) stay animated instead of being saved as a still photo.
    final XFile? picked;
    if (action == 'camera') {
      picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 60,
      );
    } else {
      picked = (await selectFiles(context, type: FileType.image)).firstOrNull;
    }
    if (picked == null || !context.mounted) return false;
    final bytes = await picked.readAsBytes();
    if (!context.mounted) return false;
    // square crop first: your picture shows round everywhere
    final square = await VibePhotoCrop.square(context, bytes, picked.name);
    if (square == null || !context.mounted) return false;
    final file = MatrixFile(bytes: square.$1, name: square.$2);
    final r = await showFutureLoadingDialog(
      context: context,
      future: () => client.setAvatar(file),
    );
    return r.error == null;
  }
}
