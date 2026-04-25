# OBS Pomodoro Timer

## Setup

1. go to **Tools > Scripts** and add `pomodoro.lua`.
2. Create one or more Text (GDI+) sources in your scene - the script writes to these by name.
3. In the script settings, enter your source names:
   - **Timer Source** — displays the countdown and timestamps (e.g. `FOCUS • 24:58 • Started 09:00 • Ends at 09:25`)
   - **Status Source** — displays the current mode label (e.g. `Focus`, `Short Break`)
   - **Session Label Source** — displays session progress (e.g. `Session 2 of 4`)

## Settings

**Timer**
- Focus, short break, and long break durations in minutes
- Sessions before long break — how many focus sessions before a long break
- Daily session goal — set a number (e.g. 8) and the session counter counts toward that instead of resetting each cycle. Set to 0 to disable.

**Display**
- Toggle mode label, session counter, start time, and end time on or off
- End time inline — puts everything on one line; turn off to stack on separate lines
- 24h clock toggle
- Separator character between elements

**Notifications**
- Sends a desktop notification each time a session or break ends. Works on Windows, macOS, and Linux. Toggle with "Enable desktop notifications".

**Sounds**
- In each Focus, Short Break, Long Break session, upload a sound file to play a sound at the end of each segment.

**Scene switching**
- **Auto-start on Scene** — starts the timer automatically when you switch to a named scene
- **Switch scene on Break** — switches to a named scene whenever a break begins
- **Switch scene on Focus** — switches to a named scene on focus

## Controls

Buttons are available in the script panel. You can also bind hotkeys under **File > Settings > Hotkeys** — search for "Pomodoro".

| Action | What it does |
|--------|--------------|
| Start | Resets session count and starts the first focus block |
| Pause | Freezes the timer mid-session |
| Resume | Picks up from where you paused |
| Reset | Stops everything and clears the display |
| Skip | Immediately ends the current segment and moves to the next |
