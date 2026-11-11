# Rafiq — guide for AI coding agents

Rafiq (رفيق, “companion”) is a native macOS app (`NotchBuddy/`); `windows/` is the Tauri version for Windows and Linux. Rafiq, a small animated dome with a golden crescent living in the MacBook notch, shows AI coding agent sessions (Claude Code, Gemini CLI, Antigravity and more) and a few integrations, lets the user approve, answer, chat and drop files from the notch, and shows prayer times. It is built on the MIT code of Coucou (github.com/Louis-CFM/coucou) and is growing into an all-in-one companion: AI agent, cyber, news and daily life.

## Where things are
- `NotchBuddy/Sources/App/` — Mac-only Swift code. `NotchBuddy/Sources/CoucouKit/` — code shared with the iPhone app (the companion's BotEngine, look and outfits, pills, diff, models). `NotchBuddy/Sources/Phone/` — iPhone app (`CoucouPhone` target), with its widgets in `Sources/Widgets/` and the expanded approval notification in `Sources/NotificationContent/`. `NotchBuddy/Resources/sounds/` — the 29 WAV sounds (scripts/make-sounds.py). `NotchBuddy/project.yml` — XcodeGen project (never edit the `.xcodeproj` by hand).
- `NotchBuddy/Sources/CoucouKit/PillCatalog.swift` — single source of truth for all declared pills (workspace tools, agents, AI providers, services). Every pill ID, color, category and subtitle lives here.
- `docs/SPEC.md`, `docs/INTEGRATIONS.md` — behaviour, views, states, integrations (in French).
- `NotchBuddy/Sources/CoucouKit/RafiqLook.swift` and `windows/src/mochi/look.ts` — the companion's silhouette and colours, in one place. `scripts/make-icons.py`, `scripts/make-sounds.py`, `scripts/make-android-vectors.py` — the icons, sounds and Android vectors, generated.
- `windows/` — the Tauri app for Windows and Linux: Rust in `src-tauri/`, TypeScript in `src/`, the `coucou-hook` relay in `hook/`. `windows/README.md` lists what differs from the Mac.
- `docs/*.html` — the GitHub Pages site (privacy, terms, support).
- `relay/` — the Rafiq relay, a stateless Cloudflare Worker that forwards the iPhone Live Activity pushes (it holds the APNs key, which must never ship in an app). See `relay/README.md`.

## Build
```
cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build
```
To run it day to day on the Mac (signed, iPhone link, permissions kept across builds): `./scripts/dev-install.sh` — it installs the only Rafiq in /Applications and removes the copies earlier builds left.
Windows and Linux: `cd windows && npm install && npm run tauri dev`

## Rules
- Swift 6, SwiftUI + AppKit. No third-party dependencies unless truly unavoidable. The character is drawn in code (`Canvas` + `TimelineView`), no Rive/Lottie/images.
- Secrets live in the Keychain, never on disk or in git.
- No telemetry. Network calls only to services the user configured.
- Never block Claude Code: if the app doesn't answer, the hook exits immediately.
- Never overwrite `~/.claude/settings.json`: dated backup, merge, show the diff, write only after the user confirms.
- Never send an email or approve a Claude Code or Codex permission without an explicit click.
- Performance: 0 % CPU when the island is hidden.
- Keep the bundle identifiers `com.edra3k.rafiq` (Mac) and `com.edra3k.rafiq.ios` (iPhone): Keychain items, preferences and permissions depend on them.
- Never restyle what already ships (pills, cards, Settings, chat…) without being asked: existing views stay as they are in `main`.
- Pill IDs are stable contract values (Keychain, UserDefaults, hook routing): never rename an existing pill ID.
- New views follow the existing app style.
- Never bring back Coucou’s name, its Mochi character, its icon or its sounds (they are Louis Raillé's, see LICENSE-ASSETS.md). The companion's look changes only in `RafiqLook.swift` and `look.ts`; icons and sounds only through their scripts. Internal names that still say Coucou or Mochi (`CoucouKit`, `MochiConst`, `coucou-hook`, pill IDs…) are code, not brand: rename them only in a dedicated change, everywhere at once.
- Every release adds its CHANGELOG.md section, a row in the README Versions table, and commits the regenerated Info.plist with the new version.
- Every release also adds its What's new, shown once in the notch or the island after Rafiq updates itself: an entry for the new version in `NotchBuddy/Resources/whats-new.json` (Mac, the 16 languages) or `windows/src/whats-new/whats-new.json` (Windows and Linux, the 14 languages). 1 to 4 items picked from the CHANGELOG section, each with an icon from `scripts/test-whats-new.py`, a short title and one line, translated in every language. `python3 scripts/test-whats-new.py` checks it; CI and `release.sh` fail without it.
