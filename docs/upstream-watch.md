# Upstream watch

A weekly check of what Keepr stands on (see the "Level 3: On our own" table in
`docs/INDEPENDENCE.md`): the Matrix Dart SDK, vodozemac, the Matrix spec,
This Week in Matrix, Matrix security, Element X and Element Web, Synapse,
FluffyChat and Flutter. Each item gets a decision: "Act soon", "Worth
adopting" (with the INDEPENDENCE.md level it fits) or "Just so you know".
The daily security watch (`docs/security-watch.md`) covers the urgent side.

Last checked: 2026-11-23 03:30 UTC (window 2026-11-16 to 2026-11-23)

## For the owner

- Act soon: nothing this week.
- Worth adopting (Level 0): Matrix SDK 17.0.0 (recovery key check fix) is
  already done on `independent`; bring it to `vibe-next` when you're back.
  The Level 0 box for it in INDEPENDENCE.md is not ticked yet.
- Worth adopting (Level 0): Flutter 3.50.1 is the newest stable
  (2026-11-20); Keepr pins 3.47.9 in `.tool_versions.yaml`. Read the
  breaking changes before moving; not urgent.
- Level 0 in INDEPENDENCE.md is now partly outdated: the Matrix SDK 17
  step and the flutter_local_notifications 22.3.3 pin are done on
  `independent`; Flutter isn't listed there at all.
- This run could not read GitHub's API for anything outside Keepr's own
  repo (FluffyChat commits, GitHub advisories, release pages through `gh
  api`), and the matrix.org security page could not be fetched. Those were
  checked only through web search. To fix it, ask Claude in a new chat to
  add every repo this task needs (blackshadowde/Keepr, krille-chan/fluffychat,
  famedly/matrix-dart-sdk, matrix-org/vodozemac, famedly/dart-vodozemac,
  element-hq/synapse, element-hq/element-x-android,
  element-hq/element-x-ios, element-hq/element-web) and remake the task
  there. The `add_repo` tool was also not available in this run.

## 2026-11-23

Versions Keepr uses:

- `Vibe` and `vibe-next`: Flutter 3.47.9, matrix ^16.0.4,
  flutter_vodozemac ^0.9.0 (builds get 0.9.1), flutter_local_notifications
  ^22.3.0. `pubspec.lock` there is stale (builds pick versions fresh).
- `independent`: matrix ^17.0.0 and flutter_local_notifications ^22.3.3,
  both pinned in its `pubspec.lock`; Flutter 3.47.9.

Items:

- Matrix Dart SDK 17.0.0 (2026-11-18). A recovery key description missing
  its check values (MAC or IV) was taken as matching any key; now fixed.
  Breaking: `Room.states` is read-only. No newer release yet.
  Decision: Worth adopting, Level 0. Already on `independent` (f1e8c6e3a,
  ab759769d); `Vibe` and `vibe-next` are still on 16.0.4. Touches
  `pubspec.yaml`, `pubspec.lock`.
  https://github.com/famedly/matrix-dart-sdk/releases/tag/v17.0.0
- vodozemac and flutter_vodozemac: no new release or advisory found since
  RUSTSEC-2026-0510 (2026-11-12, fixed in 0.11.2 / flutter_vodozemac 0.9.1,
  which Keepr's builds already use).
  Decision: Just so you know.
  https://rustsec.org/advisories/RUSTSEC-2026-0510.html
- Matrix spec: no new version after v1.19 found. This Week in Matrix
  2026-11-20: MSC4388 (secure channel for signing in with a QR code, the last
  piece of MSC4108) and MSC4492 (pagination tokens work in both directions)
  were accepted; MSC4437 (replace the whole profile at once) and MSC4576
  (LiveKit data only with audio or video) entered final comment; new
  proposals MSC4582, MSC4583, MSC4584 (soft-ignoring people). The week
  before, MSC4581 (alt text for media) was proposed.
  Decision: Worth adopting later, Level 3: QR sign-in (MSC4108 with
  MSC4388) once the Dart SDK supports it, alongside OAuth sign-in; it would
  touch the login screens (`lib/vibe/screens/` login). Nothing else needs
  Keepr to change now.
  https://matrix.org/category/this-week-in-matrix/atom.xml
- Matrix security: no new posts found by search. The matrix.org security
  page couldn't be read this run.
  Decision: Just so you know (check again next week).
  https://matrix.org/category/security/
- Element X Android 26.11.1 (pre-release, 2026-11-17): app migrations run
  before restoring a session, also when started by a push; a workaround for
  duplicate one-time keys after login; custom timeline font size;
  multi-account work; reworked recovery setup. No security fixes or MSC4153
  changes.
  Decision: Just so you know. The duplicate one-time key issue is in their
  Rust SDK, not the Dart SDK Keepr uses.
  https://github.com/element-hq/element-x-android/releases/tag/v26.11.1
- Element X iOS and Element Web: nothing new found for the window (search
  only; iOS has multi-account behind a flag per This Week in Matrix).
  Decision: Just so you know.
- Synapse 1.166.0rc1 (2026-11-17): a release candidate; notes not read.
  1.165.0 (2026-11-10) answers media HEAD requests without reading the file
  and allows post-quantum TLS key exchange (X25519MLKEM768). No deprecation
  that clients must follow was found.
  Decision: Just so you know. Read 1.166.0's notes when it's final.
  https://releasealert.dev/github/element-hq/synapse
- FluffyChat 2.11.6 (merged 2026-11-19, PR #3995): release version bump
  only; its one code fix (removing a reaction) is already in Keepr per
  INDEPENDENCE.md. No newer release found. FluffyChat commits since
  2026-11-16 could not be read (no GitHub access to that repo), so fixes
  after 2.11.6 are not checked.
  Decision: Just so you know (not checked: commits).
  https://github.com/krille-chan/fluffychat/pull/3995
- Flutter 3.50.1 (2026-11-20, Dart 3.14.0) is the newest stable; Keepr is
  on 3.47.9 (the Matrix Dart SDK also pins 3.47.9). Seen on Shorebird's
  version page; confirm on flutter.dev before moving.
  Decision: Worth adopting, Level 0 (not listed there yet). Touches
  `.tool_versions.yaml`, `snap/snapcraft.yaml`, the workflows' Flutter
  version, and possibly code for breaking changes.
  https://docs.shorebird.dev/getting-started/flutter-version/
- Other direct dependencies (pub and Rust): GitHub advisories and OSV could
  not be queried this run; the daily security watch found nothing for
  Keepr's packages through 2026-11-22. `packages/keepr_pq/rust/Cargo.lock`
  is not in the repo, so Rust versions can't be checked.
  Decision: Just so you know.
