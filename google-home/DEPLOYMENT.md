# Google Smart Home Action — status (2026-10-09)

**Account linking has never worked for any user.** Do not advertise Google Home control
anywhere: not in the app, documents, store listings or the website. See `docs/FACTS.md`
(T-VA1) and `docs/guides/internal/33-claims-policy.md`.

- The implemented endpoints live in the main Functions codebase (`googleAuth`, `googleToken`,
  `googleSmartHome`). The code in this folder is a stale duplicate and is not deployed.
- The fix chain (the functions-compat script on the link page, the token design, revocation,
  the Android manifest `<queries>` entries) is built on branch `feat/voice-link-e2e` and is NOT
  deployed. Deployment waits for the owner.
- This page carries no deploy command on purpose. The command that used to be here resolved the
  repo-root `firebase.json` and would have deployed the entire main codebase; the rules snippet
  that used to be here would have replaced the hardened production ruleset. Production deploys
  are made per function from the matching checkout; rules deploys are manual and branch-sensitive.
- Previous content: git history of this file before 2026-10-09.
