# Trunook

[Русский](README.md) · **English** · [简体中文](README.zh.md)

The MacBook notch as a workplace: music, meetings, clipboard, files, notes
and your own language model — right where your eyes already are, instead of
ten windows on top of your work.

![The notch at work](docs/demo.gif)

**Everything runs on your own Mac.** The model, speech recognition, notes
and clipboard history never leave it. What does leave, and where it goes, is
spelled out in [its own section](#what-leaves-your-mac) — down to the last
request.

---

## Contents

- [How the notch works](#how-the-notch-works) — four states and the gestures
- [The home screen](#the-home-screen) — the tiles it is built from
- [Features](#features) — grouped
- [Keyboard shortcuts](#keyboard-shortcuts)
- [What leaves your Mac](#what-leaves-your-mac)
- [Installation](#installation) · [Requirements](#requirements) ·
  [Limitations](#limitations) · [Development](#development)

---

## How the notch works

There are four states, and you move between them by hand, without aiming at
buttons.

| What you do | What happens |
|---|---|
| Hover | Mini view: what's playing and when the next meeting is |
| Click or swipe down | The whole home screen |
| Swipe up | Collapse it again |
| Press and hold | A ring: circles of every function fan out — lead your hand and let go |
| Right-click | The same ring, but it stays: click a circle, click past it to close |

![Gestures](docs/gestures.png)

A collapsed notch still speaks: while a timer runs it shows the count, while
the coffee cup is on it shows the time left, and before a meeting it counts
down to it. Clicking that strip takes you straight to its panel.

**By keyboard and out loud.** Every panel has its own shortcut, Settings is
walkable with Tab, and icon captions are read by VoiceOver. The system's
Reduce Motion and Reduce Transparency settings are respected.

---

## The home screen

The expanded notch is built like a phone's home screen — from tiles. A tile
shows the essentials and does the essentials: pause, start the timer, join
the meeting. Clicking it opens the full panel.

Almost everything the app can do has a tile — from music, meetings and the
day timeline to water, system load, notes and the shelf, plus shortcuts for
voice, dictation and the teleprompter. Sizes run from 1×1 to 4×2 on
a four-column grid. Pick the tiles, their order and size in Settings →
**Home screen**: drag them with the mouse.

The commands tile stands a little apart: it holds up to four of your own
commands — one in the 1×1 size. Select text in another window, click
"Translate" on the tile, and the model's answer opens right in the notch.

---

## Features

### The day and time

- **Calendar.** The month with week numbers and the chosen day's plans right
  in the notch; clicking an event edits it in place — time, place,
  description, participants and the link. The day shows as a list or as
  a timeline, and a button in the wing switches one for the other: on the
  timeline block height is duration, gaps show as gaps, overlapping meetings
  stand side by side in columns, and a "now" line runs across. Before
  a meeting the notch warns you ahead of time and counts the minutes down.
  Today's tasks are picked up from Things 3.
- **Online meetings.** While a call is running, hovering gives you the
  microphone, camera, screen sharing, raise hand and leave — in Telemost,
  Google Meet, Zoom and Teams in the browser, and in the Telemost and Zoom
  apps as well (Zoom gives microphone, camera and sharing). The record button is there too: it captures
  both you and the others, speech is turned into text on your own Mac and
  becomes a note — a title, a summary and the tasks as a separate list, with
  the recording attached. Recording needs macOS 26 and is off by default.
- **Timer and stopwatch.** Time is chosen on a dial with tick marks; there
  is a 25-minute pomodoro with a break queued after it. While it runs the
  notch widens into a strip with the count; the count runs from the moment
  you started, so it never falls behind, even if the lid was closed.
- **Countdown.** A tile with your own event and how long is left. When it
  arrives — a pill and confetti from the notch.

### Text, files and notes

- **Clipboard history.** Everything you copied within reach: paste by number
  from the keyboard, and in the open list ↑↓ walk the rows while Enter
  pastes.
- **A shelf for files.** Drop files on the notch and they land on the shelf;
  drag one into any window and the file moves there. Over the notch you can
  drop a file straight into a zone: zip or unzip it, put an iCloud link on
  the clipboard, send it to the Trash.
- **Notes.** A multi-line field with formatting and checklists; the model
  comes up with the title. A list with word search, export to Markdown, and
  up to three notes pinned to the top. Someone else's text gets in without
  retyping: the selection from any window and whatever you copied both go
  into notes with their own shortcuts. Turn on Obsidian sync and your notes
  live in a subfolder of your vault, editable from both sides, while the
  model writes meaningful connections into the files as real `[[links]]`.
- **Teleprompter.** Text right under the notch — where the camera is — with
  formatting and auto-scroll: reading from mid-screen means looking past the
  lens.

### The model on your own Mac

- **Ask and read the answer in the notch.** Enter sends the question, the
  answer is written right under the notch — copy it or paste it into the
  active window; while it is being written, the send button stops it. Ollama installs itself: the app downloads and starts it,
  and suggests models your machine can carry — a light, a medium and
  a powerful one for conversation, plus a separate one for notes. The
  fitting one is marked "recommended", one button installs the pair.
- **Your own server or the cloud.** Another local server with an OpenAI
  interface (LM Studio, llama.cpp, vLLM, Unsloth Studio) or a cloud one —
  OpenAI, Anthropic, Gemini, OpenRouter, Groq, DeepSeek. Their addresses
  fill themselves in; anything else connects as a custom provider. You can
  keep several at once, each with its own address, key and model.
- **An assistant that acts.** If you allow it, the model does not only
  answer but does: sets a timer, looks at your schedule and the weather,
  creates an event, a reminder or a note. Reading happens at once; writing
  only after a "Create / Cancel" card in the notch itself. An at sign in the
  question opens a list of meetings and notes: what you pick goes into the
  question as a word — "@Standup move to Tuesday 15:00". It also answers
  questions about the app itself — "what can this thing do?", "how do I set
  up the news digest?" — and names the settings section where it is switched
  on. Off by default; needs a model that can call tools.
- **Voice and dictation.** You can ask out loud: the panel does not open —
  the notch shivers and glows, blue while listening, the model's colour
  while thinking — with a volume meter on the side. The answer is read aloud
  as the model writes it; when it finishes the notch listens again, so
  a follow-up needs no second gesture. The microphone in the question row
  puts speech straight into the field as you speak — a whole note is
  dictated the same way. Speech is recognised on your own Mac.
- **Commands.** They capture the selection in another window and open the
  conversation: the capture sits in a pill above the field, the commands sit
  below it. There can be any number of them, and each request has its own
  model — shown on the right of the row, changed with Tab. A command is not
  only a request to the model: it can be an app, a folder, a link, an
  AppleScript, a macOS Shortcut, or saving the capture to notes. The first
  nine run straight from the keyboard, and the favourites can go onto the
  home screen as a tile.

### What's going on around you

- **Music.** Track, artwork, playback controls and a progress line along the
  island's outline. Works with any player — the data comes from the system.
  Swipe with two fingers to change tracks.
- **Weather and power.** An icon with the temperature in the corner of the
  panel or as a tile, pills when the weather changes and when the charger is
  plugged in.
- **System load.** CPU, memory and disk as bars; clicking opens Activity
  Monitor.
- **News digest.** Set the topics and the schedule and the model collects up
  to five main stories per topic: headline, source, time and one sentence on
  why it matters. Links come from the feed, not from the model, so it cannot
  invent an address. A digest can be saved to notes or to a file; past ones
  can be leafed through. The model can suggest topics itself.
- **Site tracking.** A link and, in plain words, what to watch: a price,
  availability, a date, the number of seats, any string. The page is opened
  on a schedule, and when the value changes the notch shows "was → now" with
  a button to the site. For numbers there are "dropped below", "rose above"
  and a threshold.

### Windows and screens

- **Window layouts.** Drag a window by its title bar to the notch and it
  shows layouts: full screen and centred at 85 per cent in the middle,
  halves, two thirds, thirds and top and bottom quarters on the sides. Drop
  the window on the one you want.
- **Several monitors.** The Screens setting: the island only on the screen
  with the notch, on the screen under the cursor, or on all of them at once.
  Screens without a notch draw nothing at rest, and in "All screens" mode
  a thin strip — hovering it opens the island there.
- **Glass.** The panel under the notch lets the wallpaper through while the
  notch itself stays black: the island does not float above the screen, it
  flows out of the hardware. Transparency is a slider; all the way right the
  notch is solid black again. Glass needs macOS 26; below that the app works
  as before.

### Taking care of yourself

- **Breaks.** Reminders to take a break, drink water and stretch — each on
  its own interval, and only time at the computer counts. The pill waits for
  an answer: done or skip. For water the checkmark also asks how much —
  a slider from 50 to 1000 ml with tick marks and a hint at the vessel — and
  from then on shows the day's total; the same number lives in the Water
  tile. There are no goals on purpose: you are not at the computer all day.
- **Coffee cup.** While it is on, the screen neither dims nor locks. The
  duration is chosen in the notch — half an hour, an hour, an hour and
  a half, two, or no limit; while the cup is on, the time left shows in the
  notch itself.
- **Keyboard cleaning.** Locks the keyboard for 30, 60 or 90 seconds — wipe
  it without typing anything. The mouse keeps working: the notch shows the
  countdown and an Unlock button. Needs Accessibility access.

### Small things that make you smile

- **A cat in the notch.** While the notch has nothing to show, a pixel loaf
  of a cat runs out from under it: it watches the cursor, wags its tail,
  sleeps, runs upside down along the edge, chases a ball of yarn, swears,
  smokes, blows a kiss, spins after its own tail, hunts the cursor and tries
  on sunglasses. It also catches a mouse, suns itself
  under a beach umbrella with a smoothie — the notch shines like the sun
  meanwhile — and chases a bird. How often is a setting: every 2–4, 5–10 or 20–40 minutes.
  It stays away from full-screen windows, Reduce Motion and Low Power Mode.
- **Weather under the notch.** When the weather changes, rain drips from the
  notch, snow falls, a blizzard blows, lightning strikes, the sun comes up,
  clouds drift out — and in wind they race past. A few seconds each, and it
  can be turned off.

---

## Keyboard shortcuts

All of them on ⌃⌥ — a pair macOS uses for nothing. Every one can be changed
in Settings or right in the welcome window.

| Shortcut | What it opens |
|---|---|
| ⌃⌥C | Capture the selection and ask the model |
| ⌃⌥N | The home screen |
| ⌃⌥V | Clipboard history |
| ⌃⌥S | The shelf for files |
| ⌃⌥D | Mini calendar |
| ⌃⌥T | Timer and stopwatch |
| ⌃⌥M | System load |
| ⌃⌥F | News digest and site tracking |
| ⌃⌥P | Teleprompter |
| ⌃⌥Z | New note |
| ⌃⌥⇧Z | The selected text straight into notes |
| ⌃⌥R | Dictate a note |
| ⌃⌃ | Ask by voice |
| ⌃⌥1 … ⌃⌥9 | Run commands directly |
| ⌃⇧1 … ⌃⇧9 | Paste a clipboard entry by number |

---

## What leaves your Mac

In short: **by default, only the update check**. Everything else you switch
on yourself, and here is what goes out then.

| What | Where | By default |
|---|---|---|
| Update check | github.com | on, can be turned off |
| Weather | open-meteo.com, coordinates rounded to about a kilometre — or just a city name | off |
| Requests to the model | wherever the address in Settings points: by default Ollama on this same Mac | local |
| Vectors for note links | to the same model; with a local one nothing leaves at all | off |
| News digest | search queries for your topics — to news.google.com | off |
| Site tracking | the pages you added yourself | off |

Notes, clipboard history and the shelf stay on the machine: notes and
history in the app's own files, the shelf as links to your files. The
Obsidian vault is read from disk and written to in its own subfolder —
nothing leaves it.

The text of your notes goes to the model in two cases: when "search my
notes" is on, and when the assistant is allowed to look into them. With
a local model it never leaves the Mac.

---

## Installation

### Build from source — the reliable path

```bash
git clone https://github.com/TruDevLab/Trunook.git
cd Trunook
make cert      # once: a self-signed certificate
make install   # build, sign, put it in /Applications
```

You need the Command Line Tools (`xcode-select --install`). Xcode is not
required.

### From a ready-made image

Download the `.dmg` from [releases](../../releases), drag the app into
Applications and clear the quarantine:

```bash
sudo xattr -r -c /Applications/Trunook.app
```

### After that it updates itself

Once a day the app asks GitHub whether there is a new version and downloads
it in the background. When it is ready, a pill appears in the notch with
a button: pressing it installs the update and restarts the app. What was
downloaded is checked against the same signature you signed it with — so the
permissions you granted survive the update, and the quarantine does not have
to be cleared again. The check can be turned off.

---

## Requirements

- **A MacBook with a hardware notch.** The island lives in it; it can be
  shown on external monitors with the Screens setting, but there is no notch
  there.
- **macOS 14 or newer.** Glass needs macOS 26, and so does conversation
  recording; below that the app works without them.
- **To build** — the Command Line Tools.
- **For the model** — [Ollama](https://ollama.com), which the app installs
  itself. Your own OpenAI-compatible server or a cloud key work too.

The interface speaks Russian, English and Chinese — by default whichever the
system does.

---

## Limitations

### There is no Apple signature

The project has no paid developer account. On someone else's Mac Gatekeeper
will not let the app through (`spctl -a` says `rejected`), notarisation is
impossible and the App Store is out. Hence the installation order above:
building from source is simpler — the system asks nothing about what you
signed yourself — while an image needs the quarantine cleared by hand.

### The helper lives in Apple's namespace

macOS hands out track information through the private
`MRMediaRemoteGetNowPlayingInfo`, and since macOS 15.4 an ordinary process
gets nothing back: access stayed with processes whose identifier starts with
`com.apple.controlcenter.`. That is why the XPC helper is called
`com.apple.controlcenter.TrunookHelper`.

The trick gives no access to anyone else's data — it lifts the restriction
on reading the state of your own player. Apple can close the loophole in any
update: then only track titles would disappear, and the workaround itself is
isolated in a separate service.

---

## Development

The architecture, the technical findings and the debugging tools are in
[DEVELOPMENT.md](DEVELOPMENT.md) (in Russian).

```bash
make run    # build, install, launch
make test   # tests
make dmg    # the image
```

## License

[MIT](LICENSE).
