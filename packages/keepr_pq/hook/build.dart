// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

// Builds rust/ (ML-KEM-768 via libcrux) for the app's targets.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await RustBuilder(
      assetName: 'src/keepr_pq_ffi.dart',
    ).run(input: input, output: output);
  });
}
