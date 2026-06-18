# Claude Footswitch

A tiny macOS menu-bar app that maps a **USB foot pedal** to Claude Desktop's
**"Allow once"** button. Stomp the pedal to approve whatever Claude is asking to do —
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
   pedal becomes a dedicated Allow-once button. Toggle this off in the menu if you'd
   rather keep its normal keystroke.
3. **Presses the button via Accessibility.** On a press it finds the Claude app, walks
   its accessibility tree for a button labeled "Allow once", and sends a press action —
   even if Claude is in the background. Claude is an Electron app, so the app flips on
   Chromium's `AXManualAccessibility` to expose the web a11y tree.

## Requirements

- macOS 13+ (built and tested on macOS 26, Apple Silicon)
- Xcode / Swift toolchain (`swift --version`)

## Build & run

```sh
make run        # build the .app and launch it
# or
make install    # build, copy to /Applications, and launch from there
```

On first launch the app asks for two permissions. Grant **both**, then **relaunch**:

| Permission | Why | Where |
|---|---|---|
| **Input Monitoring** | read the foot pedal | System Settings ▸ Privacy & Security ▸ Input Monitoring |
| **Accessibility** | press Claude's button | System Settings ▸ Privacy & Security ▸ Accessibility |

The menu's **Permissions** section shows ✓/✕ and links straight to each pane.

## Using it

- Look for the 👣 **footprints icon** in the menu bar. Full opacity = pedal connected;
  dimmed = not found.
- When Claude shows a permission prompt, **press the pedal**. The icon flashes green on
  success, red if no "Allow once" button was found.
- **Press "Allow once" now** in the menu does the same thing without the pedal — use it
  to test.

## Menu reference

- **Press "Allow once" now** — fire the action manually (test).
- **Suppress pedal's own keystroke** — toggle seizing the device (on by default).
- **Permissions** — live status; click a row to open the right Settings pane.
- **Diagnostics ▸ Log pedal events** — log every raw HID event to Console (`log stream
  --predicate 'subsystem == "net.phfactor.ClaudeFootswitch"'`).
- **Diagnostics ▸ Show Claude's buttons…** — list the buttons the app can currently see.
  Use this if the press isn't working to check the exact label.
- **Launch at login** — register as a login item.

## Troubleshooting

- **"No 'Allow once' button visible right now."** Make sure a Claude permission prompt
  is actually on screen, then use **Show Claude's buttons…** to see the real labels. If
  the label differs, set it with:
  ```sh
  defaults write net.phfactor.ClaudeFootswitch allowOnceLabel "Allow Once"
  ```
- **Pedal not detected.** Confirm it's the expected device:
  ```sh
  ioreg -p IOUSB -l -w 0 | grep -iE 'Foot Switch|idVendor|idProduct'
  ```
- **Permissions keep re-prompting after a rebuild.** Ad-hoc signatures change each
  build. Sign with a stable identity (`CODE_SIGN_IDENTITY="Developer ID Application: …"
  make install`) or just re-grant. `make reset-tcc` clears old grants.
- **A different pedal.** Change `vendorID` / `productID` in
  `Sources/ClaudeFootswitch/HIDFootswitch.swift` and rebuild.

## Configuration (defaults)

```sh
defaults write net.phfactor.ClaudeFootswitch allowOnceLabel "Allow once"
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
  AllowOnce.swift     Accessibility search + press of the target button
  Permissions.swift   Input Monitoring + Accessibility helpers
  Settings.swift      UserDefaults-backed configuration
Resources/Info.plist  LSUIElement bundle metadata
scripts/make-app.sh   build + assemble + sign the .app
Makefile              build / run / install / debug / reset-tcc
```
