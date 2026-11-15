// SPDX-License-Identifier: AGPL-3.0-or-later

// The web has no native code, so ML-KEM, the sealing and the sentence model
// aren't available there: the same names as src/native.dart, saying so.

import 'dart:math';
import 'dart:typed_data';

Never _no() => throw UnsupportedError(
  'Post-quantum encryption is not available on the web yet',
);

abstract final class MlKem768 {
  static const publicKeyLength = 1184;
  static const privateKeyLength = 2400;
  static const ciphertextLength = 1088;
  static const secretLength = 32;

  static ({Uint8List publicKey, Uint8List privateKey}) generate() => _no();

  static ({Uint8List ciphertext, Uint8List secret}) encapsulate(
    Uint8List publicKey,
  ) => _no();

  static Uint8List decapsulate(Uint8List privateKey, Uint8List ciphertext) =>
      _no();
}

abstract final class PqSymmetric {
  static const keyLength = 32;
  static const nonceLength = 12;
  static const tagLength = 16;

  static Uint8List random(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  static Uint8List hkdf(Uint8List ikm, Uint8List info) => _no();

  static ({Uint8List nonce, Uint8List cipher}) seal(
    Uint8List key,
    Uint8List aad,
    Uint8List plain,
  ) => _no();

  static Uint8List? open(
    Uint8List key,
    Uint8List aad,
    Uint8List nonce,
    Uint8List cipher,
  ) => _no();
}

abstract final class SentenceModel {
  static bool load(String model, String tokenizer) => false;

  static void unload() {}

  static Float32List? embed(String text) => null;

  static String? sha256File(String path) => null;
}
