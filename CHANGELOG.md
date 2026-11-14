# Changelog

Vibe's changes are listed on each release:
https://github.com/blackshadowde/Vibe-flutter/releases

## 2026-11-15

- Typing buddy: a small soft blob in your theme colour (named Mochi until you rename it) sits on the right just above the text box. It breathes, blinks and dozes off when the chat is quiet; while you type its eyes follow along and its face changes with your words (happy, heart eyes, puzzled, sleepy, worried when you delete a lot). Send and it hops. It covers its eyes and asks before sending something that looks like a password or card number; says when you're writing to someone you haven't written to in a month; offers a fitting effect ("Send with Love?", not in post-quantum chats); holds a shield in post-quantum chats and frets about an unverified device; waves your draft at you when you come back; waves when they come online or start typing; and throws a small party for 3, 7, 14, 30, 60, 100 and 365 days in a row. Tap it to make it giggle, double tap to tickle it, hold it for Send later, Remind me to reply (30 minutes, 1 hour, 3 hours, tomorrow morning) and its settings. Outfits unlock as you send (bow at 25, cap 100, glasses 250, headphones 500, crown 1000). In direct chats, other Keepr users see your buddy in your typing circle (can be turned off). Settings > Style > Typing buddy: on or off, name, others see it, outfits. Everything it notices stays on the phone ([2c36db671](https://github.com/blackshadowde/keepr/commit/2c36db671))
- Message menu: hold a message and it lifts while the chat blurs; its actions float round the message's end as small glass buttons on a thin dotted arc (opening away from the screen edge), flying out one after another. Keep your finger down and slide: a light trail follows it, the button under it grows into the theme colour with its name above it, with a light tick for each; let go to pick, or lift and tap. Quick reactions sit on a closer inner arc (hold one for all emoji). Theirs: Reply, Quote, Copy, Forward, Thread, Pin, Star; yours: Reply, Edit, Copy, Forward, Pin, Delete; More opens the full list (Info, Report, Hide on this device). Photo stacks keep the list ([b1f781036](https://github.com/blackshadowde/keepr/commit/b1f781036))
- Post-quantum direct chats: when every device of both people runs Keepr with a checked post-quantum key, text messages (and their edits and replies) get an extra layer inside the normal encryption. A chat key is wrapped for each device with ML-KEM-768 and sent once; each message is sealed with AES-256-GCM, tied to the chat, the sender and that key; a new chat key every 100 messages or when the devices change. A small lock appears next to the name in the chat header. If any device uses another app, messages go out as before, so nobody gets something they can't read. Replies to a post-quantum message never copy its words outside the layer. Not covered yet: photos and files, effects (they wait in these chats), groups, and reading old post-quantum messages on a newly added device ([751f9fcf2](https://github.com/blackshadowde/keepr/commit/751f9fcf2))
- Post-quantum (groundwork): ML-KEM-768 (FIPS 203) from libcrux, the formally verified implementation Signal uses, built into the app for phones. Each device makes its own post-quantum key pair once, keeps it in secure storage, and shares the public key in direct chats signed with its device key; other Keepr apps only accept keys whose signature checks out. Settings > Encryption > Technical details shows "Post-quantum key: ML-KEM-768 · working" after a live check on the phone. Messages don't use it yet ([12c3f067d](https://github.com/blackshadowde/keepr/commit/12c3f067d))
- Home: the top is your picture, name and status (Online in green) with round Search and Settings buttons; under it Chats and Spaces side by side as pills with their unread counts, and a round + at the end. Hold Chats for locked chats. Pinned chats show as pictures under that row when you have any ([d601d9fd0](https://github.com/blackshadowde/keepr/commit/d601d9fd0))
- Chat bubbles: back to the picture sitting in the curve of the last bubble, and now every bubble of a run reaches the same edge, so the run lines up ([d601d9fd0](https://github.com/blackshadowde/keepr/commit/d601d9fd0))
- Typing indicators: when someone sets a new one in a chat with you, you get a notification showing it (asking you to set yours if you haven't); opening the chat offers Set yours once ([d601d9fd0](https://github.com/blackshadowde/keepr/commit/d601d9fd0))
- Attach menu: each action is a bright round tile with a white rounded icon (Photos, Contacts, Files, Poll, Location) ([d601d9fd0](https://github.com/blackshadowde/keepr/commit/d601d9fd0))

## 2026-11-14

- Chat bubbles: the sender's picture sits at the bottom of a run and the last bubble's bottom corner flows into it with a soft inward curve; the bubbles above line up with it, so the run reads as one shape. A new message no longer slides in: the row opens up and the bubble stretches out of the picture (wide, then tall, a little overshoot) ([7280b32d0](https://github.com/blackshadowde/keepr/commit/7280b32d0))
- View once: hold Send and pick View once for a text, or switch on View once when sending a photo, video or file. The other person sees a pill ("Photo · tap to view once"); it opens full screen one time (photos can be zoomed but not saved from there), and when they close it, it breaks into dust that drifts away. Their app then tells yours, and yours deletes it for everyone. Previews and notifications only say "View once message" ([7280b32d0](https://github.com/blackshadowde/keepr/commit/7280b32d0))
- Location: Share live location for 15 minutes, 1 hour, 8 hours or until a time you pick. The card shows a live dot, "Until 10:30 PM · updated 2 min ago" and Stop for you; it keeps moving while the app is in the background (with an ongoing notification) and says when it ended. Check in: "when I get to the pin" (checks in by itself when you're within 150 m) or after a timer; you get End and +30 min on the card. When the time is up the app asks if you're OK; with no answer in 10 minutes the card says Missed check-in and the chat gets your live location for an hour. Tapping any location opens a full-screen map you can move, zoom and turn, which follows live updates, with Open in maps ([7280b32d0](https://github.com/blackshadowde/keepr/commit/7280b32d0))

- Home: unread chats are cards at the top of the list, in the phone's colour theme: who, when and how many, the newest message in a bubble (or that they're typing), a box to answer right there and Open. With more than 5 unread chats the cards fold to one line each, with a round arrow that opens a card. The rest is a flat list under "All chats" (no pill behind every row). Previews start with "You:" for your own messages and show the answer, not the quoted words, for a reply to part of a message. Only people who are online get a dot. The top row holds pinned chats only, since unread ones are the cards ([857b2de7b](https://github.com/blackshadowde/keepr/commit/857b2de7b))

- Chat bubbles: the last bubble of a run curves in round the sender's small round picture (theirs on the left, yours mirrored on the right); the others line up with it, corners tighter where they stack. Solid colours with no borders: yours take the phone's colour theme when it has one, theirs are neutral. Sending status is a small word inside your bubble (Encrypting, Sent, Delivered) that changes in place and goes once it's seen. In groups the name sits inside the first bubble; the time shows once under a run. A reply to part of a message shows the quoted words on the reply line only, not again inside the bubble. Typing dots sit in a circle the size of the picture ([51000a55e](https://github.com/blackshadowde/keepr/commit/51000a55e))
- Location: a shared place is a card with a still map (dark in dark mode), a pin in the theme colour, the coordinates and a tap to open it in maps. Sharing is a full-screen map: send where you are (with its accuracy), or move the map and send the place under the pin; a button brings the map back to you ([51000a55e](https://github.com/blackshadowde/keepr/commit/51000a55e))

- Chat: ⋯ in the chat bar now opens the person or group page with the chat's settings on it (Search, Mute, Chat wallpaper on glass, Encryption, Disappearing messages, Scheduled messages, Leave) instead of a separate menu. Photo stacks: swipe the top photo left or right to flip through them (with a 2/5 counter); tap opens the one on top. Swiping on a stack no longer closes the chat ([9f5997c](https://github.com/blackshadowde/keepr/commit/9f5997c))

- Chat: text messages sit in rounded bubbles (yours tinted with the theme colour) beside a small round picture; photos, stickers, big emoji and cards stay as they were. While someone types, the dots sit inside a round bubble, and a new message swells out of that corner like a drop pulling free (wide first, then tall, a little overshoot) before settling to its shape, instead of sliding in. The line that ran down each person's run is gone ([93997a1](https://github.com/blackshadowde/keepr/commit/93997a1))

- Strict encryption: every single message now gets a fresh key, in direct chats and groups alike (it was every 3 messages or 5 minutes in direct chats, every 10 messages or an hour in groups). Strict chats move over the next time you open them, if you're allowed to change the chat's settings. Each new key is shared with everyone's devices, so big groups do a little more work per message. The website and FAQ say the same now ([8416709](https://github.com/blackshadowde/keepr/commit/8416709))
- Polls: a Poll button in the attach menu. The poll is a card in the chat: the question, each answer as a rounded row that fills with its share of votes (with the faces of who picked it and the percentage), radio buttons or checkboxes when more than one answer is allowed, and End poll for whoever started it. Making one is a matching sheet: the question, numbered answers, add / remove answers, whether answers show before the end, and more than one answer ([8416709](https://github.com/blackshadowde/keepr/commit/8416709))
- Home: the Chats / Spaces tile shows how many chats are unread; opened, each side shows its own count ([8416709](https://github.com/blackshadowde/keepr/commit/8416709))

- Home: pinned chats now show only in the row at the top, no longer also in a Pinned section of the list (they still turn up when you search) ([a8e5a4f](https://github.com/blackshadowde/keepr/commit/a8e5a4f))

- Chat bar: the pill shows the connection status again under the name (•-•-• with a running light while connecting, green once connected), then their local time in direct chats. The back arrow sits on a round backdrop like the pill. Home: the row at the top shows only pinned chats and chats with unread messages, each once (it also showed chats you'd written in last) ([d00788d](https://github.com/blackshadowde/keepr/commit/d00788d))

- Video calls: your own preview is mirrored again, like looking in a mirror, so moving your right hand moves the picture on the right. What the other person sees was never flipped and still isn't ([0edd8cc](https://github.com/blackshadowde/keepr/commit/0edd8cc))

## 2026-11-07 ([a7d176a](https://github.com/blackshadowde/keepr/commit/a7d176a))

- Brought back from the rollback, on its own: switching Chats / Spaces, and opening or closing a person or community pane, move the rows as blocks (the old rows slide away, then the new ones come in). Opening a chat is unchanged (it slides in as before) ([f9efdd4](https://github.com/blackshadowde/keepr/commit/f9efdd4))

- Rolled back to how Keepr was right after "every chat its own pill" (9062de0): the block motion, strip reveal, row haptics, the Dial look and its fixes, and the later small fixes made along with them (follow new messages, search close) are all taken out. Every file except this changelog is exactly as it was then; the entries below stay as a record ([1f3adc8](https://github.com/blackshadowde/keepr/commit/1f3adc8))

- Chat: a new message now brings the chat down to it when you're at or near the newest messages, and always when it's one you sent; it used to stay where it was ([f18c303](https://github.com/blackshadowde/keepr/commit/f18c303))

- Dial fixes: tapping the quoted line over a reply jumps to the message it answers. The dial now steps aside whenever the message box has the keyboard (it could stay before). The person page lists open threads; tap one to open it. Long-press now opens two curved bands right where your finger is: the big one with Reply, Thread, Quote, Edit, Forward, Copy, Save and Info, the small one inside with quick reactions, more emoji and Delete or Report; they sweep open and the buttons turn into place along them ([8543160](https://github.com/blackshadowde/keepr/commit/8543160))

- Dial: the dial steps aside while the keyboard is up, so the chat keeps its room. Switching chats on the dial now turns: the chat you're in swings away round a point below the screen and the next one swings in from the side you turned to. Opening a chat from all chats turns the same way (all chats swing out as the chat swings in, and back). Long-press a message for a ring of actions round it: the message in a disc in the middle, Reply, Thread, Quote, Edit, Forward, Copy, Save, Info, Delete or Report turning into place round it, and quick reactions above ([270144d](https://github.com/blackshadowde/keepr/commit/270144d))

- Dial A–Z: hold the dial and letters run round the arc; slide to a letter (a tick per letter) and let go. The dial then holds everyone of that kind from that letter on, A to Z (not just your recent chats); turn or tap to open someone. The lime "A–Z · M ✕" chip on top goes back to your recent chats ([9e0c0a9](https://github.com/blackshadowde/keepr/commit/9e0c0a9))

- Dial: your message's dot on the middle line now shows its state: it glows while being encrypted, pulses while it goes out, turns blue once sent, green once delivered and red if it couldn't be sent. The dots after the text are gone in Dial. The person or group page is now the tree from the mockup: the middle line runs on and Conversation, Shared, Members (groups), About and Actions hang off it left and right. The dial holds pinned chats and your 15 most recent (everyone else is in the rings, list or search), and a flick spins it on a few people ([b8d30b9](https://github.com/blackshadowde/keepr/commit/b8d30b9))

- Dial fixes: dragging the dial no longer swipes the chat closed. The dial now turns smoothly and settles on a soft spring before opening who's in the middle, with a quick dark wipe between chats. Names no longer overlap the pictures on the dial (the open chat's name is in the bar on top); pictures grow as they reach the middle. The dial only holds chats of the same kind: people with people, groups and channels with groups. A reply's curve now runs up the line and turns into the quoted words instead of wandering off. The rings swing into place each time you open all chats or switch Chats / Spaces, keep showing (with a List button for everyone), and search opens from a button with a ✕ to close. Tap the picture in the middle of the dial, or the name in the top bar, for the person or group page (slides in from the left, swipe right to close). Home search (both looks) now closes with ✕ or by tapping away with nothing typed ([29edf69](https://github.com/blackshadowde/keepr/commit/29edf69))

- Dial (experimental look, Settings > Customisation > Dial): switch it on and Keepr restarts into a new layout. There's no home screen: it opens on the chat you were in last. A chat runs down one line in the middle, their messages to the left and yours to the right in lime, a dot on the line for each message (in groups, the sender's initial at the start of their run). A reply shows the quoted words in small type above it with a little curve up from its dot. Under the message box is a dial of the people you talk to: drag it sideways to turn it (a tick per person) and let go to open who's in the middle, tap someone to open them, swipe up for all chats. All chats sit on two rings (pinned and unread inside, everyone else outside, or a list when there are many), with Chats / Spaces in the middle, search on top and Archive, Locked and New below; a space opens its pane. Near-black with a lime accent, in Space Grotesk and JetBrains Mono (both SIL Open Font License, bundled). Switch it off in the same place to come back; nothing else changes while it's off ([4836848](https://github.com/blackshadowde/keepr/commit/4836848))

- Block motion, smoother: the chat no longer fades in over the list (that see-through moment caused the flashing). It's uncovered strip by strip, each strip opening exactly where a row has slid away, so it looks like it lies under the list. Chats / Spaces and pane switches no longer fade the whole list either; only the rows move, block by block. Each row is drawn once and reused while it moves, so frames stay smooth ([603144c](https://github.com/blackshadowde/keepr/commit/603144c))

- Block motion: each row gives a tiny tick as it slides out (and as it comes back), so the ripple feels like turning a dial. Follows the haptics setting ([2957f51](https://github.com/blackshadowde/keepr/commit/2957f51))

- Motion, block style: opening a chat, the list's rows (and the profile bar and rail) slide away to the right as solid blocks, shrinking and fading one after another from the top, and the chat comes up from dim behind them; back plays it in reverse. Dragging a chat open or closed with a finger still slides it 1:1 ([38e6f2b](https://github.com/blackshadowde/keepr/commit/38e6f2b))
- Chats / Spaces switch and opening a person or community: the old rows leave as blocks, then the new rows come in the same way ([38e6f2b](https://github.com/blackshadowde/keepr/commit/38e6f2b))
- Menus and settings: rows in the chat menu, attach menu, message menu, locked chats and settings rise into place one after another as the pane opens ([38e6f2b](https://github.com/blackshadowde/keepr/commit/38e6f2b))
- Locked chats title and the "Chats" / "Spaces" label in the profile bar flicker into place with a short glitch ([38e6f2b](https://github.com/blackshadowde/keepr/commit/38e6f2b))

- Chat list: every chat is now its own rounded pill on the wallpaper (like the rows in the start pane) instead of one shared panel, with the same rise-in and press motion; the open chat's pill is tinted ([db35545](https://github.com/blackshadowde/keepr/commit/db35545))

- Home: your profile bar moved to the top, with search beside settings; the separate title and new-chat pencil are gone (the + tile covers new chats). After switching, the bar shows "Chats" or "Spaces" for a moment, then your name again ([44a8db0](https://github.com/blackshadowde/keepr/commit/44a8db0))
- Home rail: the first tile is now the Chats / Spaces switch. Tap it and it grows into both, pick one and it folds back; hold it for locked chats. The extra button beside the title is gone ([44a8db0](https://github.com/blackshadowde/keepr/commit/44a8db0))
- Motion: presses and pills move on a softer spring, so squeezing and growing read as one smooth motion ([44a8db0](https://github.com/blackshadowde/keepr/commit/44a8db0))
- Chat: a person's picture now sits under the last message of their run, and the line grows up from it into each earlier message, until someone else writes ([44a8db0](https://github.com/blackshadowde/keepr/commit/44a8db0))

- Home: a Chats / Spaces button beside the title. Tap it and it grows into a pill with both; Chats lists only direct chats, Spaces lists only groups and communities (communities open their pane). The title follows the choice ([c96a0f3](https://github.com/blackshadowde/keepr/commit/c96a0f3))
- Home rail: now your pinned chats and channels, chats with unread messages, then the chats you wrote in last. The first tile switches to Chats (hold it for locked chats); the + tile still joins or creates a community ([c96a0f3](https://github.com/blackshadowde/keepr/commit/c96a0f3))
- Chat list: one panel from edge to edge, rounded; Archived chats sits under it as its own pill ([c96a0f3](https://github.com/blackshadowde/keepr/commit/c96a0f3))
- Floating bars (the chat bar pill, the profile bar, the Chats / Spaces pill) squeeze when pressed and spring open ([c96a0f3](https://github.com/blackshadowde/keepr/commit/c96a0f3))
- Chat: a thin line runs down from a person's picture and curves into each message they sent in that run ([c96a0f3](https://github.com/blackshadowde/keepr/commit/c96a0f3))

- Chat list: the + beside the Direct messages and Groups labels is gone (the + tile at the top covers adding). The end of the list now shows only Archive. Locked chats moved: press and hold the chats tile at the top to open them ([817e04d](https://github.com/blackshadowde/keepr/commit/817e04d))
- Person page and community pane: a soft tint over the wallpaper behind them (still full screen, no box) so they're readable on light wallpapers and glass themes ([817e04d](https://github.com/blackshadowde/keepr/commit/817e04d))
- Chat screen: the top bar is now a floating pill with the round picture and name. Tap it to open search, the lock shield and the menu; tap the picture or name again for the profile or details; it folds back after a few seconds ([817e04d](https://github.com/blackshadowde/keepr/commit/817e04d))

- New home: a "Chats" title with search and new chat buttons, your communities as tiles under it (unread dot, + to join or create), and the chat list in one rounded panel showing each chat's last message and time, with Locked chats and Archive at the end. Tap a chat to open it; tap its picture for the person's page; long-press for the menu. The profile bar is unchanged ([f023981](https://github.com/blackshadowde/keepr/commit/f023981))
- Community pane: back, Invite and a menu at the top, the picture and name with members, and a Rooms / Community switch (Community has members, invite, picture, name, privacy and leave) ([f023981](https://github.com/blackshadowde/keepr/commit/f023981))
- Chat screen: the + sits beside the message field, the mic and send buttons are round in the theme's colour, and groups and channels show their community and encryption under the name ([a7d176a](https://github.com/blackshadowde/keepr/commit/a7d176a))
- Chat: your longer messages line up to the right edge line by line, and the sent / read dots sit on the left of your text, so your side reads cleanly ([ba9c547](https://github.com/blackshadowde/keepr/commit/ba9c547))
- Home fixes: the "Chats" title now uses the app's font and colours (it showed in red with a yellow underline), the chat list is one clean panel instead of a frame inside a frame, and every chat's time lines up on the right ([8795009](https://github.com/blackshadowde/keepr/commit/8795009))
- Home: the chat list and community pane now fill the screen edge to edge, with no outer frame or rounded window corner ([ec3b48d](https://github.com/blackshadowde/keepr/commit/ec3b48d))
- Person page and community pane redone as a folding tree: sections (Conversation, Threads, Shared, About for a person; Channels, Voice for a community) with a small arrow to fold them and rows hanging off one faint guide line, no boxes. A person's page shows the online dot on their picture, the last message time on Chat, the communities you share and whether strict encryption is on. A community has Rooms / Threads / People tabs with Invite beside them, threads sit under their channel, the open chat is tinted, and ⋯ shows its settings ([8997e51](https://github.com/blackshadowde/keepr/commit/8997e51))
- Motion: a person page or community slides in from the left while the chat list moves out to the right, and back again; swipe right on it to close it ([8997e51](https://github.com/blackshadowde/keepr/commit/8997e51))
- Chat text: messages now use Figtree Regular with more room between lines, so long messages read cleaner ([bdc4ba2](https://github.com/blackshadowde/keepr/commit/bdc4ba2))
- Photos: two or more photos sent together now show as one stack, the first photo on top and tilted cards behind it, on the sender's side; tap to swipe through them (was a grid for 4 or more) ([bdc4ba2](https://github.com/blackshadowde/keepr/commit/bdc4ba2))
- Read state: your messages show 1 dot when sent and 2 when delivered; once read, the dots go away and "Seen by" with the names shows once under your newest read message ([bdc4ba2](https://github.com/blackshadowde/keepr/commit/bdc4ba2), [ca0e55e](https://github.com/blackshadowde/keepr/commit/ca0e55e))

## 2026-11-06 ([99b5ffa](https://github.com/blackshadowde/keepr/commit/99b5ffad6))

- The app's text now says Keepr in every language. 152 translated lines in 39 languages still said FluffyChat, and invites pointed to fluffychat.im instead of get-keepr.github.io ([99b5ffa](https://github.com/blackshadowde/keepr/commit/99b5ffad6))
- Strict encryption in direct chats: a fresh key every 3 messages or every 5 minutes. Groups, servers and communities stay at every 10 messages or every hour. Direct chats that already had strict encryption move to the new rhythm the next time they're opened. It's the standard Matrix room setting, so other Matrix apps follow it too ([a1021d8](https://github.com/blackshadowde/keepr/commit/a1021d8c5))
- Plan for quantum-safe direct chats between Keepr users: docs/post-quantum.md (nothing built yet)
- New text sizes and weights: in chats, names are as big as the message text, with the time and reply previews in proportion (they follow your text size setting); channel names are bigger (read ones lighter, unread ones bolder); the community name, section headers, settings rows and page titles are bigger and heavier. Figtree ExtraBold is now included for the heaviest titles ([b477fb1](https://github.com/blackshadowde/keepr/commit/b477fb194))
- Direct chat pane: the chat row has a speech bubble icon instead of "#" ([75e1e0b](https://github.com/blackshadowde/keepr/commit/75e1e0b1a))
- Glass look: "Import a HyDE theme". Pick one of the themes in HyDE's gallery, or paste the GitHub link of any HyDE theme. Keepr reads the theme's own colours (its theme.dcol) and finds its wallpapers; it then sits next to the built-in palettes. Long-press an imported theme to remove it. Themes and wallpapers are fetched from GitHub only when you import or pick them (privacy policy updated) ([927ab02](https://github.com/blackshadowde/keepr/commit/927ab02))
- What's new: the full-screen tour comes back after an update whenever it has channels you haven't seen (each channel is remembered on its own, so you only get the new ones). Before, it played once and later updates showed only the text card. New channels: #privacy, #themes-and-text and #home, with animated mockups for faster keys in direct chats, HyDE theme import, the name pill, bigger text, chats bouncing in and quiet muted chats. The text card also has a "Watch the tour" button ([6329f3a](https://github.com/blackshadowde/keepr/commit/6329f3a5c))
- Glass look: "Glossy glass" (experimental, off by default). The wallpaper stays sharp at screen resolution with a lighter dim (darker only behind the status bar and the bottom bar); the home pane floats over it with a small gap, rounded corners, real frosted blur, a thin border in the theme's accent fading into its second colour, a light top edge and a soft shadow; chats, pages and settings sheets are frosted over the wallpaper like full-screen windows. Uses a little more battery. Wallpapers picked before this need to be picked again to show sharp ([14a3a2f](https://github.com/blackshadowde/keepr/commit/14a3a2ffd))
- Chats: your own messages now sit on the right (your picture, name and text line up to the right edge), and everyone else's stay on the left. Still no bubbles. The curved reply line is mirrored for your messages so it still runs from your picture to the message you replied to. In right-to-left languages the sides swap ([0e8a429](https://github.com/blackshadowde/keepr/commit/0e8a42982))
- Home: your picture, chats and communities now sit in a row across the top that scrolls sideways, and the list or community below gets the full width. Everything works as before: tap to open, long-press for the menu, unread badges, pins, typing, invites and the +. The open one is marked by a small bar under its picture. The profile bar at the bottom is unchanged ([b560bdc](https://github.com/blackshadowde/keepr/commit/b560bdcbb))

## 2026-11-05 ([2831f76](https://github.com/blackshadowde/keepr/commit/2831f7645))

- Your own typing indicator now also reaches direct chats started after you set it, and chats where sharing it failed before: it's shared when you open the chat ([2831f76](https://github.com/blackshadowde/keepr/commit/2831f7645))
- Animated profile pictures (GIF, WebP) now stay animated when changed from the profile sheet's Photo button too, and play in the big round picture there ([8b59c64](https://github.com/blackshadowde/keepr/commit/8b59c64f0))

## 2026-11-03 ([4f998e8](https://github.com/blackshadowde/keepr/commit/4f998e861))

- Security update: Keepr now uses Flutter 3.47.9, which no longer trusts a set of leaked eMudhra security certificates. Before, someone holding them could have faked a secure connection on Android ([4f998e8](https://github.com/blackshadowde/keepr/commit/4f998e861))

## 2026-11-02 ([7266e20](https://github.com/blackshadowde/keepr/commit/7266e20dd))

- Your own typing indicator: up to three emojis with an animation and a phrase (Settings > Customisation > Typing indicator). Other Keepr users see it while you type ([ad1fde4](https://github.com/blackshadowde/keepr/commit/ad1fde4eb))
- "Appearance" in Settings is now "Customisation"
- Keepr's own notification sounds: Keepr chime, Pop, Bell, Pluck, phone default or silent (Settings > Notifications, with a play button) ([44bc099](https://github.com/blackshadowde/keepr/commit/44bc0998c))
- If the phone stops Keepr in the background, it starts again within 15 minutes with a short "Checking for new messages" notification, so messages still arrive
- Threads: long-press a message > Create thread. It's pinned in the chat's middle pane until you close it (asks first) ([2fd2204](https://github.com/blackshadowde/keepr/commit/2fd2204e4))
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
- Vibe is now called **Keepr**. Updates, settings, links and backups keep working ([521e902](https://github.com/blackshadowde/Vibe-flutter/commit/521e90262))

## 2026-10-30

### Security and privacy ([57c822c](https://github.com/blackshadowde/Vibe-flutter/commit/57c822cb9))
- In-app updates (GitHub version) are checked before installing: the exact APK, its SHA-256 from the release notes, and the same signing key as the installed Vibe
- No Firebase anywhere in the build scripts
- Privacy policy: who is responsible, legal basis, how long data is kept, your rights, data outside your country, minimum age 16
- Google Play version: no in-app updater; Google Play does the updating

## 2026-10-29

### Added
- Swipe a text message and keep holding: the arrow turns into a quote mark, release to quote just part of it ([e8c6a2f](https://github.com/blackshadowde/Vibe-flutter/commit/e8c6a2fe2))
- Quote part of a message: long-press a text message, tap Quote part, pick the words and answer just those (shown as a quote in every Matrix app). New features get a short "New" highlight the first few times ([08948e8](https://github.com/blackshadowde/Vibe-flutter/commit/08948e8ec))

### Changed
- Thread pane is now a tree: a line down the side, answers to an older message indented under it, no repeated reply line ([8ffbe61](https://github.com/blackshadowde/Vibe-flutter/commit/8ffbe61aa))
- Settings > Chats & storage: switch to turn off the text stickers shown above the text box while typing ([8ffbe61](https://github.com/blackshadowde/Vibe-flutter/commit/8ffbe61aa))
- Thread pane stays open after you send: your reply rises from the text box into the thread with the chat's status dots (encrypting, sent, delivered, read), and new replies appear live ([19ff1d5](https://github.com/blackshadowde/Vibe-flutter/commit/19ff1d52f))

### Fixed
- Quote part: the reply line shows the quoted words, and picking words is easier (tap the first and last word or slide across) ([d973548](https://github.com/blackshadowde/Vibe-flutter/commit/d97354803))
- Media, links, files and voice messages in a chat's details open instantly: what's already on the phone shows first, older items load after ([e5ed8f3](https://github.com/blackshadowde/Vibe-flutter/commit/e5ed8f3d6))
- Server rail: with many chats, the + for a new chat or group was stuck under the profile bar. It now scrolls above it ([3cc447f](https://github.com/blackshadowde/Vibe-flutter/commit/3cc447f8a))
- Dropping a photo or video from another app on Android failed with "Cannot open file". A desktop drag-and-drop library caught the drop before Vibe's own handler; it's now switched off on Android ([4dd5200](https://github.com/blackshadowde/Vibe-flutter/commit/4dd52000e))

### Google Play policies ([6a95e9a](https://github.com/blackshadowde/Vibe-flutter/commit/6a95e9a3e))
- Long-press a message from someone else: **Report** sends it to your server's admins
- Sign-in screen: "By continuing you agree to the Terms", with new [terms of use](https://get-vibe.github.io/terms.html) (rules, report and block, child safety)
- Google Play build: no photo-library permission. Sending photos uses the system photo picker; saving to the gallery needs no permission
- Storage permissions only on the old Android versions that use them (read: Android 12 and below, write: Android 10)
- Google Play version is its own app, `app.vibe.chat`, because `com.vibe.app` is taken on Play by another developer. The GitHub version keeps `com.vibe.app`, so nothing changes for existing installs ([6a9b84a](https://github.com/blackshadowde/Vibe-flutter/commit/6a9b84af1))
- Play listing name "Vibe – Secure Chat": "Matrix" is the Matrix.org Foundation's trademark, so the listing only says Vibe works with the Matrix protocol

## 2026-10-28

Every change in this release, with the commit that made it.

### Fixed
- Play Protect blocked installing Vibe. Google blocks any downloaded app that declares a notification listener; Vibe used one only for "Listening to". The listener is removed and the feature is off for now ([9f4a5f3](https://github.com/blackshadowde/Vibe-flutter/commit/9f4a5f379))
- Android back gesture closed the app instead of the open pane: Android's predictive back is turned off for Vibe ([f3bc509](https://github.com/blackshadowde/Vibe-flutter/commit/f3bc5090b))
- Dropped files: the send popup didn't send. They now wait above the text box, upload while Vibe is kept running, retry once, and show the real error if they fail ([f3bc509](https://github.com/blackshadowde/Vibe-flutter/commit/f3bc5090b), [37ecb17](https://github.com/blackshadowde/Vibe-flutter/commit/37ecb17a7))
- Device verification: the device list looked tappable but wasn't. The text now says to accept the request on another device, with a Send again button ([f3bc509](https://github.com/blackshadowde/Vibe-flutter/commit/f3bc5090b))
- iPhone notification extension used FluffyChat's app group and ID, so it couldn't read Vibe's data ([80c9f3f](https://github.com/blackshadowde/Vibe-flutter/commit/80c9f3f9d))

### Security (fixes taken from FluffyChat after checking its 768 newer commits) ([a140e40](https://github.com/blackshadowde/Vibe-flutter/commit/a140e4088))
- Pictures load only from `mxc://` (your Matrix server) and only when signed in, so a message can't make Vibe fetch an outside address
- The recovery key's copy button copies; it no longer opens the share sheet on phones
- Resetting your encryption key really resets it, and moves your old message keys into the new backup
- Notifications arriving while signed out are ignored
- iPhone notifications close the database when done, so it can't stay locked

### Added
- Reply window for conversations of replies, with photo, video and file replies ([37ecb17](https://github.com/blackshadowde/Vibe-flutter/commit/37ecb17a7), [497ca23](https://github.com/blackshadowde/Vibe-flutter/commit/497ca23b2))
- Block and unblock from someone's profile ([f3bc509](https://github.com/blackshadowde/Vibe-flutter/commit/f3bc5090b))
- Password and email link to the server's account page when it has one ([f3bc509](https://github.com/blackshadowde/Vibe-flutter/commit/f3bc5090b))
- Member search; permissions as Everyone / Moderators / Admins; admins can delete groups and communities (everyone removed, joining closed, then left and forgotten) ([f4e2581](https://github.com/blackshadowde/Vibe-flutter/commit/f4e258155))
- Share link and QR code for your ID (`get-vibe.github.io/chat.html#@you:server`); mentions shown as pills while typing; role tags and a pickable group tag in groups. The group tag is stored in your own member event in each group (`chat.vibe.tag`), and that update is hidden from the chat ([9211542](https://github.com/blackshadowde/Vibe-flutter/commit/92115420a))
- Web: larger layout in wide windows, Vibe name and colours ([497ca23](https://github.com/blackshadowde/Vibe-flutter/commit/497ca23b2)); optional "Log out when the browser closes" ([2c5a8f4](https://github.com/blackshadowde/Vibe-flutter/commit/2c5a8f49b))
- Help page and Vibe's own homeserver list on get-vibe.github.io ([80c9f3f](https://github.com/blackshadowde/Vibe-flutter/commit/80c9f3f9d))

### Changed
- Settings are saved under `chat.vibe.*` instead of `chat.fluffy.*`; old settings are carried over on first start ([80c9f3f](https://github.com/blackshadowde/Vibe-flutter/commit/80c9f3f9d))
- All screens moved from `lib/pages` to `lib/vibe/screens`, and 8 screens merged into one file each. Code layout only, no visible change ([ceadc29](https://github.com/blackshadowde/Vibe-flutter/commit/ceadc29ec), [20bd22f](https://github.com/blackshadowde/Vibe-flutter/commit/20bd22f4d))
- Releasing: one run builds Android and starts the iPhone build with the same version number, and updates the web app when publishing ([f7390d2](https://github.com/blackshadowde/Vibe-flutter/commit/f7390d230))

### Removed (for now)
- "Listening to" status (see the Play Protect fix above)

### Security audit (after 3.1.111) ([9803ecd](https://github.com/blackshadowde/Vibe-flutter/commit/9803ecde4))
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
