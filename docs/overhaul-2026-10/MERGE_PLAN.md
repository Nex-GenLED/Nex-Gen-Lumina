# Prepared merge of docs/overhaul-2026-10 into release — NOT RUN

Documents only. No tag, no version bump, no code, no `codemagic.yaml` change. The owner runs it when ready; nothing below has been executed.

## Why a push to release starts no build

`codemagic.yaml` lines 24–29 at `c283d62`: the only trigger is `events: [tag]` with `tag_patterns: build-*`. A branch push or a merge commit on `release/store-submission-consolidated` starts nothing; only a `build-*` tag does. The file's own comment (lines 20–23) adds that the Codemagic UI webhook was switched to tag-only at the same time; if push-builds ever reappear, check the UI first, because the yaml cannot disable a trigger it does not own. So: merge and push the branch, never a tag.

## Commands (from a clean worktree on the release branch; one at a time)

```
git fetch origin --no-tags
git ls-remote origin refs/heads/release/store-submission-consolidated     # expect c283d62 or a newer docs-only row
git ls-remote origin refs/heads/docs/overhaul-2026-10                     # the SHA reported in the hand-back
git worktree add --detach "C:/Flutter Projects/lumina-release-docs" origin/release/store-submission-consolidated
cd "C:/Flutter Projects/lumina-release-docs"
git switch release/store-submission-consolidated
git status --porcelain                                                     # must print nothing
git merge --no-ff --no-edit origin/docs/overhaul-2026-10 -m "Merge docs/overhaul-2026-10 into release (documents only: FACTS.md, guides, archive, docs guard, drive exports; no app code)"
```

Tree check before pushing (the merge must carry exactly the branch's tree when release has not moved):

```
git diff --stat origin/docs/overhaul-2026-10 HEAD                         # empty if release == c283d62
git diff --stat c283d62 HEAD -- lib test functions firestore.rules firestore.indexes.json codemagic.yaml pubspec.yaml android ios   # must be EMPTY: no code, rules, indexes, CI, version or platform files
git show --stat --name-status HEAD | head -60                              # only docs/, scripts/docs_*, README.md, CLAUDE.md, SECURITY.md, audit/README.md, esp32-bridge/README.md, alexa-skill/DEPLOYMENT.md, google-home/DEPLOYMENT.md, the moved/removed guides and PDFs
node scripts/docs_guard.mjs                                                # 0 failures
```

If release has moved past `c283d62` (another docs row), the first diff is non-empty by that row only; read it and continue. If anything under `lib/`, `test/`, `functions/`, rules, indexes, `pubspec.yaml`, `codemagic.yaml`, `android/` or `ios/` shows in the second diff, stop: that is not this branch.

Push the branch only:

```
git push origin release/store-submission-consolidated                      # no tag; never `--tags`
git ls-remote origin refs/heads/release/store-submission-consolidated     # confirm the merge SHA
```

Then add a ledger row under "Operational flags" (docs only, no build): "DOCS MERGE — docs/overhaul-2026-10 @ <sha> merged <date>; no functions, rules, config or app change; no build."

## Ship-checklist line (already in BUILD_LEDGER.md convention 6)

Before every bump: `node scripts/docs_guard.mjs` prints 0 failures; every `docs/FACTS.md` row the build changes is re-stamped (statement, status, build, verified date); the build's entry is added to `docs/guides/internal/31-release-notes.md` with its tester text ending "Send reports to general@nex-genled.com with the date and time."; the ledger row records the guard's summary line.
