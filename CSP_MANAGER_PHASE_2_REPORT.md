# CSP Manager – Phase 2 integration

Implemented:
- standalone landing page at `/manager/` for `cspmanager.app`
- Vercel host rewrite from `cspmanager.app/` to `/manager/`
- login and registration CTAs
- Ultra+ feature-gate messaging and session-aware primary CTA
- safe `returnTo` flow through login and registration
- main CSP hero CTA linking to `https://cspmanager.app/`
- access guard added to Manager dashboard

Deployment note:
- Add `cspmanager.app` as a domain to the same Vercel project.
- The host rewrite serves the Manager landing page at the domain root.
- `/login/`, `/registracia/`, `/upgrade/`, `/assets/` and `/manager/*` remain shared paths in the same deployment.
