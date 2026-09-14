# Trunook

[Русский](README.md) · **English** · [简体中文](README.zh.md)

A dynamic notch for the MacBook: music, meetings, clipboard history, a shelf
for files, notes and prompts to a local model — in the notch instead of separate
windows.

![The notch in action](docs/demo.gif)

Hover and the notch shows what is playing and when the next meeting is. Click
or swipe down and the full panel opens. Hold the press and a fan of
circles for every feature slides out from under the notch: move towards the
one you want and let go. Right click, or the button in the home screen's wing,
opens the same circles without holding: click the one you want, click
elsewhere to close.

![Gestures](docs/gestures.png)

Every shortcut uses ⌃⌥ — a pair macOS reserves for nothing. Any of them can be
changed in settings or right in the welcome window.

| Shortcut | What it opens |
|---|---|
| ⌃⌥C | Capture the selection and ask the model |
| ⌃⌥V | Clipboard history |
| ⌃⌥S | File shelf |
| ⌃⌥D | Mini calendar |
| ⌃⌥T | Timer and stopwatch |
| ⌃⌥M | System load |
| ⌃⌥F | News digests and site tracking |
| ⌃⌥P | Teleprompter |
| ⌃⌥Z | New note |
| ⌃⌥⇧Z | Selected text straight to notes |
| ⌃⌃ | Ask out loud |
| ⌃⌥N | Main panel |
| ⌃⌥1 … ⌃⌥9 | Commands directly |
| ⌃⇧1 … ⌃⇧9 | Paste a clipboard entry by number |

## What it does

- **A home screen of tiles.** The expanded notch is built like a phone's home
  screen: music, upcoming meetings, the month, tasks, timer, weather, system
  load, battery, news, site tracking, an AI question field, the coffee cup,
  clipboard, shelf, notes. Tiles come in 1×1, 2×1, 3×1, 2×2, 4×1 and 4×2 on a
  four-column grid. Each shows the essentials and does the essentials —
  pause, start the timer, join the meeting — and clicking it opens the full
  panel. Pick tiles, order and size in Settings, under Home screen: drag
  tiles with the mouse.
- **Music.** Track, artwork, playback controls, a progress line along the
  island's outline. Works with any player: the data comes from the system.
  Swipe with two fingers to change tracks.
- **Calendar and reminders.** A warning a chosen time before the start, a join
  button for the meeting link, a countdown in the notch. Today's tasks from
  Things 3.
- **Mini calendar.** ⌃⌥D opens the month with week numbers and the chosen
  day's plans. Clicking an event edits it right in the notch: time,
  description, place; participants and the meeting link are alongside.
  A repeating event edits a single occurrence by default, not the series.
- **Meeting controls.** Microphone, camera, screen sharing, raise hand and
  leave — on hover, while a call is running. Telemost, Google Meet, Zoom and
  Teams in the browser.
- **Clipboard history.** Recent copies, paste by number from the keyboard;
  with the list open, ↑↓ walk the rows and Enter pastes the chosen one.
- **File shelf.** Drag files onto the notch and they land on the shelf. Drag
  them off into any window — the file moves for good.
- **Model prompts.** The question goes off with Enter, the answer is written
  right in the notch, and can be copied or pasted into the active window.
  Answering is Ollama on your own machine, and there is no need to install it
  by hand: the app downloads and starts it itself, and suggests models your
  machine can carry — light, medium and powerful for chat, plus one for notes.
  The one that fits is marked “recommended”, and a single button installs the
  pair you need. The “Answer without thinking first” switch makes answers
  several times faster; the catalogue's medium model already answers that way.
- **Your own server or the cloud.** Under “Advanced” — another local server
  with an OpenAI interface (LM Studio, llama.cpp, vLLM, Unsloth Studio) or a
  cloud one — OpenAI, Anthropic, Gemini, OpenRouter, Groq, DeepSeek. Addresses
  for all of those fill in themselves; anything else connects as a custom
  provider. Several can be kept at once: each has its own address, key and
  model, and a command picks a model from any of them.
- **An assistant that acts.** Allow it, and the model does more than answer:
  it sets timers and the stopwatch, checks what is coming up, a day's agenda
  and the weather, and creates events, reminders and notes. Reading happens
  at once; writing only after a card in the notch says “Create” or “Cancel”.
  Off by default, and it needs a model that can call tools.
- **Pointing with “@”.** Type an at sign in the question and a list opens
  below the field: meetings for the next two weeks and recent notes. What
  you pick goes into the question as a word — “@Standup move it to Tuesday
  at 15:00”, or “@Standup cancel it”. The assistant moves and cancels the
  meeting itself, asking for confirmation with a card; a note it reads and
  answers from. It will not look a meeting up by title — with three
  standups in a week, the choice is yours.
- **Voice assistant.** A double press of ⌃ asks out loud. If the assistant is
  allowed to act, voice goes the same way a typed question does: the model
  looks into your notes, the calendar or the weather by itself when it needs
  to. The panel stays closed: the notch jolts and glows — blue
  while it listens, the model's colour while it thinks and answers — and a live
  level meter on the side shows that you are being heard. The answer is short
  and read aloud as the model writes it; a button in the notch stops it. Click
  the notch to open the conversation and read it with your eyes. Having read
  the answer out, the notch listens again: you can follow up without reaching
  for the gesture, and silence ends the conversation. Voice has a model of its
  own, the lightest by default: speed matters most out loud. Speech is
  recognised **on your own machine** and never leaves it.
- **Dictation.** The microphone in the question line puts speech straight into
  the field as you talk; whatever was typed before it stays. A whole note can
  be dictated too — from a quick-access circle. Speech is recognised
  **on the computer itself**.
- **News digest.** Set topics and a schedule — say, every day at 10:00 — and
  the model collects up to five top stories per topic for the period: the
  headline, the source, the time and one sentence on why it matters. Links
  come from the feed, not from the model, so it can't invent an address.
  A pill tells you the digest is ready, and a mark stays in the notch until
  you open it. Save the digest to notes or as a Markdown file; earlier ones
  can be paged through. The model can suggest topics too — just tick the
  ones you want.
- **Site tracking.** A page link and, in words, what to track: price,
  availability, a date, the number of seats, any line of text. The page is
  opened by a built-in browser on schedule, and when the value changes the
  notch shows "was → now" with a button that opens the site. Numbers also get
  "went down", "went up" and threshold conditions. If a site asks whether
  you're a robot, you pass the check once in the app's window.
- **Notes.** The same panel has a mode switch: "Commands" is a question line and an
  answer, "Note" is a multi-line field with formatting. The model comes up with
  the note's name. Its answer goes into notes with one button too. The "search
  notes" toggle makes the model answer from your own records rather than from
  general knowledge; with an acting assistant it is not needed and goes away —
  the model looks into the notes by itself. ⌃⌥Z opens an empty note; the list with word search is one
  button away in that same panel, and notes are exported from there into
  a folder as Markdown files. Someone else's text goes in without retyping:
  ⌃⌥⇧Z saves whatever is selected in any window, and copied text has a button
  both in the clipboard history and on the copy badge.
- **Commands.** ⌃⌥C captures the selection and opens a conversation with the
  model: the captured text sits in a pill above the field, the command list
  below it. There can be any number of commands, they can be reordered, and
  every model prompt carries its own model — shown on the right of its
  row and changed in place with Tab or a click. Besides model prompts,
  a command can be an app, a folder, a link, an AppleScript, a macOS Shortcut,
  or saving the captured text as a note.
- **Timer and stopwatch.** Preset lengths and a twenty-five minute pomodoro
  with a break queued after it. While it runs the notch widens into a strip
  with the count — click it to open the panel. Time is measured from the moment
  you start it, so it stays accurate even if the lid was closed.
- **System load.** CPU, memory and disk with fill bars. Click any reading
  to open Activity Monitor.
- **Obsidian.** Notes sync with your vault: yours live in a subfolder inside
  it and are edited from both sides, while the rest of the vault feeds search
  and the model's context. The model finds links between notes by meaning
  rather than by shared words, and writes them into the files as real
  `[[links]]` visible in the graph. All of it is off by default, and you name
  the folder yourself.
- **Weather and power.** An icon with the temperature in the panel's corner,
  chips when the weather changes or the charger is plugged in.
- **Teleprompter.** Text right under the notch — where the camera is — with
  formatting and auto-scrolling. Read from mid-screen and you look past the lens.
- **A cup of coffee.** A button next to the weather: while it is on, the screen
  neither sleeps nor locks. Clicking it opens the choice of limit right in the
  notch — half an hour, an hour, ninety minutes, two hours or no limit; the
  countdown is there too. While the cup is on, the notch stays widened: the
  icon on the left, the time left on the right — and a click leads straight
  back to the choice of limit. The cup is in quick access too, as a circle
  under the notch.
- **Keyboard cleaning.** A button next to the cup and a circle in quick access
  lock the keyboard for 30, 60 or 90 seconds — wipe it without typing anything.
  The mouse keeps working: the notch shows a countdown and an "Unlock" button.
  Requires Accessibility access.
- **Several displays.** The "Screens" setting: the island only on the screen
  with the notch, on the screen under the cursor, or on all of them. Screens
  without a notch draw nothing at rest, and in "All screens" mode a thin strip;
  hovering it opens the island there.
- **Pinning and recording retention.** Up to three notes can be pinned and stay
  at the top of the list; the home screen has a "Pinned notes" tile. Meeting
  recordings can be kept forever or for 60, 30, 14, 7 days or one day — the
  note text stays. A single recording can be marked "Keep this recording".
- **Checklists.** In a note, `[] ` at the start of a line or a button in the
  formatting bar starts a checkbox item; a click checks and strikes it through,
  Enter continues the list. In Obsidian and exports they are plain `- [ ]`.
- **Weather under the notch.** When the weather changes, rain drips from the
  notch, snow falls, a blizzard swirls, lightning flashes, the sun pops up, clouds drift out —
  and on windy days they rush past. A few seconds of pixel art; turned off
  with "Animate weather changes".
- **A cat in the notch.** When the notch has nothing to show, a pixel loaf cat
  runs out: follows the cursor, swishes its tail, sleeps, runs upside down along
  the edge, chases a ball of yarn, swears and shakes its fist, smokes, blows
  a kiss, spins after its tail, hunts the cursor and puts on shades. How often
  it comes out is up to you: every 2–4, 5–10 or 20–40 minutes. It stays away
  while a window is full screen, with Reduce Motion or in Low Power Mode; turn it
  off with "Liven up the notch".

- **Updates itself.** Once a day the app asks GitHub whether a newer version
  exists and downloads it in the background. When it is ready, a pill appears
  in the notch with a button: one tap installs the update and restarts the app.
  What was downloaded is checked against the very signature the running app
  carries, so granted permissions survive the update and you never clear
  quarantine again. The check can be turned off.

The interface is in Russian, English and Chinese — by default it follows the
system.

- **Look.** The panel below the notch is made of glass: the wallpaper shows
  through it while the notch itself stays black — the island doesn't float
  above the screen, it flows out of the hardware. A slider sets how
  transparent it is; all the way right brings back the solid black notch.
  Glass needs macOS 26; on earlier ones the app looks as it did.
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

- **Updates** — once a day the app asks github.com whether a newer version
  exists and downloads it in the background. Nothing but the request itself
  leaves your Mac. The check can be turned off in Settings.
- **Weather** — coordinates rounded to a hundredth of a degree (about a
  kilometre) go to open-meteo.com. You need not share your location at all: name a city in
  Settings or on the permissions step of the welcome screen, and location
  access is never requested — only the name you typed leaves the machine.
- **Model prompts** go to the address set in Settings. By default that is
  Ollama on your own machine; if you point it at a server of yours, they go
  there and nowhere else.
- **News digest** — search queries for your topics go to Google News
  (news.google.com). The model from Settings picks and summarises the news.
  It can suggest topics from your note titles — only when it runs on your
  own machine; a cloud model never sees them.
- **Site tracking** — the pages you add are opened by a built-in browser,
  just as if you opened them yourself. The page text goes to the model from
  Settings.
- **Notes** live in the app's own file. They go nowhere else; with "search
  notes" on, their text is sent to the same model that answers questions.
- **Embeddings for note links** are computed by the model whose address is
  set in the settings. With Ollama on your own machine nothing leaves it;
  point it at a cloud provider and your note text goes there. Link finding
  is off by default.
- **The Obsidian vault** is your own folder on disk: the app reads it and
  writes into its own subfolder inside. Nothing leaves your machine, and the
  whole integration is off by default.
- **Clipboard history and the shelf** stay local: history in the app's own
  file, the shelf as links to your own files.

## Requirements

- A MacBook with a hardware notch. The app does not show up on external
  displays.
- macOS 14 or newer. Glass in the notch needs macOS 26; below that the notch is black.
- Command Line Tools to build.
- [Ollama](https://ollama.com) for model prompts. You do not install it
  yourself: the app downloads and installs it, then offers models that suit
  your machine. Your own OpenAI-compatible server or a cloud key works too —
  see “Advanced” in the settings.

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
