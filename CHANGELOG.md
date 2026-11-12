# Changelog

## Unreleased

- **Details, rebuilt** — the session's Details view shows what you asked and what the agent answered, every step with its tool, its duration and, on a click, the whole command (reads that follow each other folded into one line), the files changed by their short path (a click opens the diff), the guard as one bar, the model and the length of the turn, and Terminal, Last diff, Folder, Copy and Read aloud. ‹ › go back through the last five turns.
- **Answer the agent from the notch** — a field under Details carries on the same Claude Code conversation in the background (`claude -p --resume`, the session's own folder), for terminal, VS Code, Cursor and Claude app sessions. Its approvals still wait on their card. The iPhone's instructions now use the same path.
- **More in Details** — while a turn runs: Stop (a reply Rafiq started stops at once; a turn of a terminal or the Claude app opens it, to stop it there), the tokens of the turn, and a request waiting for that session shown right there with its whole command and the same Deny, Allow and Allow with a net (nothing answered without a click). Once done: one-click replies (Continue, Run the tests, Commit and push, Explain what you did; + to add yours, right-click to remove), a microphone in the reply field, and the share of the Claude plan the turn used.
- **"Hey Rafiq, tell Claude to…"** — with no project named, it carries on the Claude Code conversation that ended last (within two hours) instead of starting a new one.
- **The Claude app's sessions stay** in the notch after a turn, so their Details and reply stay at hand.

## 0.7.0 — 2026-11-12

Rafiq starts from the code of Coucou 0.6 (MIT) and becomes its own app.

- **A new companion** — Rafiq is a small ivory dome that rises to a point, like a lantern's cap, with a golden crescent on top and warm golden cheeks. Same life as before (he looks at your cursor, reacts, sleeps, dances), a new look, everywhere: the island, the pills, the greeting, the desktop, the iPhone and Android.
- **New sounds** — 29 sounds made from scratch, soft kalimba and bells; the greeting is a short phrase in the Hijaz mode.
- **New icons** — the companion in a night sky, for the Mac, the iPhone (with its colour variants), Windows, Linux and Android, and a new menu bar icon.
- **« OK Rafiq »** — the voice wake phrase, with the ways speech recognition writes it (Rafik, Rafique, Rafeeq…).
- **Prayer times** — turn on the Prayer pill and the notch shows the next prayer and how long until it, the sun on its arc and the five times of the day; click a time once you have prayed. A reminder comes a few minutes before each prayer (10 by default), and at the time itself the island opens, Music and Spotify pause, and your own adhan plays if you put an adhan.mp3 in the sounds folder. 49 cities or any coordinates, 21 calculation methods, Hanafi Asr, high-latitude rules, per-prayer offsets, the Hijri date and the qibla in Settings. Calculated on the Mac, no network.
- **Pomodoro** — the work and rest timer, under its plain name.
- **The agent guard** — every action an agent asks for is rated (read only, edits files, network, deletes, force push, secrets, runs downloaded code…) with one line saying what it can do, on the approval card, the session card and the header's shield. It only informs: every decision stays your click.
- **A notch that speaks without opening** — a coloured halo under the notch (an agent waiting, an error, a prayer coming, a task done) and, on the compact island, a word on each side: the next prayer on the left, the agents' news on the right. The open island shows the next prayer in its header and the day's prayers on an arc above the pills.
- **Opens on hover, folds when you leave** — on by default; the island folds a few seconds after the pointer leaves (2 to 15 s, 3 by default), with a line that empties until it does. Coming back cancels it.
- **Quiet while you pray** — from a prayer's time, for 15 minutes, no sound and no island opening; then a card says what finished, what waits for you and what failed. Nothing is answered for you.
- **The evening brief** — once a day, after Isha (21:00 without the Prayer pill): sessions, files, lines and prayers of the day.
- **Secrets spotted** — a key, a token or a password an agent writes into a file brings a card with the masked value and a prompt to copy for Claude.
- **Vulnerability watch (opt-in)** — when a session starts in a project, the exact versions in its lockfiles (npm, Cargo, pip) are checked against OSV.dev, once a day; known vulnerabilities come with their fixed versions.
- **Ramadan** — the notch counts down to the iftar and the end of the suhur, with the day of the month.
- **A tidier home view** — the prayer shows once (the header chip and the Prayer pill step aside while the strip is up), with its five real times, a tick on each prayer done, a countdown at night, the short Hijri date in Arabic and the qibla. The session card says where and for how long it runs, shows this turn's steps as dots coloured by the guard, the lines and files changed, the project's branch with its unpushed commits and changes, and three shortcuts: Terminal, Last diff, Folder.
- **Tasbih** — the beads on the prayer strip (or the card after a prayer) count SubhanAllah 33, Alhamdulillah 33, Allahu akbar 34 with a click.
- **Plan ring** — with the Claude plan gauge on, its share used circles Rafiq on the home view.
- **Verse of the day** — one short verse, in Arabic with its meaning, the first time the island opens each day; it never holds the island open.
- **Claude Code by its name** — the pill every Claude Code hook reaches is called Claude Code (it was "VS Code"), and Claude Desktop can be the main pill.
- **Allow with a net** — on a high-risk approval in a Git project, Rafiq first saves the project's files (a snapshot under refs/rafiq/nets, your branch, index and stash untouched), then allows. "Back to the net" on the session card restores them, after a confirmation.
- **Prompt injection watch** — what a tool brings back to the agent (web pages, files, command output) is read for text aimed at AI agents: orders to ignore instructions, to hide things from you or send secrets away, text hidden in invisible characters. A red card names the source.
- **Trap file** — a fake key in ~/.config/rafiq/.env.production that no tool of yours needs; an agent opening it, or its key showing up in what an agent reads, brings a red card.
- **"Why?"** — with Ollama or LM Studio set up, the approval card can ask the local model what the command does and what could go wrong. Nothing leaves the Mac.
- **While you were away** — back after 10 minutes or more, a card says what your agents finished, what waits and what failed.
- **Breaks and voice** — after two hours at the screen, Rafiq yawns and suggests a break (and wudu before a near prayer); optionally, he says when a session is done.
- **Rafiq رفيق** — the name in both scripts (the Arabic in gold kufi) in the window's sidebar, Settings, the menu bar menu and the About panel; when the island folds back, "رفيق" is written beside Rafiq for a moment. The menu bar icon wears its crescent.
- **Today** — the Rafiq window opens on the day: salam, the date in both calendars, prayers, sessions, lines, security alerts, the next prayer, the evening brief's time and the verse of the day.
- **Home server** — a Server pill for Proxmox: CPU, memory and storage, the VMs and containers, with Start, Stop, Snapshot and Back to the snapshot (each asks first; actions use a second API token). Labs are the guests tagged "lab". The certificate is remembered on first use and must match afterwards. A storage at 90 % brings a card. The model loaded in Ollama shows when its address is set.
- **Agents on the server, in the notch** — Rafiq keeps an SSH tunnel to the server (your own ssh config and keys, nothing listening on the network) so Hermes, in the terminal or as a gateway, and Claude Code on the server reach the notch: sessions, steps, approvals, the guard and the injection watch. "Install on the server" copies the relay and the Hermes plugin and enables it (dated backup of config.yaml first). For Hermes, "Allow with a net" takes a Proxmox snapshot of its VM.
- **Server watch** — an SSH login from an address that is not private or known, twenty failed logins from one address, or a port newly open to the network, bring a red card.
- **Ask Hermes or Claude** — the ✦ tab of the island, "Hey Rafiq, ask Hermes to…", the iPhone or the Watch: type or say a task. Auto picks who — Hermes for the server, the home and the local models, Claude Code for code (in the project the task names), the chat for a plain question. It runs in the background, no terminal window: Hermes on the Mac or on the server, Claude Code with your hooks. The card shows its steps, then the answer, said aloud like an assistant (Settings → Agents), with Read aloud, Copy and Hand to Claude. A risky command still waits for your click, and Rafiq says so aloud.
- **Apple Watch** — a Watch app: the next prayer, the agents at work, a request to allow (two taps) or deny, the latest tasks and "Ask" by voice; complications for the next prayer and the agents at work. It goes through the iPhone, never straight to the Mac.
- **iPhone** — the Ask card on the home screen with the next prayer, the tasks and their answers (read aloud when Rafiq is open).
- **Your own identifiers** — `com.edra3k.rafiq` on the Mac, `com.edra3k.rafiq.ios` on the iPhone, `com.edra3k.rafiq.android` on Android; updates, links and support point to github.com/Edra3k/Rafiq.

Coucou's own history is in [its repository](https://github.com/Louis-CFM/coucou/blob/main/CHANGELOG.md).
