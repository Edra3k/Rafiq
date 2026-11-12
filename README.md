<div align="center">

<img src="docs/media/icon.png" width="120" alt="L'icône de Rafiq : un petit dôme ivoire au croissant doré, dans un ciel de nuit">

# Rafiq

**Ton compagnon (رفيق) qui vit dans l'encoche du Mac — ou en haut de l'écran sur Windows et Linux.**
Il veille sur tes agents IA, te rappelle l'heure de la prière, et deviendra ton outil tout-en-un :
agents, cyber, actus et quotidien.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![iOS 18+](https://img.shields.io/badge/iOS-18%2B-black?logo=apple)
![Android 11+](https://img.shields.io/badge/Android-11%2B-3DDC84?logo=android&logoColor=white)
![Windows 10/11](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-AppImage%20%7C%20deb%20%7C%20rpm-FCC624?logo=linux&logoColor=black)
![Code: MIT](https://img.shields.io/badge/code-MIT-green)

</div>

---

## Le compagnon

Rafiq est un petit **dôme ivoire qui s'élève en pointe**, comme le chapeau d'une lanterne, avec un **croissant doré** au sommet et des joues qui s'allument comme une flamme. Il sort de l'encoche, te salue sur un air en mode *Hijaz*, suit ton curseur des yeux, s'endort quand tout est calme et te prévient au bon moment.

Tout est dessiné en code (`NotchBuddy/Sources/CoucouKit/RafiqLook.swift`, `windows/src/mochi/look.ts`), les sons sont synthétisés (`scripts/make-sounds.py`) et les icônes générées (`scripts/make-icons.py`) : rien n'est repris de Coucou.

## Ce qu'il sait faire

- 🕌 **Heures de prière** — la prochaine prière et un compte à rebours dans l'encoche, le soleil sur son arc, les cinq prières du jour à cocher, un rappel avant chacune ; à l'heure, l'île s'ouvre, Musique et Spotify se mettent en pause et ton propre adhan peut jouer. 21 méthodes de calcul (UOIF, Muslim World League, Umm al-Qura, Kemenag, Diyanet…), Asr hanafite, hautes latitudes, décalages pour coller à ta mosquée, date de l'Hégire et qibla. Tout est calculé sur le Mac, rien n'est envoyé.
- 🤖 **Tes agents IA en direct** — Claude Code, Cursor, Codex, Gemini CLI, Antigravity, Copilot CLI, OpenCode, Amp et d'autres : ce qu'ils lisent, modifient et lancent, étape par étape.
- ✅ **Approuver et répondre depuis l'encoche** — Autoriser / Refuser / Toujours, les questions de Claude avec leurs choix, sans revenir au terminal.
- 💬 **Discuter** avec Claude, Gemini, OpenAI, DeepSeek, Qwen ou un modèle local (Ollama, LM Studio), avec ta clé ou ton abonnement.
- 🗣️ **« OK Rafiq »** — parle-lui, il agit et cherche sur le web.
- 🎙️ **Dictée** — garde une touche enfoncée, parle, relâche : le texte est collé là où tu écris (Parakeet hors ligne sur Apple silicon).
- 📝 **Prise de notes d'appels**, ✉️ **Mail dans l'encoche**, 🎧 **Spotify et Musique**, ⏱️ **Pomodoro**, 📈 **portefeuille crypto**, 🔌 **intégrations** (GitHub, Stripe, Vercel, Notion, n8n, Cal.com, Resend, WhatsApp).
- 📱 **Sur ton téléphone** — iPhone (Live Activity, widgets, Siri) et Android (approbations, widgets), reliés à ton ordinateur.
- 🔒 **Privé** — pas de télémétrie, pas de compte ; les clés restent dans le Trousseau, le Gestionnaire d'identifiants Windows ou le Secret Service.

## La suite

Rafiq va grandir en compagnon tout-en-un :

- **Agent IA** — un vrai assistant qui agit pour toi (fichiers, mails, agenda, web).
- **Cyber** — veille de vulnérabilités (CVE), alertes de fuites, état de tes services exposés.
- **Actus** — un brief du matin et les nouvelles qui t'intéressent, dans l'encoche.
- **Quotidien** — rappel d'eau, to-do avec rappels, historique du presse-papiers, paroles synchronisées.

### Compiler depuis les sources

**macOS** — requirements: macOS 15+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/Edra3k/Rafiq.git
cd Rafiq/NotchBuddy
xcodegen
open NotchBuddy.xcodeproj   # then ⌘R
```

**Windows** — requirements: [Rust](https://rustup.rs), Node 20+, MSVC build tools.

```powershell
git clone https://github.com/Edra3k/Rafiq.git
cd Rafiq/windows
npm install
npm run pack                # installer lands in windows/release/
```

**Linux** — requirements: [Rust](https://rustup.rs), Node 20+, and the WebKitGTK,
gtk-layer-shell and appindicator development packages (Debian/Ubuntu names below).

```bash
sudo apt install build-essential pkg-config \
  libwebkit2gtk-4.1-dev libgtk-layer-shell-dev libayatana-appindicator3-dev \
  librsvg2-dev libssl-dev libdbus-1-dev patchelf \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good
git clone https://github.com/Edra3k/Rafiq.git
cd Rafiq/windows
npm install
npm run pack                # AppImage, .deb and .rpm land in windows/release/
```

On NixOS, `nix develop` gives you all of this: then `cd windows && npm ci && npm run tauri dev`.

**Android** — requirements: JDK 17 and the Android SDK (platform 35).

```bash
git clone https://github.com/Edra3k/Rafiq.git
cd Rafiq/android
./gradlew assembleDebug      # the APK lands in app/build/outputs/apk/debug/
```


Avant la première compilation Mac, mets ton identifiant d'équipe Apple dans `NotchBuddy/project.yml` (`DEVELOPMENT_TEAM`) et dans `NotchBuddy/Sources/App/MacUpdate.swift` (`teamId`). Les identifiants de l'app sont `com.edra3k.rafiq` (Mac) et `com.edra3k.rafiq.ios` (iPhone).

## Réglages

On the Mac, open Rafiq from the Dock or the menu bar: its window has every setting under **Notch** (⌘,). On Windows and Linux, click the Rafiq icon in the system tray → **Settings…**

| What | Why | Where the key goes |
|---|---|---|
| **Claude Code hooks** | live sessions and approvals | **Install hooks** — Rafiq backs up `~/.claude/settings.json`, merges its hooks and shows you the diff before writing anything |
| **Claude plan** *(macOS, GitHub build)* | Plan usage gauge in the notch header | **Install relay** in Settings → Agents → Plan usage, then enable "Show in the notch" |
| **Gemini CLI hooks** | Gemini CLI sessions in the island | **Install hooks** in Settings → Gemini CLI — backs up `~/.gemini/settings.json` |
| **Antigravity (agy) hooks** | agy sessions in the island, and *(macOS, optional)* its commands approved from the notch | **Install hooks** in Settings → Antigravity — backs up `~/.gemini/config/hooks.json`; then turn on **Approve commands from the notch** |
| **Anthropic API key** | chat and questions about files | Settings → Anthropic API · Keychain / Windows Credential Manager / Secret Service |
| **Google AI API key** *(macOS)* | chat with Google AI (Gemini) | Settings → Chat — other providers · Keychain |
| **OpenAI API key** *(macOS)* | chat with OpenAI | Settings → Chat — other providers · Keychain |
| **Ollama server** *(macOS)* | chat with local models via Ollama | Settings → Chat → Local models → **Connect** |
| **LM Studio server** *(macOS)* | chat with local models via LM Studio | Settings → Chat → Local models → **Connect** |
| **iPhone** *(macOS)* | sessions, approvals, questions and Rafiq on your iPhone | Settings → General → iPhone · your private iCloud, see [docs/IPHONE.md](docs/IPHONE.md) |
| **Android phone** *(Windows, Linux)* | sessions, approvals, questions and chat on your Android phone | Settings → Android phone · off by default, your local network only, see [android/README.md](android/README.md) |
| **Active pills** *(macOS)* | choose which tools and agents appear in the island | Settings → Active pills |
| **Flow dictation** *(macOS, GitHub build)* | hold a key, speak, the words are pasted | Rafiq → Flow → Settings · the Accessibility and Microphone permissions |
| **Parakeet** *(macOS, Apple silicon)* | offline dictation, more accurate | Rafiq → Flow → Settings → Recognition → **Download** (about 650 MB) |
| Stripe, n8n, GitHub, Vercel, Resend, Notion, Cal.com | the service pills | Keychain / Windows Credential Manager / Secret Service, all optional |
| **WhatsApp** *(macOS GitHub build, Windows, Linux; experimental)* | your WhatsApp messages in the notch or the island, and replies | Settings → Integrations → WhatsApp · a gateway on your Mac, see [WhatsApp (experimental)](#whatsapp-experimental) |

If Rafiq isn't running, the hook exits immediately: **Claude Code is never blocked.**


## Versions

| Version | Date | Ce qui change |
|---|---|---|
| [0.7.0](https://github.com/Edra3k/Rafiq/releases/tag/v0.7.0) | 12 novembre 2026 | Première version de Rafiq : le nouveau compagnon, les heures de prière, « Demande à Hermes ou Claude » avec la réponse à voix haute, le garde des agents, le serveur maison, l'app iPhone et l'app Apple Watch. Voir [CHANGELOG.md](CHANGELOG.md). |

## D'où vient Rafiq

Rafiq est construit sur le code de **[Coucou](https://github.com/Louis-CFM/coucou)**, de Louis Raillé, et de **Coucou for Android**, de Rhytam Biswas, tous deux publiés sous licence MIT. Merci à eux. Le nom, le personnage, l'icône et les sons de Coucou ne sont pas repris : Rafiq a les siens.

## Licence

- **Code** : licence MIT, voir [LICENSE](LICENSE) (qui garde, comme la licence l'exige, la mention de Louis Raillé pour le code de Coucou).
- **Nom, personnage, icône et sons de Rafiq** : voir [LICENSE-ASSETS.md](LICENSE-ASSETS.md).
