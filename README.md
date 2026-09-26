# Fixly — Cooperative Gig Services Platform

**SIH Problem Statement:** Cooperative Gig Services Platform for Household & Community Services  
**Repo:** `SIH-Fixly` · **Stack:** Flutter · Node.js/Express · React (Vite) · Python ML · MongoDB · Redis

Fixly connects **customers** with **verified cooperative workers** for on-demand household services (plumbing, electrical, cleaning, and more). Unlike typical gig aggregators, Fixly is built around **cooperative federations**, fair wage floors, worker welfare, and an AI concierge (**Flexi**) that can book jobs via chat or live voice.

This file is the map of the whole repo. Each big folder has its own `README.md` that stays on that folder only. Deeper architecture drawings live in [`APP_FLOW.md`](APP_FLOW.md).

---

## Picture first — one job, four apps

A person needs a plumber. Four programs do the work. They do not talk to each other directly except through the Node API (and one special voice line).

```mermaid
flowchart LR
    Phone["Phone app\nFlutter\ncustomer + worker"]
    Desk["Admin desk\nReact"]
    API["Brain\nNode API :8000"]
    Brain2["Helpers\nPython ML"]
    Box[("MongoDB\n+ Redis")]

    Phone -->|"login, book, pay"| API
    Desk -->|"approve, watch map"| API
    API --> Box
    API -->|"what service? face match?"| Brain2
    Phone -.->|"live voice only\nafter API gives a short token"| Gemini["Google Gemini Live"]
```

**Plain words**

1. Customer opens the Flutter app, signs in, describes the problem (or talks to Flexi).
2. The Node API saves the booking in MongoDB and finds a nearby verified worker.
3. The worker app gets a live ping (Socket.IO). Worker goes, arrives, shows an OTP, gives a price, does the job.
4. Customer pays with Razorpay. Worker wallet updates. Federation admin can see the job on the React desk.
5. Heavy AI (guess the service, match a face) runs in Python. The phone never calls Python itself. Node calls Python.

**Technical words (same picture)**

| Hop | What actually moves |
|-----|---------------------|
| App → API | HTTPS + JSON. Header carries a JWT. Device id is checked against Redis so one account stays on one device. |
| Live map / calls | Socket.IO on the same port `8000`. Redis adapter lets more than one API process share rooms. |
| Voice | `POST /api/ai/agent/live-token` mints a short Gemini token. Audio then goes phone ↔ Google, not through Node. |
| Money | Razorpay order + signature check in `paymentController`. Wallet rows are Mongo `Transaction` / `PayoutRequest`. |
| Who may see what | `federationMiddleware` limits a federation admin to their cooperative. Super admin sees all. |

---

## The four folders

Only these four folders have their own README. Inner folders are explained inside that README. They do not have a separate file.

| Folder | Who it is | README |
|--------|-----------|--------|
| [`frontend/`](frontend/README.md) | Phone app. One install, customer or worker. | Screens, Cubit, how it calls the API |
| [`backend/`](backend/README.md) | Node API on port 8000. The brain. | Routes, Mongo, sockets, Flexi, queues |
| [`FIXLY ADMIN PANEL/`](FIXLY%20ADMIN%20PANEL/README.md) | React desk for super admin and federation admin | Pages, login, `/api/admin` |
| [`ai_ml/`](ai_ml/README.md) | Python helpers | Ports 8002, 8004, 8080, 8082 |

How they connect: phone and admin talk only to **backend**. Backend talks to MongoDB, Redis, and (when switched on) the Python services. Live voice is the one extra line: backend mints a short token, then the phone streams audio to Google.

---

## Table of contents

1. [What Fixly is](#1-what-fixly-is)
2. [Architecture overview](#2-architecture-overview)
3. [Repository layout](#3-repository-layout)
4. [Feature map (SIH)](#4-feature-map-sih)
5. [Frontend — Flutter app](#5-frontend--flutter-app)
6. [Backend — Node API](#6-backend--node-api)
7. [Admin panel — React](#7-admin-panel--react)
8. [AI / ML microservices](#8-ai--ml-microservices)
9. [Flexi AI (LangGraph + Gemini Live)](#9-flexi-ai-langgraph--gemini-live)
10. [Real-time systems](#10-real-time-systems)
11. [Data model (high level)](#11-data-model-high-level)
12. [Prerequisites](#12-prerequisites)
13. [Local setup (step by step)](#13-local-setup-step-by-step)
14. [Environment variables](#14-environment-variables)
15. [API surface](#15-api-surface)
16. [Booking lifecycle](#16-booking-lifecycle)
17. [Docker & deployment](#17-docker--deployment)
18. [Tests](#18-tests)
19. [Extra documentation](#19-extra-documentation)
20. [Security notes](#20-security-notes)
21. [Team / SIH context](#21-team--sih-context)

---

## 1. What Fixly is

Fixly is a full-stack platform with four client-facing surfaces that share one backend:

| Surface | Who uses it | Tech |
|--------|-------------|------|
| **Customer app** | Book services, track workers, pay, SOS, Flexi AI | Flutter |
| **Worker app** | Accept jobs, navigate, estimate, wallet, KYC, welfare | Flutter (same binary, role switch) |
| **Admin / Federation panel** | Approve workers, manage bookings, wages, federations | React + Vite + Tailwind |
| **ML services** | Discovery, KYC face match, demos | Python (FastAPI / http.server) |

**Product pillars**

- **Cooperative governance** — Super Admin + Federation Admins; data scoped per cooperative
- **Trust & safety** — KYC face match, certificate OCR, OTP arrival, SOS broadcast, encrypted WebRTC calls
- **Fair work** — minimum wage floors, estimation before start, Razorpay payouts, welfare / e-Shram links
- **AI assistance** — Flexi chat + Gemini Live voice; service discovery; issue analysis (text/vision)

---

## 2. Architecture overview

```
┌─────────────────┐  ┌─────────────────┐  ┌──────────────────────┐
│  Flutter app    │  │  Admin panel    │  │  (optional) Python   │
│  customer/worker│  │  Vite React     │  │  ML microservices    │
└────────┬────────┘  └────────┬────────┘  └──────────┬───────────┘
         │ HTTPS JWT          │ HTTPS JWT            │ HTTP (proxied)
         │ Socket.IO          │                      │ by Node when
         ▼                    ▼                      │ toggles ON
┌────────────────────────────────────────────────────────────────┐
│                     Node.js Express API (:8000)                 │
│  Auth · Bookings · Payments · AI agent · Support · Admin · …   │
│  Socket.IO (tracking, WebRTC signaling) · BullMQ workers       │
└───────────────┬─────────────────────────────┬──────────────────┘
                │                             │
                ▼                             ▼
         ┌─────────────┐              ┌─────────────┐
         │  MongoDB    │              │   Redis     │
         │  ledger     │              │  sessions,  │
         │  GeoJSON    │              │  queues,    │
         └─────────────┘              │  Socket adapter
                                      └─────────────┘
                │
                ├─▶ Razorpay / RazorpayX
                ├─▶ Firebase FCM
                ├─▶ Cloudinary
                ├─▶ SMTP (OTP / email)
                ├─▶ Groq / Gemini (LLMs + Live token mint)
                └─▶ Python :8002 discovery, :8004 KYC (optional)
```

**Rule of thumb:** Flutter and Admin talk to **Node only**. Python ML is never called directly from the mobile app for business data. Exception: **Gemini Live** voice opens a short-lived WebSocket to Google after Node mints an ephemeral token; booking tools still go back through Node.

---

## 3. Repository layout

```
SIH-Fixly/
├── frontend/                 # Flutter app (customer + worker) — frontend/README.md
├── backend/                  # Express API, sockets, queues, Flexi — backend/README.md
├── FIXLY ADMIN PANEL/        # React desk — its own README.md
├── ai_ml/                    # Python helpers + start_all.py — ai_ml/README.md
├── .github/workflows/        # ML keep-alive ping
├── APP_FLOW.md               # Long architecture and sequence diagrams
└── README.md                 # This file (map + setup)
```

| Path | Role |
|------|------|
| `frontend/lib/features/` | Feature modules (auth, bookings, AI, worker, customer, …) |
| `frontend/lib/core/` | Network, auth storage, l10n, Firebase, navigation |
| `backend/controllers/` | HTTP handlers |
| `backend/models/` | Mongoose schemas |
| `backend/routes/` | Route mounts under `/api/*` |
| `backend/agent/` | Flexi LangGraph agent |
| `backend/worker/` | BullMQ consumers (email, upload, notifications, scheduled bookings) |
| `backend/sockets/` | Live tracking + WebRTC signaling |
| `FIXLY ADMIN PANEL/src/pages/` | Dashboard screens |
| `ai_ml/service_discovery/` | Sklearn classifier (port **8002**) |
| `ai_ml/identity_verification/` | DeepFace KYC (port **8004**) |
| `ai_ml/support_chatbot/` | Rule-based demo (port **8080**) |
| `ai_ml/worker_Reliability_Score/` | Reliability demo (port **8082**) |

---

## 4. Feature map (SIH)

Implemented and integrated across the stack (folder READMEs and `APP_FLOW.md` spell out each piece):

1. **Provider registration & verification** — selfie + ID → DeepFace match; duplicate Aadhaar/PAN checks; admin review band
2. **Skill profiling & certification** — certificate upload + Gemini Vision OCR + name fuzzy match
3. **Customer booking & scheduling** — ASAP or schedule (up to ~7 days); BullMQ reminders
4. **Automated worker matching** — geospatial + rating/availability/verification scoring
5. **Live job tracking** — Socket.IO GPS into booking rooms; Mapbox on Flutter
6. **OTP arrival & job timeline** — arrive PIN → estimate → start → complete → pay
7. **Payments & worker wallet** — Razorpay customer pay; wallet + payout requests
8. **Reviews & reliability** — reviews feed Node-side reliability metrics
9. **Support & AI concierge** — tickets + Flexi chat/voice + issue analyze / discovery
10. **SOS / emergency** — room broadcast + radius alert; emergency contacts
11. **Cooperative / federation governance** — multi-tenant admin scoping
12. **Welfare & fair wage** — wage floors, insurance/welfare modules, e-Shram/UAN links

---

## 5. Frontend — Flutter app

**Location:** `frontend/`  
**Package name:** `fixly`  
**SDK:** Dart `>=3.7.0 <4.0.0`

### 5.1 Roles in one app

Same APK/IPA; after auth, user is **customer** or **worker** (role flows under `lib/features/role`, `customer`, `worker`).

### 5.2 Feature folders (`lib/features/`)

| Feature | Purpose |
|---------|---------|
| `auth` | Login, register, OTP, Google Sign-In |
| `home` | Home feeds, banners, discovery entry |
| `bookings` | Create/track bookings, status UI |
| `customer` | Customer-specific flows (AI helper, service detail, …) |
| `worker` | Jobs, rates, estimation, wallet, welfare, KYC |
| `workers` | Browse/match workers |
| `ai` | Flexi chat/Live repositories & UI hooks |
| `payments` | Razorpay checkout |
| `reviews` | Post-job reviews |
| `cooperative` | Cooperative-related screens |
| `language` | Locale switching |
| `splash` / `system` | Boot, app-version gate |
| `demo` | Demo / showcase paths |

Supporting layers:

- `lib/core/` — Dio client, secure storage, Firebase Messaging, permissions, Mapbox config, l10n
- `lib/services/` — Gemini Live, WebRTC, speech, AI agent helpers, call sounds
- `lib/shared/` — Shared widgets/pages (e.g. SOS)

### 5.3 Notable libraries

| Area | Packages |
|------|----------|
| State / routing | `flutter_bloc`, `go_router`, `equatable` |
| Maps | `mapbox_maps_flutter`, `geolocator`, `geocoding` |
| Realtime | `socket_io_client`, `flutter_webrtc`, `flutter_callkit_incoming` |
| AI / voice | `speech_to_text`, `flutter_tts`, `record`, `web_socket_channel`, custom Gemini Live service |
| Payments | `razorpay_flutter` |
| Auth / push | `firebase_core`, `firebase_messaging`, `google_sign_in`, `flutter_secure_storage` |
| Media | `image_picker`, `cached_network_image`, `video_player`, `pdf` / `printing` |

### 5.4 Run (local)

```bash
cd frontend
cp .env.example .env          # set Mapbox + API_BASE_URL
cp dart_defines.example.json dart_defines.json   # same keys for --dart-define-from-file

flutter pub get
flutter run --dart-define-from-file=dart_defines.json
```

Phone images: `frontend/Dockerfile` and `frontend/docker-compose.yml`. Day-to-day dev is `flutter run`, not Docker.

### 5.5 Config keys (Flutter)

| Key | Meaning |
|-----|---------|
| `API_BASE_URL` | Backend base URL (local IP, tunnel, or prod) |
| `Mapbox_api_key` / `ACCESS_TOKEN` | Mapbox public token (`pk.*`) |

Never commit real `.env` or filled `dart_defines.json` with secrets.

---

## 6. Backend — Node API

**Location:** `backend/`  
**Runtime:** Node.js (ES modules) · **Default port:** `8000`  
**Docs:** Swagger UI at `http://localhost:8000/api-docs` (generate with `npm run swagger`)

### 6.1 Tech stack

| Concern | Choice |
|---------|--------|
| HTTP | Express 5 |
| DB | MongoDB + Mongoose (GeoJSON `2dsphere`) |
| Cache / sessions / queues | Redis + BullMQ + ioredis |
| Realtime | Socket.IO (+ Redis adapter) |
| Auth | JWT access + refresh; multi-device `deviceId` sessions in Redis |
| Payments | Razorpay |
| Push | Firebase Admin (FCM) |
| Media | Cloudinary + Multer upload pipeline |
| AI | Groq, Google Generative AI, LangChain / LangGraph |
| Security | Helmet, CORS, rate limits, NoSQL key sanitizer |
| Email | Nodemailer (OTP / transactional via queue) |

### 6.2 Background workers (auto-imported on start)

| Worker | Job |
|--------|-----|
| `emailWorker.js` | Outbound email |
| `uploadWorker.js` | Async uploads |
| `notificationWorker.js` | Push / notification fan-out |
| `scheduledBookingWorker.js` | Scheduled booking reminders |

### 6.3 Run

```bash
cd backend
cp .env.example .env   # fill Mongo, Redis, secrets, optional AI keys
npm install
npm run swagger        # optional — refresh swagger-output.json
npm start              # node server.js
```

Health: `GET /` → `{ status: 'success', message: 'GigConnect API Platform is active' }`

Seed helpers (when needed):

```bash
npm run seed                    # scripts/seedData.js
node scripts/seed-admin.js      # admin user seed
```

### 6.4 Auth notes

- Register → email OTP → verify → tokens
- Google login via Firebase ID token
- Send **`deviceId`** on login / OTP verify / logout for session isolation (see `backend/README`)
- Refresh token rotation supported

---

## 7. Admin panel — React

**Location:** `FIXLY ADMIN PANEL/`  
**Stack:** React 18 · Vite 5 · Tailwind · React Router · Leaflet · Recharts · Axios

### 7.1 Who logs in

- **Super Admin** — platform-wide: federations, settings, API keys, language control
- **Federation Admin** — scoped to own cooperative (middleware on backend)

### 7.2 Routes / pages

| Path | Screen |
|------|--------|
| `/login` | Auth |
| `/impersonate` | Impersonation helper |
| `/dashboard` | KPIs, recent bookings, maps |
| `/bookings` | Booking management |
| `/workers`, `/workers/:id` | Worker list & detail |
| `/approvals` | KYC / onboarding approvals |
| `/customers`, `/customers/:id` | Customers |
| `/services` | Service catalog |
| `/payments` | Payments / payouts |
| `/insurance` | Insurance policies |
| `/reviews` | Reviews moderation |
| `/reports` | Reports |
| `/analytics` | Charts / analytics |
| `/ai-insights` | AI-related insights |
| `/notifications` | Notification center |
| `/support` | Support tickets |
| `/settings` | Platform settings + API keys |
| `/federations`, `/federations/:id` | Cooperative federation admin |
| `/language-control` | Locale / copy toggles |
| `/theme` | Theme showcase |

### 7.3 Run

```bash
cd "FIXLY ADMIN PANEL"
npm install
npm run dev      # typically http://localhost:5173
npm run build    # production bundle
```

Point the panel’s API base URL at the running backend (see panel `.env` / Vite env — do not commit secrets). Netlify config: `netlify.toml`.

---

## 8. AI / ML microservices

**Location:** `ai_ml/`  
**Launcher:** `python3 start_all.py` (starts all present services; Ctrl+C stops all)

| Service | Port | Stack | Wired into production Node? |
|---------|------|-------|------------------------------|
| Service Discovery | **8002** | FastAPI + sklearn TF-IDF + `.pkl` | **Yes** when `AI_DISCOVERY_ENABLED=true` |
| Identity Verification | **8004** | FastAPI + DeepFace / face match | **Yes** when `AI_VERIFY_ENABLED=true` |
| Support Chatbot (demo) | **8080** | Rule engine + http.server | **Demo**; app support uses Node LLM path |
| Worker Reliability (demo) | **8082** | joblib demo store | **Demo**; app uses Node `computeReliability` on Mongo |

Deployable Docker services for discovery + identity: root `render.yaml` (Render free blueprint).

### 8.1 Quick start

```bash
cd ai_ml
# install deps per service (fastapi, uvicorn, scikit-learn, etc.)
python3 start_all.py
```

Useful URLs when up:

- Discovery docs: `http://127.0.0.1:8002/docs`
- KYC docs: `http://127.0.0.1:8004/docs`
- Support demo: `http://127.0.0.1:8080/demo/index.html`
- Reliability demo: `http://127.0.0.1:8082/demo/index.html`

Fallback behavior: if Python discovery/KYC is down or toggles are `false`, Node uses built-in keyword / manual review paths so the app still works.

Deep dive: [ai_ml/README.md](ai_ml/README.md) and [APP_FLOW.md](APP_FLOW.md) section 6.

---

## 9. Flexi AI (LangGraph + Gemini Live)

**Backend agent:** `backend/agent/` (+ `controllers/agentController.js`, routes `/api/ai/agent/*`)

| Mode | Flow |
|------|------|
| **Chat** | Flutter → `POST /api/ai/agent/chat` → LangGraph → Mongo tools (services, workers, bookings) → Redis session (~10 min TTL) → LLM reply (Gemini Flash / Groq) |
| **Live voice** | Flutter → `POST /api/ai/agent/live-token` → ephemeral Google token → Flutter WebSocket to Gemini Live → booking tools via `POST /api/ai/agent/live-tool` |
| **Analyze issue** | `POST /api/ai/analyze-issue` — text via Groq; image via Gemini Vision + Cloudinary |
| **Service discovery** | `POST /api/ai/service-discovery` → optional Python `:8002` → map to Mongo `Service` |
| **Match workers** | `POST /api/ai/match-workers` — Mongo `$near` + heuristic score |

Design notes for Live dual-lane / orchestration live under `docs/superpowers/`.

**Guardrail:** AI assists and proposes; humans confirm; money and booking truth stay in Node + Mongo.

---

## 10. Real-time systems

| Channel | Purpose |
|---------|---------|
| Socket.IO `worker_location_update` | Live GPS into booking room + update worker GeoJSON |
| Socket.IO SOS | Emergency broadcast to room / map markers in admin |
| WebRTC signaling (`/api/webrtc`, `sockets/webrtcCallSocket.js`) | Customer ↔ worker encrypted calls; Flutter CallKit |
| FCM + local notifications | Booking updates, reminders, calls |
| BullMQ | Email, uploads, notification fan-out, scheduled booking nudges |

Flutter clients: `socket_io_client`, `webrtc_call_service.dart`, Firebase Messaging setup under `lib/core/`.

WebRTC signaling lives in `backend/sockets/webrtcCallSocket.js`. The phone side is `frontend/lib/services/webrtc_call_service.dart`. Audio after the handshake goes phone-to-phone, not through Node.

---

## 11. Data model (high level)

Primary Mongo collections (Mongoose models in `backend/models/`):

| Model | Role |
|-------|------|
| `User` | Customers, workers, admins; location GeoJSON; KYC; federation refs |
| `Booking` | Job lifecycle + estimates + parties |
| `Service` | Catalog categories / pricing hints |
| `Review` | Ratings / comments |
| `Transaction` / `PayoutRequest` | Money movement |
| `Notification` / `PushToken` | In-app + FCM |
| `Cooperative` / `CooperativeSociety` | Federation / society entities |
| `SupportTicket` | Support |
| `WorkerCertificate` | Skill docs |
| `WelfareAccount` / `WelfareResource` / `WelfareTransaction` | Welfare |
| `InsurancePolicy` | Insurance |
| `EmergencyContact` | SOS contacts |
| `Banner` / `Settings` / `AppVersion` | CMS + config + force-update |
| `WebRTCCallLog` / `VerificationAuditLog` | Auditing |

**Booking `status` enum (simplified timeline):**

`PENDING` → `APPROVED` / `SEARCHING` → `ACCEPTED` → `ARRIVED` → `ESTIMATION_GIVEN` → `READY_TO_START` → `IN_PROGRESS` → `PAYMENT_PENDING` → `COMPLETED`  
(also `CANCELLED`)

Field-level picture: Mongoose files in `backend/models/`, and the ER diagram in [APP_FLOW.md](APP_FLOW.md).

---

## 12. Prerequisites

| Tool | Used for |
|------|----------|
| Node.js 18+ | Backend + admin panel |
| Flutter SDK (stable, Dart 3.7+) | Mobile app |
| MongoDB | Primary database |
| Redis | Sessions, Socket adapter, BullMQ |
| Python 3.10+ | Optional ML services |
| Android Studio / Xcode | Device or emulator |
| Mapbox account | Maps token |
| Firebase project | Auth Google + FCM |
| Razorpay account | Payments (test keys OK locally) |

---

## 13. Local setup (step by step)

### 13.1 Infrastructure

```bash
# MongoDB & Redis must be reachable at the URIs you put in backend/.env
# Example local defaults:
#   MONGO_URI=mongodb://127.0.0.1:27017/fixly
#   REDIS_URL=redis://127.0.0.1:6379
```

### 13.2 Backend

```bash
cd backend
cp .env.example .env
# Edit .env — at minimum MONGO_URI, REDIS_URL, JWT_SECRET, REFRESH_SECRET
npm install
npm start
# → http://localhost:8000
# → http://localhost:8000/api-docs
```

### 13.3 Admin panel

```bash
cd "FIXLY ADMIN PANEL"
npm install
npm run dev
# → http://localhost:5173
```

### 13.4 Flutter

```bash
cd frontend
cp .env.example .env
cp dart_defines.example.json dart_defines.json
# Set API_BASE_URL to your machine IP or tunnel (not localhost on physical device)
flutter pub get
flutter run --dart-define-from-file=dart_defines.json
```

### 13.5 Optional ML

```bash
cd ai_ml
python3 start_all.py
# Then set in backend/.env:
#   AI_DISCOVERY_ENABLED=true
#   AI_VERIFY_ENABLED=true
#   SERVICE_DISCOVERY_URL=http://127.0.0.1:8002
#   IDENTITY_VERIFY_URL=http://127.0.0.1:8004
```

### 13.6 Typical ports

| Service | Port |
|---------|------|
| Backend API + Socket.IO | **8000** |
| Admin Vite | **5173** |
| Service discovery | **8002** |
| Identity verification | **8004** |
| Support chatbot demo | **8080** |
| Reliability demo | **8082** |

---

## 14. Environment variables

### 14.1 Backend (`backend/.env`)

Copy from `backend/.env.example`. Common keys:

| Variable | Purpose |
|----------|---------|
| `PORT` | API port (default `8000`) |
| `MONGO_URI` | Mongo connection string |
| `REDIS_URL` | Redis connection string |
| `JWT_SECRET` / `REFRESH_SECRET` | Token signing |
| `FCM_PROJECT_ID` / `FCM_CLIENT_EMAIL` / `FCM_PRIVATE_KEY` | Firebase Admin push |
| `FCM_USE_APPLICATION_DEFAULT` | Use ADC in cloud instead of raw key |
| `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` | Payments |
| `AI_DISCOVERY_ENABLED` / `AI_VERIFY_ENABLED` | Toggle Python ML proxies |
| `SERVICE_DISCOVERY_URL` / `IDENTITY_VERIFY_URL` | ML base URLs |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USER` / `SMTP_PASS` | Email OTP |
| `CLOUDINARY_*` or DB Settings keys | Image hosting |
| `GROQ_API_KEY` / `GROQ_MODEL` | Text LLM |
| `GEMINI_API_KEY` / `GOOGLE_API_KEY` | Gemini + Live token mint |
| `GEMINI_LIVE_MODEL` | Live model id (default `gemini-3.1-flash-live-preview`) |

Many API keys can also be stored in Mongo **Settings** and edited from the Admin panel so operators can rotate without redeploying.

### 14.2 Flutter (`frontend/.env` + `dart_defines.json`)

| Variable | Purpose |
|----------|---------|
| `API_BASE_URL` | Backend origin |
| `Mapbox_api_key` / `ACCESS_TOKEN` | Mapbox `pk.*` |

### 14.3 Admin panel

Use Vite env vars as configured in the panel (API base URL, etc.). Keep `.env` out of git.

---

## 15. API surface

Base: `http://<host>:8000`  
Interactive: `/api-docs`

| Mount | Domain |
|-------|--------|
| `/api/auth` | Register, OTP, login, Google, refresh, logout |
| `/api/users` | Profiles |
| `/api/workers` | Worker profiles, reliability, availability |
| `/api/services` | Service catalog |
| `/api/bookings` | Booking CRUD + job timeline |
| `/api/payments` | Razorpay create/verify |
| `/api/reviews` | Reviews |
| `/api/home` | Home aggregates / banners |
| `/api/ai` | Analyze issue, discovery, match workers, demand forecast |
| `/api/ai/agent` · `/api/agent` | Flexi chat, live-token, live-tool |
| `/api/upload` | Media upload |
| `/api/admin` | Admin operations |
| `/api/verification` | KYC verify pipeline |
| `/api/worker-certificates` | Certificates |
| `/api/worker-wallet` | Wallet / payouts |
| `/api/notifications` | Notifications |
| `/api/support` | Support chat / tickets |
| `/api/cooperative` | Federations / societies |
| `/api/welfare` | Welfare |
| `/api/webrtc` | Call signaling / logs |
| `/api/emergency` | SOS / emergency |
| `/api/version` · `/api/app-version` | Force-update / version gate |

Auth API details (deviceId, OTP bodies): `backend/README`.

---

## 16. Booking lifecycle

End-to-end happy path:

1. **Customer** picks service (or Flexi / discovery suggests category)
2. **Match** nearby workers (geo + score) or open search
3. Booking enters **`SEARCHING`** / **`ACCEPTED`**
4. Worker **en route** — live map via Socket.IO + Mapbox
5. Worker **arrives** — customer enters OTP → **`ARRIVED`**
6. Worker submits **estimate** (labor + parts) → customer approves → **`READY_TO_START`**
7. Job **`IN_PROGRESS`** → complete → **`PAYMENT_PENDING`**
8. Customer pays (Razorpay) → **`COMPLETED`** → review; worker wallet / payout
9. Optional: WebRTC call anytime during active job; SOS if unsafe

Scheduled bookings use BullMQ for 24h / 1h / 30m reminders.

---

## 17. Docker & deployment

| Artifact | Purpose |
|----------|---------|
| `backend/Dockerfile` + `backend/docker-compose.yml` | API containerization |
| `frontend/Dockerfile` + `frontend/docker-compose.yml` | Flutter container helpers |
| `docker-compose.flutter.yml` | Host-emulator ADB loop |
| `ai_ml/*/Dockerfile` | ML services |
| `render.yaml` | Render free web services for discovery + identity |
| `scripts/deploy_hf_spaces.py` | Hugging Face Spaces deploy helper |
| `scripts/ml_keepalive.sh` | Keep free ML endpoints warm |
| `FIXLY ADMIN PANEL/netlify.toml` | Static admin hosting |

Production tips:

- Prefer ADC / secret managers for FCM and LLM keys
- Put Redis + Mongo on managed services
- Set Flutter `API_BASE_URL` to HTTPS API
- Enable `AI_*` toggles only when ML URLs are healthy

---

## 18. Tests

### Backend

```bash
cd backend
npm test           # run_tests_with_metrics.js wrapper
npm run test:raw   # node --test tests/*.test.js
```

Coverage areas include bookings, WebRTC, AI controller, notifications, cooperative/agent flows, app version, etc. (`backend/tests/`).

### Flutter

```bash
cd frontend
flutter test
```

Includes validators, workers API repository, notification payload, app version checks.

### Python ML

Each module under `ai_ml/*/tests` (where present) — run per package README.

---

## 19. Extra documentation

| Doc | Contents |
|-----|----------|
| [APP_FLOW.md](APP_FLOW.md) | Architecture diagrams and job sequences |
| [frontend/README.md](frontend/README.md) | Phone app, inner `lib/` folders |
| [backend/README.md](backend/README.md) | API, auth, queues, AWS notes |
| [FIXLY ADMIN PANEL/README.md](FIXLY%20ADMIN%20PANEL/README.md) | Admin desk and `src/` layout |
| [ai_ml/README.md](ai_ml/README.md) | The four Python programs and their ports |

---

## 20. Security notes

- **Never commit** `.env`, service-account JSON, private keys, or real Razorpay/Gemini/Groq secrets
- Rotate any secret that was ever pushed to git history
- JWT secrets must be strong and distinct (`JWT_SECRET` ≠ `REFRESH_SECRET`)
- Rate limiters apply on sensitive routes; Helmet enabled by default
- Federation middleware scopes admin queries — do not bypass in custom routes
- KYC images go through Cloudinary; treat URLs as sensitive PII
- Gemini Live tokens are short-lived; do not log them

---

## 21. Team / SIH context

- Platform name in code/docs may still appear as **GigConnect** / **SkillConnect** in older Swagger titles and backend messages — product brand is **Fixly**
- AI/ML pieces that actually run are listed in [ai_ml/README.md](ai_ml/README.md). `start_all.py` comments also mention worker-matching and fair-price ports; those folders are not in this repo.
- Problem framing: cooperative gig work for household & community services with fair wages, verification, and AI-assisted booking

---

## Quick start (cheat sheet)

```bash
# Terminal 1 — API
cd backend && cp .env.example .env && npm install && npm start

# Terminal 2 — Admin
cd "FIXLY ADMIN PANEL" && npm install && npm run dev

# Terminal 3 — Flutter
cd frontend && cp dart_defines.example.json dart_defines.json && flutter pub get
flutter run --dart-define-from-file=dart_defines.json

# Terminal 4 — optional ML
cd ai_ml && python3 start_all.py
```

Then open:

- API docs → `http://localhost:8000/api-docs`
- Admin → `http://localhost:5173`
- Flutter → device / emulator

---

## License

ISC (backend `package.json`); clarify with team before public redistribution of the full monorepo.
```