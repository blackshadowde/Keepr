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

Last updated: 2026-11-20.

- Released: Keepr 3.1.165 (2026-11-20, Android only; the Play app bundle
  `keepr-play-3.1.165` was built from `Vibe` for the owner to upload).
  iPhone and web are still on 3.1.158. Before that, 3.1.161 had:
  - One card per run for messages, with the picture nested beside the newest
    and the time inside.
  - Typing indicator in the same style (joins their card when they wrote
    last; several people; their own style or buddy).
  - Link previews inside the card; the link is left out of the text once the
    preview shows; hold a link for Open, Copy link, Share.
  - Photo grid without flicker, numbered picks, and an All photos tile that
    opens Android's photo picker (Google Photos too).
  - Photo stacks open the new hold menu and show their reactions.
  - Jump to present: a small round button above the send button.
  - Swipe down on panes follows the finger and springs with its speed
    (`vibe_sheet_drag.dart`).
  - The samurai (deleting a message) has a jointed body and eased timing,
    about 3.4 s, and never looks back (`vibe_samurai.dart`, played by
    `VibeSlashRow` in `vibe_slash.dart`; the message card is marked with
    `VibeSlashBubble`). The owner's motion study is a private artifact.
  - Quiet home (replaced in 3.1.165 by the big title and filters).
  - One profile page: picture and name both open `VibeSetStatusPage` (photo,
    name, style, pill, ID copy, status, Keepr ID code with Share and Copy,
    group tag, settings). `VibeOwnProfile.show` points there.
  - Connections (`vibe_connections.dart`): on the profile page, connect
    Last.fm or ListenBrainz with a username; the phone asks every 30 s while
    Keepr runs and shares the song through the status `activity` (`'by':
    'connection'`, `card` / `pill` switches). The card is
    `VibeListeningCard`; the line by the name shows headphones. Spotify
    can't be connected directly (since February 2026 its developer access
    allows 5 users with Premium), but it can feed either service. Last.fm
    uses the `LASTFM_API_KEY` repository secret (set; the workflows pass it
    with `--dart-define`); without it Last.fm shows as not in this version
    and ListenBrainz still works. Bujji listens along (`_onMusic` in
    `vibe_buddy_bar.dart`): headphones, dancing, hops to messages; a sad
    song (Last.fm tags or sad words in the title) makes it sad with a tear.
    The old notification listener stays off.
  - Bujji: smooth `groove` to music (no shaking), hides behind a message
    after too many pokes until petted a few times (`_hideAway`,
    `_petHidden`); no fade behind its row (stops in `chat_view.dart`).
  - Replies: the line runs down the card's edge to the picture
    (`_ReplyRail` in `vibe_message.dart`).
  - Voice notes: the recorder pane (`recording_input_row.dart`) and voice
    cards (`events/audio_player.dart`) as in the mockups.
- New in 3.1.165:
  - Home: three dots (your profile, `tour.profile`), search, a filled +; a
    big "Chats" that folds into the bar as the list scrolls (`_BigTop`,
    `_homeLift`); filters All / Unread / Groups / Direct / Spaces
    (`_Filters`, `VibeHomeFilter` in `vibe_dm_pane.dart`); chats fade under
    the filters. Bujji no longer sits on the title.
  - Replies: the message being replied to gets
    a soft inset wash in the theme colour (`_SoftWash`); the swipe bubble
    uses the theme's soft colour (`vibe_swipe_reply.dart`).
  - Voice notes: Stop leads to
    listening back (play, drag to jump), then Delete, Retake or Send
    (`stopToReview`, `playReview`, `seekReview`, `recordAgain` in
    `recording_view_model.dart`).
  - Notifications settings: rules made for one chat (`!…`) or one person
    (`@…`) show by name in their own section, "Chats and people with their
    own setting", with what they do in plain words.
  - Settings in the owner's pick, "Soft tiles" (design canvas): big title
    that moves into the bar (`VibeTitledPage`), your card, Search settings
    (`vibe_settings_search.dart`, over `BujjiSettings.all`), rows with icons
    in grey tiles (`VibeSettingsRow`, `VibeIconTile`), cards radius 24 with
    no lines, small capital labels, switches whose dot grows. All in
    `vibe_settings_style.dart`, so every settings page follows; `VibeGroups`
    puts plain row icons in tiles. Notifications uses `VibeTitledPage` with
    plain-named rules (Direct chats, Groups, mentions, Calls) and All rules.
  - Bujji reminders: "after 2 mins", a bare "2 mins" and similar; when it
    can't read the time it keeps the task and asks again (`_when` and the
    pending answer in `bujji.dart`).
  - Themes (the owner's pick from the canvas): Customisation has Light /
    Dark / Auto (`VibeModeSwitch`), a row of theme cards (`VibeThemePicker`,
    mini chats) with Material You, Keepr and all of mpvRx's palettes
    (`vibe_theme_set.dart`; Ocean, Tidal and Cloudflare renamed Cyan, Teal
    and Tangerine; "Default" is Mauve), Pure black (`VibeThemeSet.black`),
    Your own theme from one colour (`VibeThemeEditor`, kept in
    `chat.keepr.custom_themes`). A change grows from the tap
    (`VibeThemeReveal` round the app in `vibe_app.dart`). The pick lives in
    `ThemeController.theme` ('keepr', 'material', a palette id or
    'custom:…'); `VibeLook.palette` + `VibePalette.set`. Glass is no longer
    offered (old Glass users get Keepr); its code is still there, unused.
    Chat wallpaper is the account wallpaper (plain). Their messages: each
    person's own colour by default (`VibeCardColours`,
    `AppSettings.vibeTheirColour`: own / theme / plain).
- On `vibe-next`, not released yet (2026-11-20, "Keepr check" passes):
  - Status clear-time chips side by side again (`vibe_set_status.dart`:
    the chip's `Container` had `alignment`, which made it full width).
  - Square crop for your picture, a chat's and a group's
    (`vibe_photo_crop.dart` on `crop_image`, aspect 1, round guide; GIF and
    animated WebP skip it). Called from `VibeOwnProfile.changePhoto`,
    `VibeGroups` and `chat_details.dart`.
  - Waiting messages: `AppSettings.sendTimelineEventTimeout` is 2 days
    (was 15 s), so the SDK keeps retrying network failures and still fails
    server refusals at once. `VibePatientHttp` (`vibe_send_retry.dart`,
    wraps the client's HTTP in `client_manager.dart`) backs off send-type
    requests while offline (2 s up to 60 s) and lets them go on the first
    success; `VibeSendRetry.watch` resends what was still "sending" in the
    database after the first sync. The UI already says "Waiting for
    connection".
  - Bujji brings reactions you'd miss (`bujji_gifts.dart`,
    `bujji_gift_float.dart`, `_giftFrom` / `_onGifts` / `_deliver` /
    `_pile` in `vibe_buddy_bar.dart`; props `gift`, `basket`, `phew` and
    `VibeBuddyFace.held` in `vibe_buddy.dart`): others' reactions on your
    messages that aren't on screen. 1 to 3: held up, slow hop, tap goes to
    the message (Bujji hops onto it). 4+: basket, tipped out as a pile above
    the box, tired phew. Bujji off (or pace off): a bubble above send, over
    the jump button when it shows. Scrolling to the message or the reaction
    being removed clears it.
  - Select text (`vibe_quote.dart`, the old Quote part sheet: Copy and
    Quote, numbers as chips; the orbit's Quote is now Select) and tappable
    numbers in messages (`vibe_numbers.dart`, used by `VibeLinks.span`:
    5+ digit codes copy, phone numbers get Call / Copy).
  - Own profile page plays an animated picture (`animated: true`).
  - The bar's background is painted by `_InputBack` in `chat_view.dart`
    from the text box down (`controller.inputRowKey`), not as a fraction of
    the whole bar.
  - Old name Vibe replaced by Keepr in the iPhone share extension's display
    name and desktop window titles.
  - Replies as Echo (the owner's pick from the canvas): `replyStrip` in
    `vibe_message.dart` draws the answered message as a smaller card in its
    person's colour peeking out above the card (26 px show, the card covers
    the rest; it reports its width to the card via `_ReportWidth` so the card
    covers it). `_ReplyCurve` and `_ReplyRail` are gone.
  - Wallpapers (the owner's pick): `vibe_wallpaper.dart` paints Doodles,
    Flow, Shapes, Waves and Dots from the `ColorScheme`
    (`VibeWallpaperPaint`, doodles from SVG path data); `VibeWallpaperPage`
    (Customisation > Chat wallpaper) with tiles, Pattern
    (`AppSettings.vibeWallpaperPattern`) and, for your photo, Dim (the
    account's `wallpaperOpacity`) and Remove. The pick is
    `AppSettings.vibeWallpaper` ('photo' by default, 'none', or a style).
    Your photo gets blur 3 when none is set and a 14% theme tint.
    `VibeWallpaper.on` replaces the old `wallpaperUrl != null` checks.
  - Unpin in the hold menu: the pin with a slash (`_OffIcon`).
  - Hot word "sorry" writes itself like hi and bye (`_sorryPath`, from the
    Hershey script lettering, with its credit). The owner wants only sorry
    changed; the other scenes stay.
- Waiting for the owner:
  - Pane extras from the study (dim follows the pull, the page behind steps
    back): they reach into Flutter's own pane code, so try them with a test
    APK. Questions in Keepr already open as panes (`showVibeDialog`), so the
    "popup grows from the button" idea fits menus rather than questions.
- Open threads of work:
  - Google Play: the owner applied for production access (2026-11-20). The
    Play listing still shows the old mockups from before the redesign (the
    README images were given to him as a stopgap); new store screenshots are
    to be made. 3.1.165 (code 165) is uploaded to "Closed testing - Alpha"
    and sent for review with new screenshots, feature graphic and two
    declarations. Foreground services: camera, microphone, phone call (calls),
    location (live location), remote messaging entered as "Other" (Direct
    connection / built-in notifications keep a connection open), with videos.
    Full-screen intent: "Making and receiving calls", pre-granted Yes. Most of
    these come from flutter_callkit_incoming's own manifest. If Google rejects
    remote messaging, the Play build needs another way to keep that
    connection. Keepr doesn't ask for full-screen intent itself
    (`canUseFullScreenIntent`), so without approval calls show as a floating
    notification on Android 14+. Play bundles come from "Keepr for Google
    Play" (`vibe-play.yml`).
  - "Could not be sent": the owner's report was messages failing quickly
    offline; the two-day waiting change above is the fix (not released).
  - Nearby (offline chat over Bluetooth): plan in `docs/nearby.md`, decisions
    still to make before building.
  - FluffyChat leftovers (audit 2026-11-20 against FluffyChat 2.11.6):
    app, launcher, notification, splash and web icons are Keepr's. Left:
    icons inside the app are mixed (about 370 outlined and 320 plain, which
    is FluffyChat's style, against 270 rounded in Keepr's own screens);
    screens still mostly FluffyChat's layout: chat search, call page,
    stickers and emotes settings, encryption and access settings, backup
    setup (bootstrap), lock screen, event info, the adaptive dialogs and
    the photo editor in `send_file_dialog.dart`; the four call sounds in
    `assets/sounds/call_*.mp3` are FluffyChat's files; the iPhone share
    extension is still the "FluffyChat Share" target and
    `ios/Runner/GoogleService-Info.plist` is FluffyChat's Firebase project;
    `assets/logo/mini/logo_font_mini.png` says Vibe (unused); macOS
    PRODUCT_NAME is Vibe. Keep: the AGPL credit (About page, SPDX lines)
    and the `im.fluffychat.*` / `chat.fluffy.*` storage and account data
    keys and the `fluffychat_push` channel id (renaming them would lose
    people's settings and data).
  - Post-quantum: steps 1 to 3 are in the code (`packages/keepr_pq`,
    `lib/vibe/vibe_pq.dart`) even though the boxes in `docs/post-quantum.md`
    aren't ticked; step 4 (settings and wording) is next.
- While the owner is away (until about 2026-12-16), a daily scheduled task
  watches for critical or high security fixes (Matrix SDK, vodozemac,
  FluffyChat, packages Keepr uses). It fixes them on a `hotfix/…` branch made
  from `Vibe`, releases the Android APK only, merges `Vibe` back into
  `vibe-next`, and logs everything, including lower ones left for the owner,
  in `docs/security-watch.md`.
- Mockups live on the owner's design canvas (a private claude.ai artifact);
  ask the owner for screenshots if a design is needed.
