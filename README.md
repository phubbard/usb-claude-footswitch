# Claude Footswitch

A tiny macOS menu-bar app that maps a **USB foot pedal** to Claude Desktop's
**"Allow once"** action. Stomp the pedal to approve whatever Claude is asking to do —
hands stay on the keyboard.

Built for the **RDing / PCsensor USB foot switch** (VID `0x1130`, PID `0x660C`), the
common single-pedal model. Other pedals work too if you adjust the IDs (see below).

## How it works

1. **Reads the pedal directly.** The pedal enumerates as a USB HID keyboard (this unit
   is configured to type Return). The app matches it by vendor/product ID with
   `IOHIDManager` and treats any key-down from it as a press — no Windows config tool
   needed. It reads the device *non-exclusively*: macOS doesn't let a userspace app
   truly seize a keyboard (trying it blocks event delivery and re-enumerates the device
   in a loop), so seizing isn't an option.
2. **Sends ⌘↩ to Claude.** Claude's permission prompt binds **⌘↩ (Command-Return)** to
   "Allow once". On a press the app brings Claude to the front (if needed) and injects
   that chord. Replaying the shortcut is far more reliable than poking the accessibility
   tree, which Claude's web-based prompt doesn't expose as tappable buttons.
3. **Suppresses the pedal's own Return.** Because the device isn't seized, its Return
   would otherwise leak to the focused app (and could submit a line in a terminal). A
   `CGEventTap` drops that Return in a brief window *armed by a confirmed pedal press*.
   Your real Enter key is untouched (it's outside the window), and our own ⌘↩ is
   untouched (it carries the Command flag; only the pedal's *plain* Return is dropped).

## Requirements

- macOS 13+ (built and tested on macOS 26, Apple Silicon)
- Xcode / Swift toolchain (`swift --version`)

## Build & run

```sh
make run        # build the .app and launch it
# or
make install    # build, copy to /Applications, and launch from there
```

**Signing matters here.** macOS revokes Accessibility / Input Monitoring grants whenever
an app's code signature changes, so ad-hoc signing (new hash every build) would make you
re-grant constantly. The build picks the most stable identity available, in order:

1. `CODE_SIGN_IDENTITY="…"` if you set it
2. a **Developer ID Application** identity, if you have one (auto-detected; hardened
   runtime, notarization-ready, Team-ID-stable)
3. a **stable local self-signed** identity (`scripts/signing-setup.sh`, created in a
   dedicated keychain)
4. ad-hoc (last resort)

With any real identity, **you grant permissions once and they persist across rebuilds.**

On first launch, grant **two** permissions:

| Permission | Why | Where |
|---|---|---|
| **Input Monitoring** | read the foot pedal | System Settings ▸ Privacy & Security ▸ Input Monitoring |
| **Accessibility** | send ⌘↩ and run the Return-suppression event tap | System Settings ▸ Privacy & Security ▸ Accessibility |

The app re-checks live and starts within a couple of seconds of granting. Input
Monitoring only takes effect for a process that had it at launch, so the app
**relaunches itself automatically** once you enable it. The menu's **Permissions**
section shows ✓/✕ and links straight to each pane.

## Using it

- The 👣 **footprints icon** in the menu bar is full-opacity when ready (pedal connected
  + both permissions), dimmed otherwise.
- With a Claude permission prompt up, **press the pedal** → menu icon flashes a **green
  checkmark** and Claude approves.
- **Approve Claude (send ⌘↩) now** in the menu does the same without the pedal.
- Keep Claude **off to the side**: if it isn't frontmost when you stomp, the app briefly
  focuses it to approve, then hands focus back to where you were — stomp and stay in flow.

## Menu reference

- **Approve Claude (send ⌘↩) now** — fire the action manually (test).
- **Suppress pedal's own Return** — toggle the event-tap suppression (on by default).
- **Permissions** — live ✓/✕; click a row to open the right Settings pane; **Relaunch**
  appears if a grant isn't picked up.
- **Diagnostics ▸ Log pedal events** — also log raw HID values.
- **Diagnostics ▸ Show Claude's buttons…** — what the AX tree exposes (usually nothing,
  which is why we send a keystroke).
- **Launch at login** — register as a login item.

A plain-text activity log is always written to `~/Library/Logs/ClaudeFootswitch.log`
(launch state, HID open, presses, approvals, suppressed Returns) — handy for debugging.

## Troubleshooting

- **Pedal flashes green but Claude doesn't approve.** The prompt window must belong to
  Claude, and ⌘↩ must be its "Allow once" shortcut (shown on the button). Tail the log:
  `tail -f ~/Library/Logs/ClaudeFootswitch.log` while pressing.
- **The pedal's Enter still leaks.** Make sure **Suppress pedal's own Return** is on and
  Accessibility is granted (the tap needs it). The log shows `tap Return … SUPPRESSED`.
- **Permissions show ✕ after granting.** Almost always a stale grant from an earlier
  ad-hoc build. Clear and re-grant on the signed build: `make reset-tcc && make install`.
- **Pedal not detected.** `ioreg -p IOUSB -l -w 0 | grep -iE 'Foot Switch|idVendor|idProduct'`
- **A different pedal.** Change `vendorID` / `productID` in
  `Sources/ClaudeFootswitch/HIDFootswitch.swift` and rebuild. If it types something other
  than Return, change `returnKeyCode` in `KeyboardSuppressor.swift` too.

## Configuration (defaults)

```sh
defaults write net.phfactor.ClaudeFootswitch targetBundleID "com.anthropic.claudefordesktop"
defaults write net.phfactor.ClaudeFootswitch debounceMs -int 250
```

## Releasing

CI (`.github/workflows/ci.yml`) builds and checks a universal bundle on every push and PR.

To cut a release, push a version tag — `.github/workflows/release.yml` builds a
**universal, Developer ID-signed, notarized** app, packages a DMG, and publishes it to
GitHub Releases:

```sh
git tag v1.0.0
git push origin v1.0.0
```

For signing + notarization, add these repository secrets (Settings ▸ Secrets and
variables ▸ Actions). Without them the workflow still builds a DMG — just ad-hoc-signed.

| Secret | What | How to get it |
|---|---|---|
| `DEVELOPER_ID_P12_BASE64` | Developer ID Application cert **+ private key**, base64'd | Keychain Access ▸ export the cert as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | the `.p12` export password | you set it on export |
| `AC_API_KEY_ID` | App Store Connect API **Key ID** | App Store Connect ▸ Users and Access ▸ Integrations ▸ App Store Connect API |
| `AC_API_ISSUER_ID` | the **Issuer ID** shown on that page | same page |
| `AC_API_KEY_P8` | the `.p8` key contents | downloaded once when you create the key; paste the whole file |

Locally: `make release-local` builds a universal signed app + DMG (using your Developer ID
if present); `make dmg` packages whatever `make build` / `make universal` produced.

## Project layout

```
Sources/ClaudeFootswitch/
  main.swift              NSApplication bootstrap (accessory / menu-bar)
  AppDelegate.swift       status item, menu, permission flow, wiring
  HIDFootswitch.swift     IOHIDManager pedal watcher (match, debounce)
  AllowOnce.swift         finds Claude, sends ⌘↩, restores focus
  KeyboardSuppressor.swift CGEventTap that drops the pedal's stray Return
  Permissions.swift       Input Monitoring + Accessibility helpers
  Settings.swift          UserDefaults-backed configuration
  Diag.swift              plain-text activity log
Resources/                Info.plist + AppIcon.icns
tools/make-icon.swift     renders the app icon at every size
scripts/
  make-app.sh             build (universal/versioned) + assemble + sign
  make-dmg.sh             package the app into a signed DMG
  notarize.sh             notarize + staple (App Store Connect API key)
  signing-setup.sh        stable local self-signed identity
  ci-keychain.sh          import the Developer ID cert in CI
  make-icon.sh            render + pack AppIcon.icns
.github/workflows/        ci.yml (build check) + release.yml (tagged release)
Makefile                  build / universal / dmg / install / release-local / …
```
