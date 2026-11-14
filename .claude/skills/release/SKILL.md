---
name: release
description: Cut a release of the mod git-flow style - merge develop into main (which triggers auto-version, the GitHub release and the mod portal upload), then sync the version commit back into develop. Use when asked to release, ship, or publish a new version.
---

# Release

This repo uses a git-flow style setup:

- `develop` is the default branch. Feature PRs are **squash-merged** into it with Conventional Commit titles.
  Pushes to `develop` run tests and commitlint but never release.
- `main` is the release branch. Every push to `main` runs `.github/workflows/auto-version.yml`: if there
  is a `feat`, `fix`, `perf` or breaking commit since the last `v*` tag, it bumps `info.json`, writes
  `CHANGELOG.md` and `changelog.txt`, commits `chore(release): x.y.z`, tags `vx.y.z`, pushes, and runs
  `release.yml` (GitHub release + Factorio mod portal upload).

Releasing means: merge `develop` into `main` with a real merge commit, wait for the version commit, then
bring that commit back into `develop`.

## Rules

- **Never squash** `develop` into `main`. The changelog and version bump are computed from the individual
  conventional commits; a single squashed `chore:` commit would release nothing and lose the changelog.
- The merge commit's message must **not** start with `chore(release)`, or auto-version skips the push.
- Do not rewrite history on `main` or `develop` (no force pushes, no rebases of either branch).
- If anything below fails or looks wrong (conflicts, a red CI run, a rejected push), stop and tell the
  user what happened instead of improvising.

## Steps

### 1. Preflight

```bash
git status --porcelain            # must be empty; stop if the tree is dirty
git fetch origin --tags --prune
git log --oneline --no-merges origin/main..origin/develop
```

- If that log is empty, there is nothing to release. Say so and stop.
- Show the user the commits that will ship. Check whether any of them would cut a release:

```bash
git log --no-merges --format='%s%n%b' origin/main..origin/develop \
  | grep -qE '^(feat|fix|perf)(\([^)]*\))?!?:|^[a-z]+(\([^)]*\))?!:|^BREAKING[ -]CHANGE:' \
  && echo releasable || echo "no feat/fix/perf: main will update but no version will be cut"
```

  If nothing is releasable, tell the user and ask whether to merge anyway before continuing.
- Optionally preview the bump: `npx commit-and-tag-version --dry-run` run on a throwaway checkout of
  `origin/develop` (needs `npm ci`). Don't commit anything from the dry run.
- Check CI on `develop` is green (GitHub Actions for the latest `develop` commit). If it is red, stop.

### 2. Merge develop into main

Preferred: merge locally and push.

```bash
git checkout -B main origin/main
git merge --no-ff origin/develop -m "chore: merge develop into main for release"
git push origin main
```

If the push is rejected (branch protection, or the environment won't push to `main`), fall back to a pull
request instead: open a PR from `develop` into `main` titled `chore: release develop into main`, wait for
its checks, and merge it with the **merge commit** method (never squash, never rebase). If merge commits are
disabled in the repo settings, stop and ask the user to enable them (Settings > General > Pull Requests >
Allow merge commits) or to push the merge themselves.

### 3. Wait for the release

The push to `main` starts the "Auto version" workflow. Wait for it to finish (`gh run watch` on that run if
`gh` is available, or poll with a bounded loop, at most ~10 minutes):

```bash
for i in $(seq 1 30); do
  git fetch -q origin main --tags
  git log -1 --format=%s origin/main | grep -q '^chore(release)' && break
  sleep 20
done
git log -1 --format='%h %s' origin/main
git describe --tags --abbrev=0 origin/main
```

If nothing was releasable, no `chore(release)` commit will appear; skip the wait and go to step 4. If the
workflow failed, report the failing step and stop before touching `develop`.

### 4. Sync main back into develop

```bash
git checkout -B develop origin/develop
git merge --ff-only origin/main || git merge --no-edit origin/main
git push origin develop
```

Normally this fast-forwards (develop gains the merge commit and the `chore(release)` commit). If someone
merged into `develop` meanwhile, it makes a merge commit instead, which is fine. Resolve no conflicts
silently: if the merge conflicts, stop and ask.

### 5. Report

Tell the user the new version and tag, link the GitHub release
(`https://github.com/thattomperson/factorio-blueprints/releases/tag/vX.Y.Z`), say whether the mod portal
upload step passed (it is skipped with a warning when `FACTORIO_API_KEY` is not set), and confirm that
`develop` is back in sync with `main` (`git log --oneline origin/develop..origin/main` is empty).
