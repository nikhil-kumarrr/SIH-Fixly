# Contributing to Fixly

Thank you for your interest in contributing to **Fixly** — the cooperative gig services platform built for fair wages, worker welfare, and AI-powered service matching!

---

## Code of Conduct

We are committed to providing a welcoming, inclusive, and harassment-free environment for everyone. Please be respectful, constructive, and collaborative in all discussions and pull requests.

---

## Monorepo Structure

Fixly is structured as a monorepo containing four core workspaces:

- [`backend/`](backend/): Express.js REST & WebSocket API, BullMQ queues, MongoDB models, Flexi AI assistant.
- [`frontend/`](frontend/): Flutter application (shared codebase for Customers & Cooperative Workers).
- [`FIXLY ADMIN PANEL/`](FIXLY%20ADMIN%20PANEL/): React + Vite dashboard for Super Admins and Federation Admins.
- [`ai_ml/`](ai_ml/): Python FastAPI microservices for service classification, face matching, and ML utilities.

---

## Development Workflow

### 1. Fork & Clone
```bash
git clone https://github.com/nikhil-kumarrr/SIH-Fixly.git
cd SIH-Fixly
```

### 2. Branching Strategy
Create a feature branch from `main`:
```bash
git checkout -b feat/your-feature-name
# or for bug fixes:
git checkout -b fix/issue-description
```

### 3. Environment Configuration
Follow the local setup instructions in the root [`README.md`](README.md):
- Copy `backend/.env.example` to `backend/.env` and supply required variables.
- Copy `frontend/dart_defines.example.json` to `frontend/dart_defines.json`.
- Install dependencies for the relevant project:
  - Backend: `cd backend && npm install`
  - Admin: `cd "FIXLY ADMIN PANEL" && npm install`
  - Frontend: `cd frontend && flutter pub get`
  - AI/ML: `cd ai_ml && pip install -r requirements.txt` (if testing ML services)

### 4. Code Standards & Commits
- Use descriptive commit messages following the Conventional Commits format:
  - `feat: add SOS emergency contact alert`
  - `fix: resolve wallet payout concurrency issue`
  - `docs: update API documentation for live-token endpoint`
  - `refactor: optimize socket event listeners`
- Ensure code compiles cleanly without errors or warnings.
- Keep secrets and `.env` files out of Git history.

---

## Submitting Pull Requests

1. Push your branch to your fork:
   ```bash
   git push origin feat/your-feature-name
   ```
2. Open a Pull Request against the `main` branch of `nikhil-kumarrr/SIH-Fixly`.
3. Provide a clear PR description explaining the problem solved or feature added.
4. Attach screenshots or demo recordings if changes affect the Flutter app or Admin Panel UI.
5. Ensure CI checks pass before requesting reviews.
