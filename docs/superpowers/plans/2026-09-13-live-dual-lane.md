# Live Dual-Lane Implementation Plan

> **For agentic workers:** Steps below. Mark complete as you go.

**Goal:** Approach 1 — Live voice duplex + Flash brain + TTS fallback + app action cards.

## Files

| File | Change |
|------|--------|
| `backend/utils/geminiLiveToken.js` | Transcription + app-tool instruction |
| `backend/agent/services/appIntentService.js` | NEW — detect app intents + optional booking lookup |
| `backend/controllers/agentController.js` | Merge `appActions` into chat/live-tool |
| `frontend/pubspec.yaml` | `flutter_tts: ^4.2.5` |
| `frontend/android/.../AndroidManifest.xml` | TTS_SERVICE query |
| `frontend/lib/models/ai_agent_response.dart` | `appActions` |
| `frontend/lib/features/ai/data/ai_app_actions.dart` | NEW — detect + execute |
| `frontend/lib/services/gemini_live_service.dart` | (minor if needed) |
| `frontend/lib/features/customer/.../customer_ai_helper_page.dart` | Duplex, transcripts, tools, cards, fallback |

## Tasks

1. Token + duplex + transcripts
2. App actions model/detector/executor + cards
3. Live `call_fixly_app` + brain merge
4. Fallback B reconnect
5. flutter_tts + manifest
6. Hot reload / smoke
