# 🎵 Aura Music — Next-Gen AI Music Player

[![Flutter](https://img.shields.io/badge/Flutter-v3.27+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-brightgreen)](#-getting-started)
[![AI Engine](https://img.shields.io/badge/AI%20Powered-Groq%20%7C%20Gemini-orange)](#-ai-intelligence--features)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Aura Music** is a sleek, ultra-modern, skeuomorphic Flutter music streaming application built for high-fidelity audio playback, AI-assisted lyric interpretation, synchronized karaoke, and personalized aesthetic customization.

---

## ✨ Features at a Glance

### 🚀 High-Fidelity Audio Streaming
- **Decrypted JioSaavn & Jamendo Integration**: Stream millions of Punjabi, Hindi, Bollywood, English, and global hits at up to **320 kbps HQ**.
- **Smart Pre-Flight URL Resolver**: Automatic fallback pipeline with direct audio stream health-checks and bitrate negotiation (320kbps → 160kbps → 96kbps).

### 🤖 AI Intelligence & Lyrics Interpretation
- **Line-by-Line AI Explanations 💡**: Deep-dive into what the song author means for each lyric line, powered by **Groq Llama-3.3 70B** with instant **Gemini 2.5 Flash** fallback.
- **Real-Time AI Translation 🌐**: Translate lyrics instantly into **Hindi**, **English**, or **Hinglish**.
- **AI Song Story Summaries 📜**: Get instant AI summaries explaining the song's story, mood, emotional themes, and background in English or Hindi.

### 🎤 Synchronized Karaoke Lyrics
- **Live LRC Karaoke**: Auto-scrolling lyrics synchronized precisely to playback position.
- **Center Sync Lock 🎯**: Lock active karaoke lines in the exact vertical center of the screen during playback.

### 🎨 Skeuomorphic Player Skins & Aesthetic Customization
- **4 Distinct Player Skins**:
  - 🎨 **Ultra Minimal Artwork** *(Default)*
  - 📀 **Rotating Vinyl Disc**
  - 💿 **Modern Compact CD**
  - 📼 **Classic Retro Cassette Tape**
- **Personalized RGB Theme Accent**: Pick from curated presets (Aura Gold, Neon Cyan, Emerald, Purple, Sunset, Crimson) or define custom RGB values.
- **Glassmorphic & Dark Mode UI**: Premium frosted glass aesthetics with full AMOLED Dark Mode support.

### 🎛️ Advanced Audio Engine & Controls
- **Built-In Equalizer**: 5-band graphic EQ with custom presets and Bass Boost.
- **Volume Normalization**: Equalize audio output to dampen harsh volume spikes.
- **Gapless Playback & Crossfade**: Smooth transitions between songs.
- **Haptic Feedback**: Dynamic vibration responses on buttons and sliders.

### 📥 Offline Downloads & Profile
- **Offline Download Manager**: Save tracks locally for offline listening with full cover art and metadata caching.
- **First-Launch Personalization**: Personalizes greetings (`Good morning, Bhavneet 🌅`, `Good afternoon ☀️`) based on your display name and time of day.

---

## 📲 How to Download & Install

### Option A: Download Pre-Built Releases (Easiest)

1. Open the [Releases](https://github.com/bhavneetv/Aura_Music/releases) page of this repository.
2. Download the latest **`app-release.apk`** for Android devices or **`FlutterIpaExport.ipa`** for iOS devices.
3. Install the APK on your Android device (ensure *Install from Unknown Sources* is enabled).

---

### Option B: Build & Run from Source (GitHub)

#### 📋 Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.24.0 or newer)
- [Dart SDK](https://dart.dev/get-dart)
- Android Studio / VS Code with Flutter extension
- Android SDK (for Android build) / Xcode (for iOS build)

#### 🛠️ Step-by-Step Build Instructions

1. **Clone the Repository**
   ```bash
   git clone https://github.com/bhavneetv/Aura_Music.git
   cd Aura_Music
   ```

2. **Install Dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Environment API Keys**
   Create a `.env` file in the root directory:
   ```env
   GROQ_KEY="your_groq_api_key_here"
   GROQ_KEY_2="your_second_groq_api_key_here"
   GEMINI_KEY="your_gemini_api_key_here"
   ```
   *(Note: Free API keys can be obtained from [Groq Console](https://console.groq.com/) and [Google AI Studio](https://aistudio.google.com/).)*

4. **Run the App Locally**
   Connect your physical device or start an emulator/simulator, then run:
   ```bash
   flutter run
   ```

5. **Build Release APK or IPA**
   - **Android Release APK**:
     ```bash
     flutter build apk --release --no-tree-shake-icons --dart-define=GROQ_KEY="your_key" --dart-define=GEMINI_KEY="your_key"
     ```
   - **iOS Release Bundle**:
     ```bash
     flutter build ios --release --no-codesign
     ```

---

## ⚙️ GitHub Actions CI/CD Automated Workflow

This project includes automated GitHub Actions workflows under `.github/workflows/`:
- **`apk-build.yml`**: Automatically builds Android Release APKs and creates a GitHub Release when triggered.
- **`dart.yml`**: Automatically builds and archives iOS `.ipa` packages.

To enable automated release builds with AI features, add `GROQ_KEY`, `GROQ_KEY_2`, and `GEMINI_KEY` to your repository's **Settings > Secrets and variables > Actions**.

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more details.
