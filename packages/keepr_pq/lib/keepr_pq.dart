// SPDX-License-Identifier: AGPL-3.0-or-later

/// ML-KEM-768 (FIPS 203) from libcrux, the formally verified implementation
/// Signal uses. On the web (no native code there) a stand-in with the same
/// names that says it isn't available.
library;

export 'src/native.dart' if (dart.library.js_interop) 'src/web.dart';
