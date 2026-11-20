# Keepr: its own Matrix client

Keepr started from FluffyChat's code. This checklist makes it a Matrix client of
its own. FluffyChat's copyright notices and the AGPL licence stay, as the
licence requires; everything else becomes Keepr's.

## Level 0: Catch up first (checked 2026-11-20)

FluffyChat's newest is 2.11.6 (2026-11-15). Keepr has its fixes through 2.11.5
and the one code fix in 2.11.6 (removing a reaction), and is already on Matrix
SDK 16.0.4 (FluffyChat ships 16.0.1). What's left, one commit each, with
Keepr check and a test APK after each:

- [x] Matrix SDK 17.0.0 (2026-11-18, FluffyChat hasn't moved yet): fixes a
      recovery key check (a key with no check values counted as matching any
      key). Its breaking change makes `Room.states` read-only; Keepr only
      reads it (3 places), so this should be small. Test: sign in, recovery
      key, verifying a device, emotes, calls.
- [x] `pubspec.lock` is stale (says matrix 10.0.1); builds pick versions
      fresh. Refresh it from a workflow run so every build gets the same ones.
      (Keepr check prints it in its log under "Package versions".)
- [ ] flutter_local_notifications 22.3.0 → 22.3.3 first (iPhone permission
      errors, repeating notifications across daylight saving). 23 needs
      Android Gradle plugin 9.1.1 and compileSdk 37, so it goes with the
      build tools below.
- [ ] Android build tools: Gradle plugin 8.11.1 → 9.1.0, Gradle 8.14.1 → 9.3.1,
      and `proguard-android-optimize.txt` (test the release APK: the optimizer
      can break code that needs keep rules).
- Not needed: fcm_shared_isolate, light_compressor_v2, cupertino_ui (Keepr
  doesn't use them).

After Level 2 is done, FluffyChat's changes no longer apply as merges; from then
on a fix of theirs is read and written again in Keepr's code where it applies.

## Level 1: Keepr's own identity

- [x] Code package `fluffychat` → `vibe` (all `package:` imports)
- [x] Android code folder `chat.fluffy.fluffychat` → `app.keepr.chat`
- [x] App IDs and links: `im.fluffychat://` → `keepr://`, push/app IDs → Keepr's
- [x] iPhone app ID `im.fluffychat.app` → `app.keepr.chat` (iPhone users reinstall once)
- [x] Internal names (`FluffyChatApp`, `fluffy_chat_app.dart`, …) → Keepr
- [x] Old FluffyChat build scripts and leftovers removed; desktop (Linux, Windows, Mac) named Keepr; Keepr's own privacy, security, contributing and changelog pages
- [x] Settings keys `chat.fluffy.*` → `chat.keepr.*` (old ones carried over on first start)
- [x] Help links, homeserver list, website and logo now on get-keepr.github.io
- [x] Translations: every language says Keepr (FluffyChat and fluffychat.im replaced in the app's text; the text keys stay)
- [x] iPhone notification extension: app group and ID now Keepr's
- [ ] iPhone: FluffyChat's Firebase file (`GoogleService-Info.plist`) and the "FluffyChat Share" folder name (kept for now: removing them needs an iPhone build to test)

Kept on purpose (stored data and Matrix event types; renaming would log people
out or lose settings): `im.fluffychat.store.clients`, `im.fluffychat.account_config`,
`im.fluffychat.account_bundles`, `im.fluffychat.checkboxes`, the app-lock keys
and the `fluffychat_push` notification channel.

## Level 2: Keepr's own screens

Each FluffyChat screen is rewritten in `lib/vibe/`, then the old file is deleted.

- [x] All screens moved from `lib/pages` to `lib/vibe/screens`
- [x] One file per screen (controller and view merged): chat details, permissions, members, image viewer, invite, login, new group, new chat
- [x] Unused FluffyChat screens removed (old chat list parts, space view, archive list, new-space and add-account pages)

- [ ] Chat screen parts (input bar, event list, message types)
- [x] Settings pages: blocked people, password, password recovery, chat, style, notifications, devices, security, homeserver
- [ ] Custom emoji settings
- [ ] Login and sign-up
- [ ] Encryption setup and verification
- [ ] Notifications (push helper)
- [ ] Remaining FluffyChat widgets and utils
- [ ] FluffyChat leftovers from the 2026-11-20 audit (in CLAUDE.md): in-app
      icon styles, the call sounds, the iPhone share target and Firebase file

## Level 3: On our own, staying current

Once FluffyChat's code is gone, Keepr still stands on four things that keep
changing: the Matrix Dart SDK, vodozemac (the encryption), Flutter and the
Matrix spec. These are what to follow:

| What | Where | Why |
|---|---|---|
| Matrix Dart SDK | github.com/famedly/matrix-dart-sdk releases, pub.dev/packages/matrix/changelog | Keepr's Matrix engine: fixes, security, breaking changes |
| vodozemac | github.com/matrix-org/vodozemac and famedly/dart-vodozemac releases, their security advisories | the encryption itself |
| Matrix spec | spec.matrix.org changelog, matrix.org/category/spec (a release every few months; v1.19 in July 2026) | new features clients are expected to support |
| This Week in Matrix | matrix.org/blog (weekly) | what's coming, and deadlines servers and clients follow |
| Matrix security | matrix.org/category/security, GitHub advisories on matrix-org repos | fixes to bring in quickly |
| Element X and Element Web | their GitHub releases | usually first to ship new Matrix features; servers follow them |
| Synapse | github.com/element-hq/synapse releases | server changes clients must keep up with |
| FluffyChat | github.com/krille-chan/fluffychat releases | the same SDK in Flutter: many of its fixes apply to Keepr too |
| Flutter | flutter.dev stable releases | the toolkit |

How: on GitHub, Watch → Custom → Releases for those repos; and a weekly
scheduled task (alongside the daily security watch) that lists new releases
and what each means for Keepr in `docs/upstream-watch.md`.

There is no single official Matrix client: the Matrix.org Foundation publishes
the spec, and matrix.org lists featured clients (Element Web and Desktop,
Element X, FluffyChat, Cinny, Nheko). Element X, by Element (the company
started by Matrix's creators), is the one to watch for what's coming.

Spec features Keepr could take up next (check the SDK supports them first):
OAuth 2.0 sign-in (MSC3861, used by matrix.org), room history for people who
join encrypted rooms later (MSC4268, v1.19), shared custom emoji and sticker
packs (MSC2545, v1.19), one switch to block invites (MSC4380, v1.18), recent
emoji synced across devices (`m.recent_emoji`, v1.18), time zone in profiles
(MSC4175, v1.16), and not sending keys to unverified devices (MSC4153).
