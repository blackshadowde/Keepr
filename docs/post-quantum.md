# Post-quantum direct chats (plan)

An extra lock on direct chats between two Keepr users, so that messages
recorded today can't be read later by a quantum computer ("harvest now,
decrypt later"). Groups, servers and communities stay on normal Matrix
encryption with strict key rotation (every 10 messages or every hour).

Status: plan only, nothing built yet. Start after Keepr is in production on
Google Play. Steps are checked off as they land.

## Why an extra layer is needed

- Matrix locks messages with Megolm keys, and sends those keys between
  devices with Olm (X25519). X25519 is not quantum-safe: someone who records
  the traffic today could recover the Megolm keys with a future quantum
  computer, and with them the messages.
- Strict key rotation limits how much one key unlocks, but doesn't stop that.
- So the message text gets a second lock, inside the normal Matrix one, with a
  key that comes from a quantum-safe exchange. To read it, both locks have to
  be broken ("hybrid": as safe as the stronger of the two).

## What it looks like for people

- A direct chat where both people use Keepr (with the feature on) shows a
  "Quantum-safe" mark next to the shield.
- In groups, servers and communities: nothing changes.
- If one person also uses another Matrix app (Element, FluffyChat), those
  messages show there as "This message is protected for Keepr only". The chat
  settings say so plainly, and the feature can be switched off per chat.
- Off by default at first; on by default only after the review (step 6).

## Building blocks

- **ML-KEM-768** (NIST FIPS 203) for the quantum-safe key exchange, combined
  with **X25519** (hybrid), like Signal's PQXDH and SimpleX's hybrid ratchet.
- **HKDF-SHA-256** to mix both secrets into one key, **AES-256-GCM** (or
  ChaCha20-Poly1305) for the inner lock.
- Code: a well-known, audited Rust implementation (RustCrypto `ml-kem`, or
  liboqs), called through Rust bindings the same way Keepr already uses
  `flutter_vodozemac` for Matrix encryption. No crypto written from scratch.

## Decisions to make first

1. **Ratchet or session key.** Simple: one quantum-safe key per pair of
   devices, refreshed every N messages / days. Stronger: a quantum-safe
   ratchet (a fresh exchange every few messages, like SimpleX). Recommended:
   start simple, refresh every 50 messages or 1 day, ratchet later.
2. **Where keys live.** The private ML-KEM keys stay on the device (Android
   Keystore / iOS Keychain-backed storage), never in the server key backup
   unless the backup itself is quantum-safe. Recommended: device only at first.
3. **How devices find each other's keys.** Publish the ML-KEM public key as
   part of the device's Matrix info (signed by the device's Ed25519 key, so the
   server can't swap it). Verified devices only.
4. **History on a new device.** Simplest: older quantum-safe messages don't
   open on a device added later (like disappearing history). Later: a
   quantum-safe way to pass keys between your own verified devices.

## Roadmap

### Step 0: research (before any code)
- [ ] Check what Matrix itself is doing (vodozemac, MLS work, any
      post-quantum proposals) so Keepr doesn't build something Matrix will
      soon offer as a standard
- [ ] Read Signal's PQXDH / triple-ratchet papers and SimpleX's
      post-quantum ratchet notes; pick the design for decision 1
- [ ] Pick the Rust library; check its licence (must fit AGPL-3.0), audits,
      and Android / iOS / web support
- [ ] Measure: key and message sizes, battery and speed on a mid-range phone

### Step 1: keys
- [ ] Rust bindings: ML-KEM-768 keygen / encapsulate / decapsulate, HKDF,
      AES-GCM; tests against the official FIPS 203 test vectors
- [ ] Each device makes its ML-KEM key pair once, stored securely
- [ ] Publish the public key with the device info, signed; check signatures
      when reading other people's keys

### Step 2: the handshake
- [ ] In a direct chat, when both sides have Keepr keys: hybrid exchange
      (X25519 + ML-KEM) per pair of devices, sent as an encrypted
      to-device message
- [ ] Mix both secrets with HKDF into the inner key; refresh by the rule
      from decision 1
- [ ] Handle: new device, removed device, reinstall, both sides starting the
      handshake at once

### Step 3: messages
- [ ] Text, replies and edits: inner-encrypted body inside the normal Megolm
      message, with a plain fallback line for other apps
- [ ] Files and voice messages: the file key gets the inner lock too
- [ ] The "Quantum-safe" mark; a clear message when something can't be opened

### Step 4: settings and wording
- [ ] Chat settings: "Quantum-safe (Keepr only)" switch, with what it does and
      what other apps will see
- [ ] Settings > Security: on/off for new direct chats
- [ ] Wipe and reset of the quantum-safe keys

### Step 5: testing
- [ ] Two Android phones, then Android + iPhone, then + web
- [ ] Mixed: one side also on Element (fallback text shows, nothing breaks)
- [ ] Lost device, new device, restore from backup, airplane mode, slow network
- [ ] Unit tests for every message type and for tampered messages being refused

### Step 6: review and release
- [ ] Write up the design in plain words (`docs/post-quantum-design.md`)
- [ ] Outside security review of the design and the code before it is on by
      default
- [ ] Release as opt-in first ("Labs" in settings), then on by default for
      Keepr-to-Keepr direct chats

### Later
- [ ] Quantum-safe ratchet (fresh exchange every few messages)
- [ ] Quantum-safe key backup, so history can follow you to a new device
- [ ] Switch to Matrix's own post-quantum standard when there is one, and keep
      reading old messages

## Already done (today's protection)

- [x] Strict encryption: a fresh key every 10 messages or every hour in
      groups, servers and communities
- [x] Direct chats: a fresh key every 3 messages or every 5 minutes, and
      existing strict direct chats move to this when opened
