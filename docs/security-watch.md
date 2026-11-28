# Security watch

A daily check, while the owner is away (until about 2026-12-16), for critical
or high security fixes in what Keepr uses: the Matrix Dart SDK, vodozemac,
libcrux, FluffyChat and the pub and Rust packages in the lock files. Critical
or high items are fixed on a `hotfix/…` branch and released (Android only);
everything else is listed under "For the owner".

Last checked: 2026-11-28 09:12 UTC (window 2026-11-27 to 2026-11-28)

## For the owner

- Matrix Dart SDK 17.1.0 (2026-11-23) also has "fix: don't log call
  encryption keys": group call encryption keys were written to the app's
  logs. Not rated and no advisory; the logs stay on the phone unless
  someone shares them, so it's left for you. It comes with the move to 17
  or 18 below. 17.1.0 also has "fix: keep the content of an event that
  cannot be decrypted" (a message that fails to decrypt no longer loses its
  encrypted content, so it can still be decrypted when the key arrives).
  Not rated either; it comes with the same move.
  https://pub.dev/packages/matrix/changelog

- Matrix Dart SDK 18.0.0 (2026-11-25): another new major version. It moves
  to vodozemac 0.10.0 from the dart-vodozemac release (breaking), checks the
  downloaded vodozemac against the release's SHA256SUMS, and repeats a
  backup key request that found nothing once the backup changes (so keys
  that arrive in the backup later still get used). No advisory or security
  rating. If you move off 16.x, consider going straight to 18 rather than
  17. https://github.com/famedly/matrix-dart-sdk/releases/tag/v18.0.0

- Matrix Dart SDK 17.0.0 (2026-11-18) has "fix: missing mac or iv handles
  key as valid": a secret storage (recovery) key description without its
  check values was taken as matching any key. Not rated and no advisory; it
  needs the server or someone with account data access to plant such a key,
  so it's left for you. It only ships in 17.0.0, a new major version (also
  makes `Room.states` read-only, a breaking change), so it isn't a simple
  bump from 16.x. Worth moving to 17 when you're back (17.1.0, 2026-11-23,
  is the newest; the `independent` branch already has a move to 17).
  https://pub.dev/packages/matrix/changelog
- The runs since 2026-11-19 can't reach GitHub's global advisory list or
  FluffyChat's commits (this scheduled task is only given Keepr's own repo),
  only web search and web pages. FluffyChat commits since 2026-11-16 are not
  checked yet. To fix it, ask Claude in a new chat to add the repos the task
  needs (blackshadowde/Keepr and krille-chan/fluffychat) and remake this task.
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
- MSC4388 (sign in with a QR code over a secure channel) was accepted
  (This Week in Matrix 2026-11-20); vodozemac 0.11.1 already changed its check codes for it. Only
  matters if QR sign-in is added.

## Log

### 2026-11-28

- Matrix Dart SDK: nothing after 18.0.0 (2026-11-25); no 16.x after
  16.0.4. The 17.1.0 entry "keep the content of an event that cannot be
  decrypted" added to "For the owner". No change.
  https://pub.dev/packages/matrix/changelog
- RustSec since the last run: RUSTSEC-2026-0602 and 0603 dryoc (Ed25519
  key pair check; X25519 low-order keys, medium), RUSTSEC-2026-0601 wsts
  (FROST, medium). Not crates Keepr uses. No change.
  https://rustsec.org/advisories/
- vodozemac / flutter_vodozemac and libcrux: no new advisories found. No
  change.
- matrix.org: no security post since February. This Week in Matrix
  2026-11-27 could not be read this run. No change.
  https://matrix.org/category/security/
- FluffyChat: no new release found by web search. Commits not checked.
- GitHub advisories (pub, rust) and FluffyChat commits: still not reachable
  (the task is only given blackshadowde/Keepr). Not checked.

### 2026-11-27

- Matrix Dart SDK: nothing after 18.0.0 (2026-11-25); no 16.x after
  16.0.4. Reading the 17.1.0 changelog again turned up the call key
  logging fix (see "For the owner"). No change.
  https://pub.dev/packages/matrix/changelog
- vodozemac / flutter_vodozemac and libcrux: no new advisories found. No
  change.
- matrix.org: no security post since February. No change.
  https://matrix.org/category/security/
- RustSec: the advisory list could not be read this run, and web search
  showed nothing newer than the 2026-11-26 entry. Not checked.
- FluffyChat: no new release found by web search. Commits not checked.
- GitHub advisories (pub, rust) and FluffyChat commits: still not reachable
  (the task is only given blackshadowde/Keepr). Not checked.

### 2026-11-26

- Matrix Dart SDK 18.0.0 (2026-11-25): vodozemac 0.10.0 bump (breaking),
  SHA256 check of the vodozemac download, backup key request repeated after
  the backup changes. Not a security advisory and not a same-major bump; no
  16.x after 16.0.4. No change (see "For the owner").
  https://github.com/famedly/matrix-dart-sdk/releases/tag/v18.0.0
- RustSec since the last run: RUSTSEC-2026-0600 kube-client (medium, extra
  CA store trusted). Not a crate Keepr uses. hugepage-rs, xmloxide and
  etherparse (0596 to 0599) were already in the 2026-11-25 entry. No change.
  https://rustsec.org/advisories/
- vodozemac / flutter_vodozemac and libcrux: no new advisories. No change.
- matrix.org: no security post since February. No change.
  https://matrix.org/category/security/
- FluffyChat: no new release found by web search. Commits not checked.
- GitHub advisories (pub, rust) and FluffyChat commits: still not reachable
  (the task is only given blackshadowde/Keepr). Not checked.

### 2026-11-25

- RustSec advisories 2026-11-22 to 2026-11-24 (the list could be read this
  time): ruma-identifiers-validation (two panics), pqcrypto-dilithium,
  secure-gate, secmem-proc, url (stack overflow in `Url::origin()`),
  cookie, parquet, etherparse, xmloxide (high), hugepage-rs. None are
  crates the post-quantum layer names (libcrux-ml-kem, aes-gcm, hkdf, sha2,
  getrandom, tract-onnx, tokenizers without default features), and Keepr's
  Matrix code is Dart, not ruma. `url` could only come in through a
  dependency of those; Cargo.lock isn't in the repo to confirm, and the
  layer doesn't parse links from other people. No change.
  https://rustsec.org/advisories/
- Matrix Dart SDK: nothing after 17.1.0 (2026-11-23); no 16.x after 16.0.4.
  No change.
  https://github.com/famedly/matrix-dart-sdk/releases
- vodozemac / flutter_vodozemac and libcrux: nothing new. No change.
- matrix.org: no security post since February; no blog post after This
  Week in Matrix 2026-11-20. No change.
  https://matrix.org/category/security/
- FluffyChat: no new release found by web search. Commits not checked.
- GitHub advisories (pub, rust) and FluffyChat commits: still not reachable
  (the task isn't given those repos). Not checked.

### 2026-11-24

- Matrix Dart SDK 17.1.0 (2026-11-23): adds
  `Client.onDecryptedTimelineEvent` for a webhook use. A feature, not a
  security fix. No 16.x after 16.0.4. No change.
  https://github.com/famedly/matrix-dart-sdk/pull/2579
- FluffyChat 2.11.6 (on F-Droid 2026-11-23): "Bugfixes and stability
  improvements", nothing named as security. Keepr's FluffyChat audit was
  already against 2.11.6. No change.
  https://f-droid.org/en/packages/chat.fluffy.fluffychat/
- vodozemac / flutter_vodozemac: nothing new since RUSTSEC-2026-0510. No
  change.
- libcrux: nothing new; the libcrux-intrinsics aarch64 advisory
  (GHSA-2cgv-28vr-rv6j) and libcrux-psq one are older and already outside
  what Keepr uses. No change.
- RustSec: the advisory list page could not be read this run; web search
  shows only RUSTSEC-2026-0543 (chrono unmaintained, informational), which
  isn't a vulnerability. No change.
- matrix.org: no security posts since February; This Week in Matrix
  2026-11-20 already covered. No change.
  https://matrix.org/category/security/
- GitHub advisories (pub, rust) and FluffyChat commits: still not reachable
  (the task isn't given those repos). Not checked.

### 2026-11-22

- RustSec advisories 2026-11-19 to 2026-11-20 (wasmtime and wasmtime-wasi,
  heapless, lettre, sad-rsa, tokio-rate-limit, pqcrypto-mlkem,
  pqcrypto-mldsa): none for crates Keepr uses. The ML-KEM one is for
  pqcrypto-mlkem; the post-quantum layer uses libcrux-ml-kem. No change.
  https://rustsec.org/advisories/
- vodozemac / flutter_vodozemac: nothing new since RUSTSEC-2026-0510. No
  change.
- libcrux: no new advisories. No change.
- Matrix Dart SDK: no release found after 17.0.0 (16.0.4 is still the newest
  16.x). No change.
  https://github.com/famedly/matrix-dart-sdk/releases
- matrix.org: no security disclosures; This Week in Matrix 2026-11-20 has no
  server changes that break clients (MSC4388 accepted, see "For the owner").
  No change.
  https://matrix.org/blog/2026/11/20/this-week-in-matrix-2026-11-20
- GitHub advisories (pub, rust) and FluffyChat commits: could not be read
  (the task isn't given those repos). Not checked.

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
