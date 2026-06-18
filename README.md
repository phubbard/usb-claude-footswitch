# Claude Footswitch

A tiny macOS menu-bar app that maps a **USB foot pedal** to Claude Desktop's
**"Allow once"** action. Stomp the pedal to approve whatever Claude is asking to do —
hands stay on the keyboard.

Built for the **RDing / PCsensor USB foot switch** (VID `0x1130`, PID `0x660C`), the
common single-pedal model. Other pedals work too if you adjust the IDs (see below).

## How it works

1. **Reads the pedal directly.** The pedal enumerates as a USB HID keyboard. The app
   matches it by vendor/product ID with `IOHIDManager` and treats any key-down from it
   as a "press" — it doesn't matter which key the pedal is programmed to send, so no
   Windows configuration software is needed.
2. **Suppresses the stray keystroke.** By default the device is *seized* (opened
   exclusively), so the key it would otherwise type never reaches the focused app. The
   pedal becomes a dedicated approve button. Toggle this off in the menu if you'd rather
   keep its normal keystroke.
3. **Sends ⌘↩ to Claude.** Claude's permission prompt binds **⌘↩ (Command-Return)** to
   "Allow once". On a pedal press the app brings Claude to the front (if it isn't
   already) and injects that chord into the system event stream. This is deliberately
   *not* an accessibility-tree button press — Claude's prompt is web content that
   doesn't expose tappable AX buttons, so replaying its keyboard shortcut is far more
   reliable.

## Requirements

- macOS 13+ (built and tested on macOS 26, Apple Silicon)
- Xcode / Swift toolchain (`swift --version`)

## Build & run

```sh
make run        # build the .app and launch it
# or
make install    # build, copy to /Applications, and launch from there
```

The build is signed with a **stable local identity** (created automatically by
`scripts/signing-setup.sh` in a dedicated keychain). That matters: ad-hoc signing
changes the app's code hash on every build, which makes macOS silently revoke your
permission grants. With the stable identity, **you grant once and it sticks across
rebuilds**. (Set `CODE_SIGN_IDENTITY="Developer ID Application: …"` to use your own.)

On first launch, grant **two** permissions:

| Permission | Why | Where |
|---|---|---|
| **Input Monitoring** | read the foot pedal | System Settings ▸ Privacy & Security ▸ Input Monitoring |
| **Accessibility** | send ⌘↩ to Claude | System Settings ▸ Privacy & Security ▸ Accessibility |

The app re-checks live and starts working within a couple of seconds of granting — no
relaunch needed in most cases. If a grant isn't detected, use **Relaunch** in the menu.
The **Permissions** section shows ✓/✕ and links straight to each pane.

## Using it

- Look for the 👣 **footprints icon** in the menu bar. Full opacity = ready (pedal
  connected + permissions granted); dimmed = something's missing (open the menu).
- When Claude shows a permission prompt, **press the pedal**. The icon flashes green on
  success, red on failure.
- **Approve Claude (send ⌘↩) now** in the menu does the same thing without the pedal —
  use it to test.

## Menu reference

- **Approve Claude (send ⌘↩) now** — fire the action manually (test).
- **Suppress pedal's own keystroke** — toggle seizing the device (on by default).
- **Permissions** — live ✓/✕; click a row to open the right Settings pane. A
  **Relaunch** item appears here if a grant isn't being picked up.
- **Diagnostics ▸ Log pedal events** — log every raw HID event to Console:
  `log stream --predicate 'subsystem == "net.phfactor.ClaudeFootswitch"'`
- **Diagnostics ▸ Show Claude's buttons…** — lists any buttons Claude exposes to
  Accessibility (usually none — confirming why we send a keystroke instead).
- **Launch at login** — register as a login item.

## Troubleshooting

- **Pedal flashes green but Claude doesn't approve.** The prompt window must belong to
  Claude. The app brings Claude to the front and sends ⌘↩; confirm ⌘↩ is the "Allow
  once" shortcut in your Claude build (it's shown on the button). Watch the live log
  (above) while pressing to see what's sent.
- **Permissions show ✕ even though you granted them.** Almost always stale grants from a
  previous *ad-hoc* build. Clear and re-grant on the stable-signed build:
  ```sh
  make reset-tcc && make install
  ```
- **Pedal not detected.** Confirm it's the expected device:
  ```sh
  ioreg -p IOUSB -l -w 0 | grep -iE 'Foot Switch|idVendor|idProduct'
  ```
- **A different pedal.** Change `vendorID` / `productID` in
  `Sources/ClaudeFootswitch/HIDFootswitch.swift` and rebuild.

## Configuration (defaults)

```sh
defaults write net.phfactor.ClaudeFootswitch targetBundleID "com.anthropic.claudefordesktop"
defaults write net.phfactor.ClaudeFootswitch seizeDevice -bool true
defaults write net.phfactor.ClaudeFootswitch debounceMs -int 250
```

## Project layout

```
Sources/ClaudeFootswitch/
  main.swift          NSApplication bootstrap (accessory / menu-bar)
  AppDelegate.swift   status item, menu, permission flow, wiring
  HIDFootswitch.swift IOHIDManager pedal watcher (match, seize, debounce)
  AllowOnce.swift     finds Claude and sends the ⌘↩ "Allow once" chord
  Permissions.swift   Input Monitoring + Accessibility helpers
  Settings.swift      UserDefaults-backed configuration
Resources/Info.plist  LSUIElement bundle metadata
Resources/AppIcon.icns app icon
tools/make-icon.swift  renders the app icon at every size
scripts/signing-setup.sh  creates the stable local signing identity
scripts/make-icon.sh   renders + packs AppIcon.icns
scripts/make-app.sh    build + assemble + sign the .app
Makefile               build / icon / run / install / debug / reset-tcc
```
