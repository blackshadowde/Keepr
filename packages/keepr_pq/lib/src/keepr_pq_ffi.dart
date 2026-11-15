// SPDX-License-Identifier: AGPL-3.0-or-later

// The Rust functions (rust/src/lib.rs). Each returns 0 on success.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

@Native<Int32 Function(Pointer<Uint8>, Pointer<Uint8>)>(
  symbol: 'keepr_pq_keygen',
)
external int keeprPqKeygen(Pointer<Uint8> pk, Pointer<Uint8> sk);

@Native<Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)>(
  symbol: 'keepr_pq_encapsulate',
)
external int keeprPqEncapsulate(
  Pointer<Uint8> pk,
  Pointer<Uint8> ct,
  Pointer<Uint8> ss,
);

@Native<Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)>(
  symbol: 'keepr_pq_decapsulate',
)
external int keeprPqDecapsulate(
  Pointer<Uint8> sk,
  Pointer<Uint8> ct,
  Pointer<Uint8> ss,
);

@Native<Int32 Function(Pointer<Uint8>, Size)>(symbol: 'keepr_pq_random')
external int keeprPqRandom(Pointer<Uint8> out, int len);

@Native<
  Int32 Function(Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<Uint8>)
>(symbol: 'keepr_pq_hkdf')
external int keeprPqHkdf(
  Pointer<Uint8> ikm,
  int ikmLen,
  Pointer<Uint8> info,
  int infoLen,
  Pointer<Uint8> out,
);

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Pointer<Uint8>,
  )
>(symbol: 'keepr_pq_seal')
external int keeprPqSeal(
  Pointer<Uint8> key,
  Pointer<Uint8> aad,
  int aadLen,
  Pointer<Uint8> pt,
  int ptLen,
  Pointer<Uint8> nonce,
  Pointer<Uint8> ct,
);

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
  )
>(symbol: 'keepr_pq_open')
external int keeprPqOpen(
  Pointer<Uint8> key,
  Pointer<Uint8> aad,
  int aadLen,
  Pointer<Uint8> nonce,
  Pointer<Uint8> ct,
  int ctLen,
  Pointer<Uint8> pt,
);

@Native<Int32 Function(Pointer<Utf8>, Pointer<Utf8>)>(symbol: 'keepr_embed_load')
external int keeprEmbedLoad(Pointer<Utf8> model, Pointer<Utf8> tokenizer);

@Native<Void Function()>(symbol: 'keepr_embed_unload')
external void keeprEmbedUnload();

@Native<Int32 Function(Pointer<Utf8>, Pointer<Float>, Size)>(
  symbol: 'keepr_embed',
)
external int keeprEmbed(Pointer<Utf8> text, Pointer<Float> out, int cap);

@Native<Int32 Function(Pointer<Utf8>, Pointer<Uint8>)>(
  symbol: 'keepr_pq_sha256_file',
)
external int keeprPqSha256File(Pointer<Utf8> path, Pointer<Uint8> out);
