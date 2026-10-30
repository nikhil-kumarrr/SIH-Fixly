# Security Policy

Fixly takes security and user privacy seriously. As a cooperative gig platform dealing with financial transactions, identity verification (KYC), real-time location tracking, and AI-assisted workflows, maintaining robust security standards across our monorepo is critical.

---

## Supported Versions

Only the latest `main` branch receives active security updates and vulnerability patches.

| Component | Target Version | Supported |
|-----------|---------------|-----------|
| Backend API (`backend/`) | Node.js 20+ / Express 5 | :white_check_mark: |
| Admin Panel (`FIXLY ADMIN PANEL/`) | Vite + React 18 | :white_check_mark: |
| Mobile Client (`frontend/`) | Flutter 3.7+ | :white_check_mark: |
| AI / ML Services (`ai_ml/`) | Python 3.10+ / FastAPI | :white_check_mark: |

---

## Reporting a Vulnerability

If you discover a security vulnerability or security bug in Fixly:

1. **Do NOT open a public GitHub issue.**
2. Report vulnerabilities privately via **[GitHub Private Vulnerability Reporting](https://github.com/nikhil-kumarrr/SIH-Fixly/security/advisories/new)** or by emailing the maintainer at **`nikhilkumar.20300@gmail.com`**.
3. In your report, please provide:
   - A detailed description of the vulnerability and attack vector.
   - Exact steps or minimal proof-of-concept (PoC) to reproduce the issue.
   - Affected service (`backend`, `frontend`, `FIXLY ADMIN PANEL`, or `ai_ml`).
   - Potential impact on users, worker PII, or financial flows.

You will receive an acknowledgement within 48 hours and regular updates on triage and mitigation.

---

## Core Security Guidelines for Developers

- **Never Commit Secrets**: Do not commit `.env`, `dart_defines.json`, Firebase service accounts, Google Gemini API keys, Groq tokens, Razorpay secrets, or Cloudinary credentials.
- **Short-Lived Gemini Live Tokens**: Always mint ephemeral Gemini tokens via `POST /api/ai/agent/live-token`; never leak API keys to mobile clients or commit them into static builds.
- **Role-Based Federation Scoping**: All federation admin routes must pass through `federationMiddleware` to prevent cross-tenant data leaks.
- **Input Sanitization**: All MongoDB queries must pass through `express-mongo-sanitize` to defend against NoSQL injection.
- **Sensitive PII & KYC**: Worker documents and KYC images uploaded to Cloudinary must be handled with care and never exposed publicly without authentication.
