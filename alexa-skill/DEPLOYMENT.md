# Amazon Alexa Smart Home Skill — status (2026-10-09)

**Account linking has never worked for any user.** Do not advertise Alexa control anywhere:
not in the app, documents, store listings or the website. See `docs/FACTS.md` (T-VA1) and
`docs/guides/internal/33-claims-policy.md`.

- The implemented OAuth endpoints are the main-codebase functions `alexaAuth`, `alexaToken`,
  `alexaUnlink` and `generateAlexaAuthCode`; the Lambda in this folder is the device shim.
- The fix chain (the functions-compat script on the link page, a signed access token, revocation,
  the Android manifest `<queries>` entries) is built on branch `feat/voice-link-e2e` and is NOT
  deployed. Deployment waits for the owner. The skill is not to be submitted for certification
  until linking is deployed and proven end to end.
- The "Serverless Framework" option that used to be on this page never existed in this folder.
- Previous content: git history of this file before 2026-10-09.
