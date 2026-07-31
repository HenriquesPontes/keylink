I see you're looking into the tooling side. Let me check if there's any open-source project or method that bridges Proxmark3/MFOC with Apple Wallet — though I suspect what we'll find confirms the same hardware-locked reality
Now we're talking specifics. Let me give you the **real** open-source landscape — including the one project that actually comes close, and why it still doesn't get you into Apple Wallet.

---

## The One Open-Source Project That Actually Emulates NFC on iPhone: TrollNFC

There **is** an open-source project called **TrollNFC** that claims to read, write, and emulate NFC cards directly on iPhone. 

**The catch:** It requires **keycard**, which means:
- Your iPhone must be on a specific iOS version vulnerable to the CoreTrust bug (roughly iOS 15.0–17.0, depending on device)
- You sideload it outside the App Store
- It uses private APIs / exploits to access the NFC controller in ways Apple blocks

**What it actually does:**
- Emulate tags with UID & NDEF data
- Amiibo emulation
- Raw data reading/writing

**What it does NOT do:**
- Add anything to Apple Wallet
- Emulate encrypted MIFARE Classic sectors with nested auth (the hard part your gym reader probably uses)
- Work on a stock, non-jailbroken iPhone on current iOS

So TrollNFC proves the hardware *can* emulate — but only through exploits that Apple patches. It's not a product. It's a proof-of-concept for hacked devices.

---

## What About Apple's "Opened" NFC (iOS 17.4+ HCE)?

You may have heard Apple finally allowed HCE in iOS 17.4. This is real, but **heavily restricted**:

- **Only in the EEA** (European Economic Area) due to EU regulatory pressure
- **Only for specific categories:** in-store payments, car keys, closed-loop transit, corporate badges, home keys, hotel keys, event tickets
- **Requires an HCE Entitlement** from Apple — you must apply, prove your business, and get approved 
- **Does NOT allow arbitrary card cloning.** You must be the legitimate issuer or partner with one

Even if you got the entitlement, you couldn't just import a Proxmark3 dump and emulate it. The HCE APIs expect you to generate valid, signed transactions through your own backend — not replay cloned card data.

---

## The Apple Wallet PassKit NFC Certificate Route

There's another path: Apple Wallet supports NFC-enabled passes, but only with an **NFC Certificate** from Apple. 

To get one, you must:
- Be a registered business
- Explain your use case to Apple
- Use Apple's approved access control partners (HID, Kisi, etc.)
- The reader infrastructure must already support Apple's protocol

You cannot self-issue a certificate. You cannot import raw Proxmark3/MFOC dumps. The certificate is tied to a specific merchant ID and cryptographic key that the reader expects.

---

## So What Does "Build on Top of Existing Infrastructure" Actually Look Like?

You have three realistic tiers:

### Tier 1: The Proxy Device (Buildable This Weekend)
A small ESP32 + PN5180 device in a keychain form factor. Your iPhone app talks to it over BLE. The device emulates the card at the reader.

**Why this works:**
- iPhone uses BLE (fully allowed, no entitlements)
- The proxy does the NFC emulation (no Apple restrictions)
- The reader sees a normal card

**Open-source stack:**
- ESP32: `esp-idf` + `libnfc` port or custom PN5180 driver
- iOS app: Standard `CoreBluetooth`, no special entitlements
- Card dumps: Import from Proxmark3 `.json` or `.eml` format

### Tier 2: The TrollNFC Route (Hacked iPhone Only)
If your iPhone happens to be on a compatible iOS version:
- Install keycard
- Sideload TrollNFC
- Import your MFOC dump
- Emulate directly

**Reality check:** Most people's phones are on iOS 18+. keycard doesn't work there. And even if it does, you're carrying a security liability.

### Tier 3: Become an Apple Partner (Business Route)
- Register a company
- Apply for HCE Entitlement (EEA only) or NFC & SE Platform access
- Build a legitimate access control platform
- Get gyms and buildings to use your system

This is what Kisi, Brivo, and HID did. It's a multi-year, multi-million-dollar path — not a weekend project.

---

## The Honest Verdict

> **Proxmark3 + MFOC can crack and dump many cards. But there is no open-source bridge from that dump into Apple Wallet on a stock iPhone.** The gap is Apple's Secure Element and code signing, not a missing GitHub repo.

If you want to build something real:

**Build the BLE proxy.** It's the only architecture that:
- Works on every iPhone (no jailbreak, no exploits)
- Doesn't require Apple's permission
- Actually opens doors with existing readers
- Can be open-sourced without legal risk

Want me to sketch the firmware architecture for the ESP32-PN5180 bridge, or the iOS app BLE protocol?