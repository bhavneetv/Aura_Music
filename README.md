# 🎵 Aura Music — Next-Gen AI Music Player

[![Flutter](https://img.shields.io/badge/Flutter-v3.27+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-brightgreen)](#-getting-started)
[![AI Engine](https://img.shields.io/badge/AI%20Engine-Groq%20%7C%20Gemini-orange)](#-ai-intelligence--features)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Aura Music** is a sleek, ultra-modern cross-platform music application built with Flutter. It combines high-fidelity audio streaming, AI-powered song and lyric interpretation, local multi-device Wi-Fi playback sync, deep link playlist sharing, Siri & Google Assistant integration, and customizable glassmorphic visuals.

---

## ✨ Key Features & Capabilities

### 🔗 Playlist Link Sharing & One-Click Importing
- **Deep Link Generation**: Generate shareable `aura://` or `aura-playlist://` deep links or web URLs (`auramusic.app`).
- **One-Click Playlist Import**: Share playlists directly to WhatsApp, Telegram, or Messages. Tapping a shared link automatically imports the full playlist into the recipient's Aura Library.
- **🟢 Spotify Playlist Importer**: Paste any public Spotify playlist URL into Aura to automatically convert and import all songs into your library.

### 🎙️ Native Siri & Google Assistant Voice Commands
- **iOS Siri Integration**: Speak naturally to Siri (*"Play Punjabi song in Aura"*, *"Play Diljit Dosanjh in Aura"*) to start playback immediately.
- **Android Media Actions**: Full Google Assistant media intent handling for hands-free voice search and playback.

### 🤖 AI Lyrics Interpretation & Summaries
- **🔤 Multi-Language Support (English, Hindi, Hinglish)**: Generate AI summaries and line-by-line lyric breakdowns in **English**, **Hindi (हिंदी)**, or casual **Hinglish** (*"Iss song mein artist ne deep feelings express ki hai..."*).
- **💡 Line-by-Line AI Lyric Explanations**: Understand hidden metaphors, mood, and storytelling behind individual lyric lines.
- **📜 Full Narrative Summaries**: Comprehensive narrative analysis covering theme, emotional progression, message, and cultural context.

### 📊 Waveform Seeking & 6 Visual Seek Bar Styles
- **On-Device Waveform Extractor**: Extract audio sample amplitudes to render interactive voice-note style waveform visuals.
- **6 Visual Progress Bar Styles**:
  1. 🎙️ **Waveform** *(Voice-Note Style)*
  2. 🌊 **Android 16 Wave** *(Stock Squiggly)*
  3. 🔘 **Material Rounded**
  4. 🐍 **Snake** *(Wavy Sine)*
  5. ⚡ **Zigzag** *(Sawtooth Wave)*
  6. 🌟 **Neon Glow** *(Pulse Shader)*

### 🎧 Multi-Device Synced Playback & Audio Routing
- **Wi-Fi Multi-Room Sync**: Discover and synchronize music playback across multiple nearby devices on the same Wi-Fi network.
- **Audio Output Routing**: Dynamically switch audio output between Built-in Speaker, Bluetooth Headphones, and AirPlay/Cast routes.

### 🎤 Synchronized Karaoke Lyrics
- **Live LRC Karaoke**: Auto-scrolling lyrics synchronized to the track position.
- **Center Sync Lock 🎯**: Keeps active karaoke lines centered on screen with customizable font scaling.

### 🎨 Skeuomorphic Player Skins & Dynamic Design System
- **4 Distinct Player Skins**:
  - 🎨 **Ultra Minimal Artwork** *(Default)*
  - 📀 **Rotating Vinyl Disc**
  - 💿 **Modern Compact CD**
  - 📼 **Classic Retro Cassette Tape**
- **Adaptive Navigation Styles**: Switch between **iOS 26 Liquid Glass**, **Android 16 Material 3**, and **Custom Floating Glass Capsule** navigation bars.
- **Custom RGB Accent Colors**: Choose from presets (Gold, Cyan, Emerald, Purple, Sunset, Crimson) or set custom RGB values.
- **Transparent Status Bar**: Fully immersive Edge-to-Edge interface with transparent status bar integration.

### 💾 Smart Offline Mode & Local Cover Art Caching
- **Offline Listening**: Download songs locally for playback without an active internet connection.
- **Cover Art Persistence**: Artwork is saved locally during download so song covers display offline.
- **Offline Queue Filter**: Queue automatically filters to display available downloaded songs when offline.

---

## 📲 Downloads & Releases

Pre-built binaries for all major platforms are available on the [Releases](https://github.com/bhavneetv/Aura_Music/releases) page:

| Platform | Format | Status |
|---|---|---|
| **Android** | `.apk` | [Download Release](https://github.com/bhavneetv/Aura_Music/releases) |
| **iOS** | `.ipa` | [Download Release](https://github.com/bhavneetv/Aura_Music/releases) |
| **Windows** | `.zip` (`.exe`) | [Download Release](https://github.com/bhavneetv/Aura_Music/releases) |
| **macOS** | `.zip` (`.app`) | [Download Release](https://github.com/bhavneetv/Aura_Music/releases) |
| **Linux** | `.tar.gz` | [Download Release](https://github.com/bhavneetv/Aura_Music/releases) |

---

## 🛠️ Build & Run from Source

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.27 or newer)
- [Dart SDK](https://dart.dev/get-dart)

### 1. Clone & Install
```bash
git clone https://github.com/bhavneetv/Aura_Music.git
cd Aura_Music
flutter pub get
```

### 2. Configure Environment API Keys
Create a `.env` file in the project root:
```env
GROQ_KEY="your_groq_api_key"
GROQ_KEY_2="your_second_groq_api_key"
GEMINI_KEY="your_gemini_api_key"
```

### 3. Run Locally
```bash
flutter run
```

### 4. Build Release Bundles
- **Android APK**:
  ```bash
  flutter build apk --release --no-tree-shake-icons
  ```
- **iOS Bundle**:
  ```bash
  flutter build ios --release --no-codesign
  ```
- **Windows Executable**:
  ```bash
  flutter build windows --release
  ```
- **macOS App**:
  ```bash
  flutter build macos --release --no-codesign
  ```
- **Linux Bundle**:
  ```bash
  flutter build linux --release
  ```

---

## ⚙️ Automated CI/CD Workflows

Workflows are configured under `.github/workflows/`:
- **`apk-build.yml`**: Builds and releases Android `.apk`.
- **`dart.yml`**: Builds and releases iOS `.ipa`.
- **`desktop-builds.yml`**: Builds and releases Windows `.exe` (Zip), macOS `.app` (Zip), and Linux bundle (`.tar.gz`).

To enable automated release builds with AI features, add `GROQ_KEY`, `GROQ_KEY_2`, and `GEMINI_KEY` to your repository's **Settings > Secrets and variables > Actions**.

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more details.
