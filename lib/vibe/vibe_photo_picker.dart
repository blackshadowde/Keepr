// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Picking photos opens Android's own photo picker: it needs no permission,
/// and when Google Photos is set up there it can search and pick from
/// Google Photos too.
abstract class VibePhotoPicker {
  static void useSystem() {
    final picker = ImagePickerPlatform.instance;
    if (picker is ImagePickerAndroid) picker.useAndroidPhotoPicker = true;
  }
}
