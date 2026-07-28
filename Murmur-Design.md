# Murmur — A Fully Local, Granola-Style Meeting Notepad for macOS

**Working name:** Murmur
**Platform:** macOS 14+ (native SwiftUI / AppKit)
**Goal:** Everything runs on-device. Audio never leaves the Mac, transcription runs on
the Neural Engine, and note "enhancement" runs against a local LLM. No account, no cloud,
no telemetry.

---

## 1. What Granola actually does (and what we're copying)

Granola's core trick is deceptively simple:

1. While you're in a meeting, it captures **two audio sources** — your **microphone**
   ("you") and the **system output** ("them", i.e. whatever the meeting app is playing
   through your speakers).
2. It transcribes that audio to text.
3. You jot **sparse notes** during the call.
4. When the call ends, an LLM **merges your rough notes with the full transcript** into
   clean, structured meeting notes (summary, decisions, action items).

The magic is step 4: your notes give the model *what you cared about*, and the transcript
gives it *what was actually said*. Murmur reproduces this loop entirely on-device.

---

## 2. Architecture at a glance

```
                          ┌─────────────────────────────┐
   Microphone  ──────────▶│  MicrophoneCapturer          │
   (AVAudioEngine)        │  (AVAudioEngine input tap)   │──┐
                          └─────────────────────────────┘  │  16 kHz mono
                                                            ├─▶ AudioFileWriter ─▶ mic.wav
   System audio ─────────▶┌─────────────────────────────┐  │
   (ScreenCaptureKit /    │  SystemAudioCapturer         │──┘  16 kHz mono
    Core Audio tap)       │  (SCStream audio output)     │──────▶ AudioFileWriter ─▶ system.wav
                          └─────────────────────────────┘

   On stop:
     mic.wav    ─▶ WhisperKit.transcribe ─▶ segments (labeled "You")   ─┐
     system.wav ─▶ WhisperKit.transcribe ─▶ segments (labeled "Them")  ─┤─▶ merge by
                                                                         │   timestamp
                                                                         ▼
                                              full transcript  +  your raw notes
                                                                         │
                                                                         ▼
                                                     OllamaClient  ─▶  Enhanced notes
                                                     (localhost:11434)   (summary / actions)
                                                                         │
                                                                         ▼
                                                     SwiftData  ◀── persisted Meeting
```

Design principle: **each capture source is transcribed independently and merged by
timestamp.** This gives us clean "You vs. Them" speaker labels for free, and avoids the
hard problem of overlaying two live audio streams into one correctly-timed mix.

---

## 3. Component breakdown

### 3.1 Audio capture

**Microphone** — `AVAudioEngine`. Install a tap on `inputNode`, receive
`AVAudioPCMBuffer`s in the device's native format (usually 44.1/48 kHz float), resample to
**16 kHz mono Float32** (what Whisper wants), and stream to a WAV writer.

**System audio** — two viable native paths on modern macOS:

| Approach | Min macOS | Permission | Indicator? | Notes |
|---|---|---|---|---|
| **ScreenCaptureKit** (`SCStream`, `capturesAudio = true`) | 13.0 | Screen Recording | Yes (menu-bar dot) | Simple, well-documented, robust. **Murmur ships with this.** |
| **Core Audio process taps** (`CATapDescription` + aggregate device) | 14.4 | Audio Capture (`NSAudioCaptureUsageDescription`) | No | The "right" path for an audio-only notes app — no screen-recording prompt. Lower-level C interop. **Recommended production upgrade.** |

We ship ScreenCaptureKit because it's the fastest way to a working, reliable capture.
The screen-recording permission is the one visible wart; migrating to Core Audio taps
removes it. Both are wrapped behind a `SystemAudioCapturer` protocol so the swap is
localized. See §7 for the tap migration notes and their known foot-guns.

`SCStreamConfiguration` is set to capture audio only: `capturesAudio = true`,
`excludesCurrentProcessAudio = true` (so we don't record our own UI sounds),
`sampleRate = 48000`, `channelCount = 2`, and a minimal 2×2 video size with a long
`minimumFrameInterval` since we discard video frames.

### 3.2 Transcription — WhisperKit

[WhisperKit](https://github.com/argmaxinc/WhisperKit) (Argmax) runs OpenAI Whisper models
compiled to Core ML, using the Apple Neural Engine + Metal. Added via Swift Package
Manager.

- Model is downloaded on first launch (e.g. `openai_whisper-base.en` ≈ 150 MB, or
  `openai_whisper-small.en` for better accuracy). Cached locally thereafter.
- We transcribe **on stop** by pointing WhisperKit at each `.wav` file. This is
  memory-safe for long meetings (WhisperKit internally windows long audio) and avoids
  holding hours of PCM in RAM.
- Each returned segment carries `.text`, `.start`, `.end`. We tag mic segments as **You**
  and system segments as **Them**, then merge both lists sorted by start time.

*Live preview (stretch):* WhisperKit also exposes streaming transcription; the MVP keeps
the authoritative transcript as a post-stop pass for reliability and leaves live captions
as a documented enhancement (§6).

### 3.3 Note enhancement — local LLM via Ollama

[Ollama](https://ollama.com) is the pragmatic local-LLM runtime: `brew install ollama`,
`ollama pull llama3.1:8b`, done. It serves an HTTP API on `localhost:11434`.

`OllamaClient` POSTs to `/api/generate` (or `/api/chat`) with a prompt that combines the
user's raw notes and the merged transcript, and a system instruction to produce
structured notes: **TL;DR**, **key points**, **decisions**, **action items (with owners)**,
and **open questions**. Streaming is optional; the MVP takes the full response.

Model is configurable in Settings (default `llama3.1:8b`; `qwen2.5:7b` and
`mistral:7b` are good alternatives). Because it's all localhost, this stays 100% offline.

*Alternative that needs no separate install:* Apple's on-device **Foundation Models**
framework (macOS 26). Wrapped behind a `NoteEnhancer` protocol so Ollama can be swapped
for it later.

### 3.4 Storage — SwiftData

A single `@Model final class Meeting` holds `title`, `startedAt`, `duration`, `rawNotes`,
`transcript`, `enhancedNotes`, and a pointer to its audio folder. SwiftData persists to a
local store in Application Support. Audio WAVs live in a per-meeting folder; the user can
delete audio after enhancement to save space.

### 3.5 UI — SwiftUI

- **MenuBarExtra**: always-present menu-bar item with a one-click Start/Stop and a live
  recording timer — the fastest way to start capturing when a call begins.
- **Main window**: a `NavigationSplitView` — sidebar lists past meetings; detail view has
  three tabs: **Notes** (editable while recording), **Transcript** (You/Them), and
  **Summary** (the enhanced output, with a re-generate button).
- **RecordingController** (`@Observable`): the coordinator that owns capture state, wires
  the two capturers to their file writers, kicks off transcription + enhancement on stop,
  and writes the `Meeting` to SwiftData.

---

## 4. Permissions & entitlements

The app is sandboxed-optional (audio taps + SCK are simpler **without** the App Sandbox for
a personal build; enable hardened runtime for distribution). Required:

- `NSMicrophoneUsageDescription` — mic capture.
- Screen Recording permission — requested at first system-audio capture (ScreenCaptureKit).
  *(With the Core Audio tap path this becomes `NSAudioCaptureUsageDescription` instead and
  the screen-recording prompt disappears.)*
- Outgoing network to `localhost` only (Ollama). If sandboxed, add the
  `com.apple.security.network.client` entitlement.
- Core Audio taps additionally require a **signed** binary for TCC prompts to appear.

---

## 5. Data flow, step by step

1. User clicks **Record** (menu bar or window).
2. `RecordingController` creates a meeting folder, starts `MicrophoneCapturer` and
   `SystemAudioCapturer`; each streams 16 kHz mono into `mic.wav` / `system.wav`.
3. User types sparse notes into the Notes tab; a running timer shows.
4. User clicks **Stop**. Capturers flush and close their files.
5. `TranscriptionManager` transcribes both WAVs, labels + merges segments → `transcript`.
6. `NoteEnhancer` sends `rawNotes` + `transcript` to Ollama → `enhancedNotes`.
7. Everything is saved as a `Meeting`; the detail view shows the polished summary.

---

## 6. Build roadmap

**Phase 1 — MVP (this deliverable)**
Menu-bar + window UI, mic + ScreenCaptureKit capture to WAV, on-stop WhisperKit
transcription with You/Them labels, Ollama enhancement, SwiftData persistence.

**Phase 2 — Feel**
Live captions (WhisperKit streaming), waveform/level meters while recording, a global
hotkey to start/stop, auto-title from the summary.

**Phase 3 — Polish & privacy-max**
Migrate system audio to Core Audio process taps (kill the screen-recording prompt),
auto-detect when Zoom/Meet/Teams launches and offer to record, calendar integration to
name meetings, export to Markdown/PDF, per-meeting audio auto-delete.

**Phase 4 — Speaker intelligence**
Real diarization (Argmax **SpeakerKit** or `pyannote`-style embeddings) so "Them" splits
into named participants; searchable transcript archive.

---

## 7. Migrating system audio to Core Audio taps (production upgrade)

The tap path (macOS 14.4+) removes the screen-recording indicator. Key pieces:

- Build a `CATapDescription` (mono/stereo global tap, optionally excluding your own PID).
- Create a **private aggregate device** whose *main* sub-device is a real output device,
  with the tap attached as a **sub-tap** (not as the main device — a common mistake).
- Register an IO proc with `AudioDeviceCreateIOProcIDWithBlock` and read PCM there. Do
  **not** try to drive it through `AVAudioEngine` — setting the engine's current device
  returns `noErr` but silently keeps reading the default input.
- Add `NSAudioCaptureUsageDescription`; the binary must be **signed** or TCC won't prompt.

Apple's sample `AudioCap` (insidegui) and Apple's "Capturing system audio with Core Audio
taps" doc are the canonical references. Because it's the same 16 kHz-mono output contract,
only `SystemAudioCapturer` changes — the rest of Murmur is untouched.

---

## 8. Why these choices

- **On-device Whisper (WhisperKit)** over a cloud STT: privacy is the whole point, and the
  Neural Engine makes `base`/`small` models real-time-capable on Apple Silicon.
- **Ollama** over bundling a model runtime: it's the least-friction way for a user to get a
  capable local LLM, with a stable HTTP contract, and it's swappable for Apple Foundation
  Models later.
- **Two streams, merged by timestamp** over mixing: gives speaker labels for free and
  sidesteps real-time mix alignment.
- **SwiftData** over Core Data boilerplate or files: least code for a local, typed store.

> ⚠️ This codebase targets Apple Silicon Macs. WhisperKit's ANE path assumes M-series;
> Intel Macs fall back to CPU/GPU and will be much slower.
