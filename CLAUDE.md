# Keepr: notes for whoever picks up the work

Read this first, whether you're an AI assistant (Claude in any plan, Claude
Code, another chatbot) or a person. It holds what the owner wants, how the
code is laid out, how to build and release, and where things stand.
Keep it current: after finishing something, update "Where things stand".

## What Keepr is

- A Matrix chat app in Flutter, forked from FluffyChat and long since its own
  app. Earlier name: Vibe. Code still uses the `Vibe…` prefix (`VibeMessage`,
  `lib/vibe/…`, `vibe-*.yml`); keep it, don't rename.
- Android 10 and newer is the main target. Also an unsigned iPhone build
  (installed through AltStore) and a web build on GitHub Pages.
- Repo: `blackshadowde/Keepr` (public). Website: `get-keepr/get-keepr.github.io`.
- Branches: `Vibe` = releases, `vibe-next` = work in progress. Work on
  `vibe-next`; move `Vibe` forward only when the owner says to release.
- Bujji is the typing buddy: a small character above the text box that
  reacts, carries tools and answers `@bujji …`. Everything Bujji does is on
  the phone: no AI and nothing sent anywhere. The name is fixed.

## The owner's rules (always follow)

1. Commits are authored by the owner (`blackshadowde`) only. No
   "Co-Authored-By", no AI or tool credit lines in commits or notes.
2. Never commit or upload signing secrets or keystores
   (VIBE_SIGNING_SECRETS.txt, HYPR_SIGNING_SECRETS.txt, hypr.jks, key.jks).
   Keep TG_API_HASH secret. Don't put the owner's email in files.
3. Change only what's needed. Never rewrite a whole file; new files are fine.
   Check before and after every change that nothing else breaks.
4. No sea or sailor words in the app (for example "Offline mode", not
   "Sea mode").
5. Changelogs and release notes describe features on their own; never compare
   to other apps ("like Telegram", "Discord-style").
6. No emojis in the app's own UI: use plain Material icons. (Emojis people
   send are fine.)
7. A UI revamp gets mockups first, and they must look good; build after the
   owner approves.
8. Don't start builds unless asked. Test APKs come from `vibe-next` through
   the "Keepr build" workflow and are never published. Release only when the
   owner asks.
9. Every change gets a line in `CHANGELOG.md` under today's date heading
   (`## YYYY-MM-DD`), ending with the commit link:
   `([abc123def](https://github.com/blackshadowde/keepr/commit/abc123def))`.
10. Code comments are short, in plain words, about what the person using the
    app sees and why.
11. Android 10+ only: no workarounds for older Android.

## Where the code is

```
lib/vibe/                      Keepr's own code (most work happens here)
  vibe_message.dart            a message: one card per run, picture nested
                               beside the newest, time inside; VibeCards,
                               VibeBubblePainter, VibeTimeFlow
  screens/chat/                the chat screen
    chat.dart                  ChatController: sending, editing, pinning,
                               threads (enterThread / closeThread)
    chat_view.dart             the chat's layout and top bar
    chat_event_list.dart       the message list
    chat_app_bar_title.dart    the name pill and the threads button
    typing_indicators.dart     typing: picture + small card + dots
    chat_input_row.dart        the text box row
    send_file_dialog.dart      sending photos and files
    events/                    message content, link text, reactions, maps
  vibe_attach_sheet.dart       the + sheet: photo grid, All photos, files…
  vibe_photo_picker.dart       uses Android's own photo picker
  vibe_link_preview.dart       link previews (inside the card)
  vibe_links.dart              hold a link: Open, Copy link, Share
  vibe_message_orbit.dart      the hold-a-message menu (slide to pick)
  vibe_threads.dart            threads list, rename, close
  vibe_whats_new.dart          What's new card and the tour
  vibe_home_view.dart          home screen
  vibe_live_location.dart,
  vibe_live_map.dart, vibe_map.dart   location, live sharing, check-ins
  vibe_pq.dart                 post-quantum layer for direct chats
  buddy/                       Bujji
    vibe_buddy.dart            Bujji's look, moods, props (the painter)
    vibe_buddy_bar.dart        Bujji in the chat: reactions, wandering,
                               holding tools until a job is done
    bujji.dart                 @bujji answers (reminders, notes, settings)
    bujji_life.dart            what Bujji is doing (tools, jobs, spots)
    bujji_settings.dart        settings Bujji can open or change
    bujji_tour.dart            Bujji's What's new tour, demos, "Show me where"
lib/config/setting_keys.dart   every setting (AppSettings.…)
packages/keepr_pq/             Rust ML-KEM-768 (libcrux) with a web stand-in
docs/                          plans: post-quantum.md, nearby.md
CHANGELOG.md                   every change, by date
RELEASE_NOTES.md               the notes for the next release (rewrite per release)
altstore.json                  iPhone AltStore source (updated by the iOS release)
```

## Building, checking, releasing (GitHub Actions)

You can't run Flutter in a plain chat. The workflows do it; run them from the
repo's Actions tab (Run workflow) or with `gh workflow run`.

| Workflow | File | What it does |
|---|---|---|
| Keepr check | vibe-check.yml | analyzer (fails only on errors), tests, Rust tests. Run on `vibe-next` after every push. |
| Keepr build | vibe-build.yml | test APK from `vibe-next`; never publish it |
| Keepr release | vibe-release.yml | from `Vibe`: inputs `publish` (make the GitHub release + VirusTotal scan) and `all_platforms` (also iPhone and web) |
| Keepr iOS | vibe-ios.yml | unsigned IPA; with publish it updates `altstore.json` on `Vibe` |
| Keepr web | vibe-web.yml | web build; `deploy` puts it on GitHub Pages. Only deploy from `Vibe`. |
| Keepr for Google Play | vibe-play.yml | app bundle for Play |
| Pull back a release | vibe-unrelease.yml | removes a release by tag |

Release steps (only when the owner asks):
1. Rewrite `RELEASE_NOTES.md` for what's new since the last release (grouped,
   plain words, no comparisons, no emojis).
2. Make sure "Keepr check" passes on `vibe-next`.
3. Move `Vibe` to `vibe-next` (fast-forward), then run "Keepr release" on
   `Vibe` with publish (and all_platforms if iPhone and web should follow).
4. The version is the pubspec major.minor plus the run number (3.1.N).
5. Afterwards bring `vibe-next` up to `Vibe` (the iOS run adds an AltStore
   commit there).

## Working without tools (a plain chat)

If you can read the repo but can't edit, build or push:
- Ask for the exact file(s) you need if they aren't attached.
- Give each change as a small find-and-replace: the file path, the exact
  text to find (a few unique lines), and what to put instead. One change per
  step, so it can be pasted into the GitHub web editor (press `.` on the repo
  page) or into a short prompt for another AI tool.
- Say which CHANGELOG line to add.
- After it's committed to `vibe-next`, run "Keepr check" and read the errors
  in the analyze job; fix and repeat.
- Don't guess APIs: say when you're unsure and how to check.

## Where things stand (update this)

Last updated: 2026-11-16.

- Released: Keepr 3.1.158 (Android, iPhone, web). Bujji's What's new tour,
  Bujji holding tools until a job is done, threads button beside the name,
  close any thread, pinned bar card.
- On `vibe-next`, not released yet (needs a test APK, then a release):
  - One card per run for messages, with the picture nested beside the newest
    and the time inside.
  - Typing indicator in the same style (joins their card when they wrote
    last; several people; their own style or buddy).
  - Link previews inside the card; the link is left out of the text once the
    preview shows; hold a link for Open, Copy link, Share.
  - Photo grid without flicker, numbered picks, and an All photos tile that
    opens Android's photo picker (Google Photos too).
  - Photo stacks open the new hold menu and show their reactions.
- Open threads of work:
  - A "Could not be sent" problem the owner raised: ask the owner for details.
  - Nearby (offline chat over Bluetooth): plan in `docs/nearby.md`, decisions
    still to make before building.
  - Post-quantum: steps 1 to 3 are in the code (`packages/keepr_pq`,
    `lib/vibe/vibe_pq.dart`) even though the boxes in `docs/post-quantum.md`
    aren't ticked; step 4 (settings and wording) is next.
- Mockups live on the owner's design canvas (a private claude.ai artifact);
  ask the owner for screenshots if a design is needed.
