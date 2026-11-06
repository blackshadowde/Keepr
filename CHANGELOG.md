# Changelog

Vibe's changes are listed on each release:
https://github.com/blackshadowde/Vibe-flutter/releases

## 2026-11-06 ([ca7d315](https://github.com/blackshadowde/keepr/commit/ca7d31536))

- The app's text now says Keepr in every language. 152 translated lines in 39 languages still said FluffyChat, and invites pointed to fluffychat.im instead of get-keepr.github.io ([ca7d315](https://github.com/blackshadowde/keepr/commit/ca7d31536))

## 2026-11-05 ([a97fb90](https://github.com/blackshadowde/keepr/commit/a97fb90e4))

- Your own typing indicator now also reaches direct chats started after you set it, and chats where sharing it failed before: it's shared when you open the chat ([a97fb90](https://github.com/blackshadowde/keepr/commit/a97fb90e4))
- Animated profile pictures (GIF, WebP) now stay animated when changed from the profile sheet's Photo button too, and play in the big round picture there ([63f6d2a](https://github.com/blackshadowde/keepr/commit/63f6d2abd))

## 2026-11-03 ([3a27365](https://github.com/blackshadowde/keepr/commit/3a27365a5))

- Security update: Keepr now uses Flutter 3.47.9, which no longer trusts a set of leaked eMudhra security certificates. Before, someone holding them could have faked a secure connection on Android ([3a27365](https://github.com/blackshadowde/keepr/commit/3a27365a5))

## 2026-11-02 ([87aab93](https://github.com/blackshadowde/keepr/commit/87aab9379))

- Your own typing indicator: up to three emojis with an animation and a phrase (Settings > Customisation > Typing indicator). Other Keepr users see it while you type ([8b0a187](https://github.com/blackshadowde/keepr/commit/8b0a187fd))
- "Appearance" in Settings is now "Customisation"
- Keepr's own notification sounds: Keepr chime, Pop, Bell, Pluck, phone default or silent (Settings > Notifications, with a play button) ([e390ffc](https://github.com/blackshadowde/keepr/commit/e390ffc0c))
- If the phone stops Keepr in the background, it starts again within 15 minutes with a short "Checking for new messages" notification, so messages still arrive
- Threads: long-press a message > Create thread. It's pinned in the chat's middle pane until you close it (asks first) ([351d510](https://github.com/blackshadowde/keepr/commit/351d51001))
- Photo stacks: 4 or more photos sent together show as one grid with "+N"; tap to swipe through them
- Search in a chat: live results while typing, arrows for older and newer matches, each match highlighted in the chat
- The back button in a chat shows how many other chats are unread
- A message that can't be sent shows a notification
- Double tap can react, reply, quote part, bookmark or copy (Settings > Chats & storage)
- The highlight on a tapped reply fades after a moment
- Photos fill the screen in the viewer
- New app icon: a white chat bubble with a lock on a dark blue background. On Android the background is its own layer, so the launcher's round or rounded-square shape shows a smooth background
- The welcome screen shows the Keepr name instead of the old one
- A thread slides in when opened and slides back out when closed
- Thread screen redesigned to match the chat: same top bar, a back arrow, the thread's name with "Thread in <chat>" below it, and Rename / Close in one menu. The "Reply in thread" strip is gone
- New filled thread icon in the theme's colour (middle pane, message menu, replies button)
- Photo stacks are laid out like messages: avatar, name and time on the left, for your photos too
- Docked chat: open another chat from the top pill, or pull a chat's name down, and the chat you were in waits in a slim strip under the text box. It shows the picture and typing while they type, the newest unread message (+N for more) when there's something new, and otherwise their name. Swipe it up or tap it to go back; the back button does the same; swipe it down or tap X to close it. Settings > Customisation > "Keep the chat you leave docked"
- Fix: messages sent before the rename to Keepr, or from phones still on the old version (like the Google Play test version), are understood again. Their text stickers no longer show up in the media pane as photos, and their long messages, effects, statuses, group tags, disappearing timers, call invites and archived chats work as before. The rename had changed these internal names without reading the old ones
- Opening Keepr: the bouncing-dots opening plays first, then the chats on the home screen pop in one after another: each one springs up a little past its place and settles back, like a card dropping in. The same happens when Keepr comes back after a few minutes away. Settings > Customisation > Start-up animation
- Muted chats stay quiet: no notification, no top pill and no side picture (calls still ring). Settings > Notifications > "Pop-ups for muted chats" turns them back on
- Your name can sit in a highlighted pill, like a group tag, tinted with your name colours (Edit profile > Show my name in a pill). Older Keepr versions show the plain name
- Fix: with a chat docked, the last messages no longer hide behind the text box
- Docking and switching chats are calmer: the chat you leave lifts a touch, then sinks down into the strip at the bottom, a little smaller with rounded corners, while the next chat waits underneath (about 0.6 seconds instead of a quick flash)
- The side pictures (someone in another chat typing or writing to you, peeking in above the text box) show again; they had stopped. Tapping one now docks the chat you're in. Inside a chat they replace the top pill, so you don't get both
- After a big update, What's new opens as a small server with a channel per area (#welcome, #threads, #chatting, #make-it-yours, #notifications). Keepr types and posts each feature as a message with a live mockup of where it is and what it does; quick replies at the bottom move on, and Start chatting ends with a little party
- Matrix SDK 15.0: older encrypted messages unlock right after you enter your security key, "Verified devices only" now really shares keys with verified devices only, and group notification rules use the right member count
- Pasting images uses pasteboard 0.6
- Hot-word scenes no longer put an emoji over the animation (no ☕, 🙏, ☔, 😎, 🥶, 🎂 and so on): just the full-screen scene, plus words like HA, WOW! and Zz. The kiss keeps its lips. Hi and bye now write themselves: a handwritten "hi" or "bye" draws in one flowing gradient stroke with a glowing pen tip; "hi" floats up and fades, "bye" lifts away in tiny sparks
- New hot words: rain, thunder or storm darkens the screen with rain and lightning; sunny, summer, yenda or full hot brings a blazing sun and heat waves; winter, chali, so cold or cool weather brings frost and snowflakes
- Threads can be renamed: tap the thread's name at the top, Rename in the thread menu, or the pencil (or long-press) in the middle pane. Without a name, a thread is named after its first message
- Photo stacks: the date line goes by the first photo, and long-press on a photo opens its menu (react, reply, delete)
- Downloaded builds are named Keepr (keepr-apk, keepr-play, keepr-ios-unsigned)
- Voice messages recorded on Android now play on every phone (the file is repackaged; the sound is unchanged). From FluffyChat 31f7fff
- "Seen by" still shows when the last thing in a chat is a hidden event. From FluffyChat c1477f7
- A chat's notification goes away as soon as you read it, here or on another device. From FluffyChat ceb1331
- Animated profile pictures play in your profile, chat details and the profile popup, and stay animated when picked from the gallery. From FluffyChat c1f0de1

## 2026-11-01

### Changed
- Vibe is now called **Keepr**. Updates, settings, links and backups keep working ([0549bc6](https://github.com/blackshadowde/Vibe-flutter/commit/0549bc679))

## 2026-10-30

### Security and privacy ([a4ec5c0](https://github.com/blackshadowde/Vibe-flutter/commit/a4ec5c05c))
- In-app updates (GitHub version) are checked before installing: the exact APK, its SHA-256 from the release notes, and the same signing key as the installed Vibe
- No Firebase anywhere in the build scripts
- Privacy policy: who is responsible, legal basis, how long data is kept, your rights, data outside your country, minimum age 16
- Google Play version: no in-app updater; Google Play does the updating

## 2026-10-29

### Added
- Swipe a text message and keep holding: the arrow turns into a quote mark, release to quote just part of it ([792ff7b](https://github.com/blackshadowde/Vibe-flutter/commit/792ff7b3b))
- Quote part of a message: long-press a text message, tap Quote part, pick the words and answer just those (shown as a quote in every Matrix app). New features get a short "New" highlight the first few times ([9953651](https://github.com/blackshadowde/Vibe-flutter/commit/995365198))

### Changed
- Thread pane is now a tree: a line down the side, answers to an older message indented under it, no repeated reply line ([534aac3](https://github.com/blackshadowde/Vibe-flutter/commit/534aac3ae))
- Settings > Chats & storage: switch to turn off the text stickers shown above the text box while typing ([534aac3](https://github.com/blackshadowde/Vibe-flutter/commit/534aac3ae))
- Thread pane stays open after you send: your reply rises from the text box into the thread with the chat's status dots (encrypting, sent, delivered, read), and new replies appear live ([d0d4acf](https://github.com/blackshadowde/Vibe-flutter/commit/d0d4acf86))

### Fixed
- Quote part: the reply line shows the quoted words, and picking words is easier (tap the first and last word or slide across) ([a112210](https://github.com/blackshadowde/Vibe-flutter/commit/a11221018))
- Media, links, files and voice messages in a chat's details open instantly: what's already on the phone shows first, older items load after ([a972b2c](https://github.com/blackshadowde/Vibe-flutter/commit/a972b2c29))
- Server rail: with many chats, the + for a new chat or group was stuck under the profile bar. It now scrolls above it ([741b415](https://github.com/blackshadowde/Vibe-flutter/commit/741b415da))
- Dropping a photo or video from another app on Android failed with "Cannot open file". A desktop drag-and-drop library caught the drop before Vibe's own handler; it's now switched off on Android ([3c67951](https://github.com/blackshadowde/Vibe-flutter/commit/3c67951e6))

### Google Play policies ([fc55515](https://github.com/blackshadowde/Vibe-flutter/commit/fc55515e2))
- Long-press a message from someone else: **Report** sends it to your server's admins
- Sign-in screen: "By continuing you agree to the Terms", with new [terms of use](https://get-vibe.github.io/terms.html) (rules, report and block, child safety)
- Google Play build: no photo-library permission. Sending photos uses the system photo picker; saving to the gallery needs no permission
- Storage permissions only on the old Android versions that use them (read: Android 12 and below, write: Android 10)
- Google Play version is its own app, `app.vibe.chat`, because `com.vibe.app` is taken on Play by another developer. The GitHub version keeps `com.vibe.app`, so nothing changes for existing installs ([68db71c](https://github.com/blackshadowde/Vibe-flutter/commit/68db71cde))
- Play listing name "Vibe – Secure Chat": "Matrix" is the Matrix.org Foundation's trademark, so the listing only says Vibe works with the Matrix protocol

## 2026-10-28

Every change in this release, with the commit that made it.

### Fixed
- Play Protect blocked installing Vibe. Google blocks any downloaded app that declares a notification listener; Vibe used one only for "Listening to". The listener is removed and the feature is off for now ([4519d56](https://github.com/blackshadowde/Vibe-flutter/commit/4519d56e3))
- Android back gesture closed the app instead of the open pane: Android's predictive back is turned off for Vibe ([e3ecdb9](https://github.com/blackshadowde/Vibe-flutter/commit/e3ecdb976))
- Dropped files: the send popup didn't send. They now wait above the text box, upload while Vibe is kept running, retry once, and show the real error if they fail ([e3ecdb9](https://github.com/blackshadowde/Vibe-flutter/commit/e3ecdb976), [9f1bd4c](https://github.com/blackshadowde/Vibe-flutter/commit/9f1bd4c43))
- Device verification: the device list looked tappable but wasn't. The text now says to accept the request on another device, with a Send again button ([e3ecdb9](https://github.com/blackshadowde/Vibe-flutter/commit/e3ecdb976))
- iPhone notification extension used FluffyChat's app group and ID, so it couldn't read Vibe's data ([2c779e9](https://github.com/blackshadowde/Vibe-flutter/commit/2c779e9e3))

### Security (fixes taken from FluffyChat after checking its 768 newer commits) ([625b562](https://github.com/blackshadowde/Vibe-flutter/commit/625b56236))
- Pictures load only from `mxc://` (your Matrix server) and only when signed in, so a message can't make Vibe fetch an outside address
- The recovery key's copy button copies; it no longer opens the share sheet on phones
- Resetting your encryption key really resets it, and moves your old message keys into the new backup
- Notifications arriving while signed out are ignored
- iPhone notifications close the database when done, so it can't stay locked

### Added
- Reply window for conversations of replies, with photo, video and file replies ([9f1bd4c](https://github.com/blackshadowde/Vibe-flutter/commit/9f1bd4c43), [2694875](https://github.com/blackshadowde/Vibe-flutter/commit/269487539))
- Block and unblock from someone's profile ([e3ecdb9](https://github.com/blackshadowde/Vibe-flutter/commit/e3ecdb976))
- Password and email link to the server's account page when it has one ([e3ecdb9](https://github.com/blackshadowde/Vibe-flutter/commit/e3ecdb976))
- Member search; permissions as Everyone / Moderators / Admins; admins can delete groups and communities (everyone removed, joining closed, then left and forgotten) ([c8bc320](https://github.com/blackshadowde/Vibe-flutter/commit/c8bc320b5))
- Share link and QR code for your ID (`get-vibe.github.io/chat.html#@you:server`); mentions shown as pills while typing; role tags and a pickable group tag in groups. The group tag is stored in your own member event in each group (`chat.vibe.tag`), and that update is hidden from the chat ([818c7f0](https://github.com/blackshadowde/Vibe-flutter/commit/818c7f0e4))
- Web: larger layout in wide windows, Vibe name and colours ([2694875](https://github.com/blackshadowde/Vibe-flutter/commit/269487539)); optional "Log out when the browser closes" ([4bf8158](https://github.com/blackshadowde/Vibe-flutter/commit/4bf8158ec))
- Help page and Vibe's own homeserver list on get-vibe.github.io ([2c779e9](https://github.com/blackshadowde/Vibe-flutter/commit/2c779e9e3))

### Changed
- Settings are saved under `chat.vibe.*` instead of `chat.fluffy.*`; old settings are carried over on first start ([2c779e9](https://github.com/blackshadowde/Vibe-flutter/commit/2c779e9e3))
- All screens moved from `lib/pages` to `lib/vibe/screens`, and 8 screens merged into one file each. Code layout only, no visible change ([3950286](https://github.com/blackshadowde/Vibe-flutter/commit/3950286d1), [0f838ca](https://github.com/blackshadowde/Vibe-flutter/commit/0f838ca20))
- Releasing: one run builds Android and starts the iPhone build with the same version number, and updates the web app when publishing ([636ab77](https://github.com/blackshadowde/Vibe-flutter/commit/636ab77fc))

### Removed (for now)
- "Listening to" status (see the Play Protect fix above)

### Security audit (after 3.1.111) ([a160dcb](https://github.com/blackshadowde/Vibe-flutter/commit/a160dcbc0))
- Call links are opened only when they point to a call server (`call.element.io` or your own). Before, a fake call message could open any website inside Vibe with the camera and microphone allowed
- Link previews are off in encrypted chats (your server would see the link); a switch turns them back on
- Firebase is no longer built into Android releases (3.1.111 and earlier included it, unused, and it contacted Google at start)
- The app ID stays `com.vibe.app`, the ID every release has used
- Unused permissions removed: screen capture and full-screen alerts
- PRIVACY.md lists every server Vibe contacts and what each one sees

### Reply threads
- A message with two or more replies opens the whole thread in a pane over the blurred chat, with the chat's own bubbles and text box; swipe a message in the pane to answer that one instead
- Releases list the APK's SHA-256 and, when the VT_API_KEY secret is set, a VirusTotal report

Vibe started from FluffyChat's code. FluffyChat's own history:
https://github.com/krille-chan/fluffychat/blob/main/CHANGELOG.md
