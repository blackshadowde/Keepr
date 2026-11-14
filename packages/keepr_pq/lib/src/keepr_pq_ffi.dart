// SPDX-License-Identifier: AGPL-3.0-or-later

// The Rust functions (rust/src/lib.rs). Each returns 0 on success.

import 'dart:ffi';

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
