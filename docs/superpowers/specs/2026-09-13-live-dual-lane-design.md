# Fixly Live Dual-Lane Voice Agent — Design

**Date:** 2026-09-13  
**Status:** Approved (approach 1 — user: implement)

## Goals

- Gemini Live = primary realtime voice (low latency).
- Gemini Flash = background brain (booking + app intents) via `live-tool`.
- `flutter_tts` + STT = fallback when Live fails; auto-reconnect Live in background.
- Full duplex: mic always open while Live PCM active; barge-in clears playback.
- Both-side transcripts in chat (input/output audio transcription).
- In-chat app action cards: theme, navigate, pay, bookings, track, call, invoice, rating, settings, SOS, etc.

## Architecture

```
Mic PCM ──► Gemini Live (AUDIO) ──► Speaker PCM
                │ tool: call_fixly_brain / call_fixly_app
                ▼
         POST /live-tool (Flash) ──► reply + appActions + booking cards
                │
                ▼
         Chat bubbles + action cards; Live says short confirm
```

Fallback: Live error/close → banner + STT/`flutter_tts` → retry Live → restore PCM.

## Non-goals (v1)

- Server-side Live audio proxy
- Perfect AEC hardware path (rely on barge-in + discard buffer)

## Success

- User can interrupt mid-sentence; mic never soft-muted during AI speech.
- Theme/nav/pay requests produce chat cards + spoken confirm.
- Live outage → TTS continues session without user re-tap.
