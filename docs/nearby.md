# Nearby: offline chat over Bluetooth (plan)

Chat with Keepr phones around you with no internet, no server and no
account. Messages hop from phone to phone (mesh) and wait for people who are
out of range (store and forward). Separate from Matrix: nothing here touches
the Matrix account, rooms or keys.

Status: research done, nothing built yet. Steps are checked off as they land.

## What the research found

Source: bitchat's protocol whitepaper v2.0 (permissionlesstech/bitchat,
WHITEPAPER.md, July 2026).

**Licences**
- bitchat (iOS): released into the public domain. Its design and code can be
  reused freely.
- bitchat-android (permissionlesstech/bitchat-android): the repo shows
  GPL-3.0 in its sidebar but its readme says public domain. GPL-3.0 can be
  combined with Keepr's AGPL-3.0, so either way we may reuse it. Check the
  LICENSE file before copying any code, and credit it in the changelog.

**How bitchat's mesh works (numbers to copy)**
- Every phone is both a BLE central and a peripheral (GATT server + client).
- Packet: version, type, TTL, timestamp, flags, 8-byte sender ID, optional
  8-byte recipient ID, payload, optional Ed25519 signature. The signature
  leaves out the TTL so relays can lower it. v2 can carry a source route.
- TTL 7 at the start. In crowded spots (6+ links) broadcasts are capped at 5.
- Duplicates are dropped with a "seen" list: 1000 entries, 5 minutes, keyed
  by sender + timestamp + type + payload hash.
- Relays wait a random 10–220 ms before passing a packet on, and send
  broadcasts to about log2(links) neighbours, never back the way it came.
- Big packets are split into ~469-byte pieces (8-byte piece ID, index/total).
  Reassembly: 128 at once, 30 s timeout, 1 MiB max.
- Encrypted packets are padded to 256/512/1024/2048 bytes so their size
  says less.
- Live private chats: Noise XX, Curve25519 + ChaCha20-Poly1305 + SHA-256.
- Identity: a Curve25519 key (Noise) and an Ed25519 key (signatures). The
  8-byte peer ID is the start of the SHA-256 of the Noise key.
- Store and forward:
  - the sender's outbox keeps 100 messages per person for 24 h, with up to
    8 retries
  - up to 3 phones ("couriers") carry a sealed message (Noise X, one way),
    24 h, 16 KiB max
  - favourites may leave 5 messages each with a courier, others 2
  - history sync: 1000 recent packets compared about every 15 s, kept 6 h
- Weak points they admit: the peer ID never changes (can be tracked) and
  metadata is the weakest part. Courier messages have no forward secrecy.

**Flutter side**
- `bluetooth_low_energy` (pub.dev, 6.2.x) does both roles on Android. On
  iOS the GATT server is partial (no connection events). Fine for testing,
  but not for an always-on mesh.
- An always-on mesh on Android needs a foreground service, which a Flutter
  plugin can't run reliably. So the radio and relaying go in native Kotlin
  (like bitchat-android's `MeshForegroundService`). Dart gets the messages
  through a method channel, the same way `VibeCheckWorker` and the other
  native helpers do.
- Crypto in Dart: the `cryptography` package has X25519, Ed25519,
  ChaCha20-Poly1305 and SHA-256. Noise XX is a small state machine on top
  (or the Kotlin side does it, see the decision below).

## Decisions to make before building

1. **Talk to bitchat phones too, or Keepr only?** If we follow bitchat's
   wire format exactly, Keepr users can also chat with bitchat users nearby,
   and the mesh gets much bigger. That means using their service UUID and
   packet types as they are. Recommended: yes, compatible.
2. **Where the crypto runs.** In Kotlin, next to the radio (works when the
   app is closed). Or in Dart (shares code with iOS later). Recommended:
   Kotlin on Android first. iOS gets its own Swift copy later, as bitchat
   does.
3. **Nickname.** Random by default, or the Matrix display name. Recommended:
   random, changeable, never the Matrix ID (so people can't be traced).
4. **Off by default.** Yes. Bluetooth scanning uses battery.

## Android requirements

- Permissions (Android 12+): BLUETOOTH_SCAN (`neverForLocation`),
  BLUETOOTH_ADVERTISE, BLUETOOTH_CONNECT. Android 10–11 need
  ACCESS_FINE_LOCATION for scanning.
- Foreground service type `connectedDevice`, with a "Nearby is on"
  notification that has a Stop button.
- Google Play: declare the `connectedDevice` foreground service in
  App content → Foreground services (short video: turning Nearby on), and
  add "Nearby devices" to the data safety answers (no data leaves the phone
  through us).
- Battery: scan in short bursts (for example 4 s on, 6 s off), and slow down
  when the screen is off and nothing has arrived for a while.

## Roadmap

### Step 1: phone-to-phone (no relaying)
- [ ] Kotlin `KeeprNearbyService`: advertise + GATT server + scan +
      client, one service UUID and one characteristic for packets
- [ ] Packet encode/decode (format above), fragmenting and reassembly
- [ ] Identity keys made on first use, kept in Android Keystore-backed storage
- [ ] Noise XX handshake and encrypted private messages
- [ ] Public nearby room (signed, not encrypted, as in bitchat)
- [ ] Dart side: `lib/vibe/nearby/` channel, models, local message store
- [ ] UI: "Nearby" row in the server rail, people around you, the public
      room, private chats; plain wording, no emojis in menus
- [ ] Settings → Nearby: on/off, nickname, "Stop when I leave the app"
- [ ] Test between two Android phones

### Step 2: mesh relaying
- [ ] TTL, seen list (1000 / 5 min), random 10–220 ms relay delay
- [ ] Send broadcasts to ~log2(links) neighbours, never back to the sender
- [ ] Private messages relayed as sealed packets (relays can't read them)
- [ ] Padding to 256/512/1024/2048
- [ ] Show how many hops a message took (optional)
- [ ] Test with 3 phones in a line (A can't reach C directly)

### Step 3: store and forward
- [ ] Outbox: 100 per person, 24 h, up to 8 retries, delivered when they
      come in range
- [ ] Couriers: up to 3 phones carry a sealed message (24 h, 16 KiB),
      with deposit limits (favourites 5, others 2)
- [ ] History sync every ~15 s with new neighbours (last 6 h, 1000 packets)
- [ ] Delivered / read ticks across the mesh
- [ ] Favourites (people you trust as couriers)
- [ ] "Wipe Nearby" in settings (keys, history, outbox)

### Later
- [ ] iPhone (Swift, CoreBluetooth; works mainly while Keepr is open)
- [ ] Changing peer IDs so phones can't be tracked over time
- [ ] Bridging over the internet when one phone has signal (optional)
