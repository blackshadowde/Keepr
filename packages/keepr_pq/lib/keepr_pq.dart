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
