# Security watch

A daily check, while the owner is away (until about 2026-12-16), for critical
or high security fixes in what Keepr uses: the Matrix Dart SDK, vodozemac,
libcrux, FluffyChat and the pub and Rust packages in the lock files. Critical
or high items are fixed on a `hotfix/…` branch and released (Android only);
everything else is listed under "For the owner".

Last checked: 2026-11-19 09:15 UTC (window 2026-11-16 to 2026-11-19)

## For the owner

- Matrix Dart SDK 17.0.0 (2026-11-18) has "fix: missing mac or iv handles
  key as valid": a secret storage (recovery) key description without its
  check values was taken as matching any key. Not rated and no advisory; it
  needs the server or someone with account data access to plant such a key,
  so it's left for you. It only ships in 17.0.0, a new major version (also
  makes `Room.states` read-only, a breaking change), so it isn't a simple
  bump from 16.x. Worth moving to 17 when you're back.
  https://pub.dev/packages/matrix/changelog
- This run's access was narrower than before: it could not reach GitHub's
  global advisory list, FluffyChat's commits, pub.dev, crates.io or osv.dev,
  only web search and web pages. FluffyChat commits since 2026-11-16 are not
  checked yet; the next run with full access should cover them.
- `pubspec.lock` on `Vibe` and `vibe-next` is out of date: it still says
  matrix 10.0.1, flutter_vodozemac 0.7.1 and vodozemac 0.7.0, while
  `pubspec.yaml` asks for matrix ^16.0.4 and flutter_vodozemac ^0.9.0. The
  builds re-resolve it (the 3.1.158 release log shows matrix 16.0.4,
  flutter_vodozemac 0.9.1, vodozemac 0.9.1), so the app is fine, but the
  versions a build gets are not pinned. Running `flutter pub get` and
  committing the lock file would pin them.
- `packages/keepr_pq/rust/Cargo.lock` is not in the repo (ignored), so the
  Rust versions used by the post-quantum layer and Bujji's matching are
  picked at build time and can't be checked here. Consider committing it.
- Branch `deps/matrix-16-vodozemac-0.9.1` (2026-11-14) does the same update
  that 3.1.158 already shipped; it is probably no longer needed. Not touched.
- Synapse 1.165.0 (2026-11-10): media downloads answer HEAD requests without
  reading the file. Nothing for Keepr to change; noted in case media checks
  behave differently.
- MSC4388 (sign in with a QR code over a secure channel) is close to being
  accepted; vodozemac 0.11.1 already changed its check codes for it. Only
  matters if QR sign-in is added.

## Log

### 2026-11-19

- Matrix Dart SDK 17.0.0 (2026-11-18): secret storage key check fix (see
  "For the owner"), Room.states read-only, webdev bump. Medium at most, not
  a same-major bump. No change.
  https://pub.dev/packages/matrix/changelog
- RustSec advisories 2026-11-16 to 2026-11-18 (lettre, zip, libz-sys,
  hickory, actix-http, chrono and others marked unmaintained): none for
  crates the post-quantum layer uses (libcrux-ml-kem, aes-gcm, hkdf, sha2,
  getrandom, tract, tokenizers) or vodozemac. No change.
  https://rustsec.org/advisories/
- vodozemac / flutter_vodozemac: nothing new since RUSTSEC-2026-0510
  (2026-11-12, already covered). No change.
- libcrux: no new advisories. No change.
- matrix.org: no security disclosures; Governing Board report (2026-11-13)
  has nothing needing client changes. No change.
  https://matrix.org/category/security/
- GitHub advisories (pub, rust) and FluffyChat commits: could not be read
  this run (no access). Not checked.

### 2026-11-16

- vodozemac RUSTSEC-2026-0510 / GHSA-pqp6-f7wc-6498 (2026-11-12): a crafted
  Ed25519 key from another user could make vodozemac panic (crash). Severity
  not rated; denial of service. Fixed in vodozemac 0.11.2 (flutter_vodozemac
  0.9.1). Keepr 3.1.158 already builds with flutter_vodozemac 0.9.1 (release
  run 43743879378). No change.
  https://rustsec.org/advisories/RUSTSEC-2026-0510.html
- vodozemac RUSTSEC-2026-0451 / GHSA-v27v-f96q-qhjq and RUSTSEC-2026-0445 /
  GHSA-mxcm-mrw6-c446 (2026-11-06): secrets not wiped from memory after use;
  needs someone able to read the app's memory. Low. Fixed in 0.11.2, already
  in 3.1.158. No change.
  https://rustsec.org/advisories/RUSTSEC-2026-0451.html
- Matrix Dart SDK 16.0.2 and 16.0.3 (2026-11-10): decrypted keys no longer
  logged, Olm account kept in its own secure storage key, safer token
  refresh, edits decrypted in getTimeline. Already in 3.1.158 (matrix
  16.0.4). No change.
  https://github.com/famedly/matrix-dart-sdk/releases/tag/v16.0.2
- GitHub advisories, pub ecosystem: none published in the window. Older ones
  (archive 2023, http 2020) don't affect Keepr's versions. No change.
- libcrux: no advisories in the window. The October ones (RUSTSEC-2026-0329,
  0330, 0331) are for libcrux-kem and libcrux-hmac-drbg, which Keepr doesn't
  use (it uses libcrux-ml-kem 0.0.11). No change.
- FluffyChat commits 2026-11-09 to 2026-11-15 (15): dependency bumps only
  (matrix 16.0.1, flutter_local_notifications 23.0.0, cupertino_ui,
  light_compressor_v2, gradle plugin, fcm_shared_isolate). No security fixes.
  No change.
- matrix.org: no security disclosures in the window (This Week in Matrix
  2026-11-06 and 2026-11-13). No change.
