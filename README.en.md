# Trunook

[Русский](README.md) · **English** · [简体中文](README.zh.md)

A dynamic notch for the MacBook: music, meetings, clipboard history, a shelf
for files and prompts to a local model — in the notch instead of separate
windows.

![The notch in action](docs/demo.gif)

Hover and the notch shows what is playing and when the next meeting is. Click
or swipe down and the full panel opens. Right click opens the menu of
everything.

![Gestures and shortcuts](docs/gestures.png)

## What it does

- **Music.** Track, artwork, playback controls, a progress line along the
  island's outline. Works with any player: the data comes from the system.
  Swipe with two fingers to change tracks.
- **Calendar and reminders.** A warning a chosen time before the start, a join
  button for the meeting link, a countdown in the notch. Today's tasks from
  Things 3.
- **Meeting controls.** Microphone, camera, screen sharing, raise hand and
  leave — on hover, while a call is running. Telemost, Google Meet, Zoom and
  Teams in the browser.
- **Clipboard history.** Recent copies, paste by number from the keyboard.
- **File shelf.** Drag files onto the notch and they land on the shelf. Drag
  them off into any window — the file moves for good.
- **Model prompts.** Ollama on your own machine: the answer is written right
  in the notch, and can be copied or pasted into the active window.
- **Quick commands.** Six slots with hotkeys: an app, a folder, a link, an
  AppleScript, a model prompt, or a macOS Shortcut.
- **Weather and power.** An icon with the temperature in the panel's corner,
  chips when the weather changes or the charger is plugged in.

The interface is in Russian, English and Chinese — by default it follows the
system.

## Install

### Build from source — the reliable path

```bash
git clone https://github.com/TruDevLab/Trunook.git
cd Trunook
make cert      # once: a self-signed certificate
make install   # build, sign, put into /Applications
```

Requires Command Line Tools (`xcode-select --install`). Xcode is not needed.

### From a prebuilt image

Download the `.dmg` from [releases](../../releases), drag the app into
Applications, then clear the quarantine flag:

```bash
sudo xattr -r -c /Applications/Trunook.app
```

## Limitations

### No Apple signature

The project has no paid developer account. Gatekeeper will not let the app
through on someone else's Mac (`spctl -a` returns `rejected`), notarisation is
impossible, and the App Store is out. Hence the install order above: building
from source is easier — the system does not question what you built with your
own certificate, while the image needs quarantine cleared by hand.

### The helper lives in Apple's namespace

macOS exposes the current track through the private
`MRMediaRemoteGetNowPlayingInfo`, and since macOS 15.4 an ordinary process
gets nothing back: access remained for processes with a
`com.apple.controlcenter.*` identifier. Hence the XPC helper's name,
`com.apple.controlcenter.TrunookHelper`.

The trick gives no access to anyone else's data — it lifts a restriction on
reading the state of your own media player. Apple may close it in any update:
only track titles would disappear, and the workaround itself is isolated in a
separate service.

## What leaves your Mac

- **Weather** — coordinates rounded to a hundredth of a degree (about a
  kilometre) go to open-meteo.com. That is the only request to the internet in
  the whole app.
- **Model prompts** go to Ollama on your own machine.
- **Clipboard history and the shelf** stay local: history in the app's own
  file, the shelf as links to your own files.

## Requirements

- A MacBook with a hardware notch. The app does not show up on external
  displays.
- macOS 14 or newer.
- Command Line Tools to build.
- [Ollama](https://ollama.com) for model prompts, installed separately.

## Development

Internals, hard-won findings and debugging techniques are in
[DEVELOPMENT.md](DEVELOPMENT.md) (in Russian).

```bash
make run    # build, install, launch
make test   # tests
make dmg    # disk image
```

## License

[MIT](LICENSE).
