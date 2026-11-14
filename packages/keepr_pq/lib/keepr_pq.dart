// SPDX-License-Identifier: AGPL-3.0-or-later

/// ML-KEM-768 (FIPS 203) from libcrux, the formally verified implementation
/// Signal uses.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/keepr_pq_ffi.dart';

abstract final class MlKem768 {
  static const publicKeyLength = 1184;
  static const privateKeyLength = 2400;
  static const ciphertextLength = 1088;
  static const secretLength = 32;

  /// A new key pair.
  static ({Uint8List publicKey, Uint8List privateKey}) generate() {
    final pk = calloc<Uint8>(publicKeyLength);
    final sk = calloc<Uint8>(privateKeyLength);
    try {
      _check(keeprPqKeygen(pk, sk));
      return (
        publicKey: Uint8List.fromList(pk.asTypedList(publicKeyLength)),
        privateKey: Uint8List.fromList(sk.asTypedList(privateKeyLength)),
      );
    } finally {
      _wipe(sk, privateKeyLength);
      calloc.free(pk);
      calloc.free(sk);
    }
  }

  /// A fresh shared secret for the holder of [publicKey], and the
  /// ciphertext to send them. Throws on a public key that isn't valid.
  static ({Uint8List ciphertext, Uint8List secret}) encapsulate(
    Uint8List publicKey,
  ) {
    _length(publicKey, publicKeyLength);
    final pk = calloc<Uint8>(publicKeyLength);
    final ct = calloc<Uint8>(ciphertextLength);
    final ss = calloc<Uint8>(secretLength);
    try {
      pk.asTypedList(publicKeyLength).setAll(0, publicKey);
      _check(keeprPqEncapsulate(pk, ct, ss));
      return (
        ciphertext: Uint8List.fromList(ct.asTypedList(ciphertextLength)),
        secret: Uint8List.fromList(ss.asTypedList(secretLength)),
      );
    } finally {
      _wipe(ss, secretLength);
      calloc.free(pk);
      calloc.free(ct);
      calloc.free(ss);
    }
  }

  /// The shared secret from a [ciphertext] sent to the holder of
  /// [privateKey].
  static Uint8List decapsulate(Uint8List privateKey, Uint8List ciphertext) {
    _length(privateKey, privateKeyLength);
    _length(ciphertext, ciphertextLength);
    final sk = calloc<Uint8>(privateKeyLength);
    final ct = calloc<Uint8>(ciphertextLength);
    final ss = calloc<Uint8>(secretLength);
    try {
      sk.asTypedList(privateKeyLength).setAll(0, privateKey);
      ct.asTypedList(ciphertextLength).setAll(0, ciphertext);
      _check(keeprPqDecapsulate(sk, ct, ss));
      return Uint8List.fromList(ss.asTypedList(secretLength));
    } finally {
      _wipe(sk, privateKeyLength);
      _wipe(ss, secretLength);
      calloc.free(sk);
      calloc.free(ct);
      calloc.free(ss);
    }
  }

  static void _length(Uint8List b, int want) {
    if (b.length != want) {
      throw ArgumentError('Expected $want bytes, got ${b.length}');
    }
  }

  static void _check(int r) {
    if (r != 0) throw StateError('ML-KEM failed ($r)');
  }

  static void _wipe(Pointer<Uint8> p, int n) =>
      p.asTypedList(n).fillRange(0, n, 0);
}

/// AES-256-GCM, HKDF-SHA256 and random bytes (RustCrypto).
abstract final class PqSymmetric {
  static const keyLength = 32;
  static const nonceLength = 12;
  static const tagLength = 16;

  /// [n] random bytes from the system.
  static Uint8List random(int n) {
    final p = calloc<Uint8>(n < 1 ? 1 : n);
    try {
      MlKem768._check(keeprPqRandom(p, n));
      return Uint8List.fromList(p.asTypedList(n));
    } finally {
      calloc.free(p);
    }
  }

  /// A 32-byte key from [ikm] and [info] (HKDF-SHA256, no salt).
  static Uint8List hkdf(Uint8List ikm, Uint8List info) {
    final a = _copy(ikm), b = _copy(info), out = calloc<Uint8>(keyLength);
    try {
      MlKem768._check(keeprPqHkdf(a, ikm.length, b, info.length, out));
      return Uint8List.fromList(out.asTypedList(keyLength));
    } finally {
      MlKem768._wipe(a, ikm.length < 1 ? 1 : ikm.length);
      MlKem768._wipe(out, keyLength);
      calloc.free(a);
      calloc.free(b);
      calloc.free(out);
    }
  }

  /// Seals [plain] with [key] and [aad]; returns the random nonce and the
  /// ciphertext (with the tag at the end).
  static ({Uint8List nonce, Uint8List cipher}) seal(
    Uint8List key,
    Uint8List aad,
    Uint8List plain,
  ) {
    MlKem768._length(key, keyLength);
    final k = _copy(key), a = _copy(aad), p = _copy(plain);
    final n = calloc<Uint8>(nonceLength);
    final c = calloc<Uint8>(plain.length + tagLength);
    try {
      MlKem768._check(
        keeprPqSeal(k, a, aad.length, p, plain.length, n, c),
      );
      return (
        nonce: Uint8List.fromList(n.asTypedList(nonceLength)),
        cipher: Uint8List.fromList(c.asTypedList(plain.length + tagLength)),
      );
    } finally {
      MlKem768._wipe(k, keyLength);
      MlKem768._wipe(p, plain.length < 1 ? 1 : plain.length);
      for (final x in [k, a, p, n, c]) {
        calloc.free(x);
      }
    }
  }

  /// Opens what [seal] made, or null if it was changed, the key is wrong or
  /// the aad doesn't match.
  static Uint8List? open(
    Uint8List key,
    Uint8List aad,
    Uint8List nonce,
    Uint8List cipher,
  ) {
    if (key.length != keyLength ||
        nonce.length != nonceLength ||
        cipher.length < tagLength) {
      return null;
    }
    final len = cipher.length - tagLength;
    final k = _copy(key), a = _copy(aad), n = _copy(nonce), c = _copy(cipher);
    final p = calloc<Uint8>(len < 1 ? 1 : len);
    try {
      final r = keeprPqOpen(k, a, aad.length, n, c, cipher.length, p);
      if (r != 0) return null;
      return Uint8List.fromList(p.asTypedList(len));
    } finally {
      MlKem768._wipe(k, keyLength);
      MlKem768._wipe(p, len < 1 ? 1 : len);
      for (final x in [k, a, n, c, p]) {
        calloc.free(x);
      }
    }
  }

  /// A native copy of [b] (at least one byte, so it's never null).
  static Pointer<Uint8> _copy(Uint8List b) {
    final p = calloc<Uint8>(b.isEmpty ? 1 : b.length);
    p.asTypedList(b.length).setAll(0, b);
    return p;
  }
}
