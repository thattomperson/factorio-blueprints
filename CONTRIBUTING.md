# Contributing

## Commits and PRs

We use [Conventional Commits](https://www.conventionalcommits.org/): `feat: ...`, `fix: ...`, `perf: ...`,
`docs: ...`, `chore: ...`, `refactor: ...`, `test: ...`, `ci: ...`. Add `!` (`feat!: ...`) or a
`BREAKING CHANGE:` footer for breaking changes.

## Branches

`develop` is the default branch: open PRs against it. `main` only moves when a release is cut, so everything
on `main` has been released (git-flow style). PRs are **squash-merged** into `develop`, and the PR title
becomes the commit there, so CI checks that the PR title is conventional. Pushes to `develop` and `main` are
linted too. Check a message locally with
`echo "feat: something" | npx commitlint`.

## Tests

```
pip install lupa
npm test            # python3 -I tests/run.py: control logic against a mocked runtime
```

## Releasing

To release, merge `develop` into `main`. In Claude Code, run `/release` (`.claude/skills/release/SKILL.md`):
it merges `develop` into `main` with a merge commit (never a squash, since the changelog is built from the
individual commits), waits for the version commit, and merges `main` back into `develop`. By hand:

```
git fetch origin
git checkout -B main origin/main && git merge --no-ff origin/develop -m "chore: merge develop into main for release"
git push origin main
# wait for the "Auto version" workflow, then:
git fetch origin && git checkout -B develop origin/develop && git merge --ff-only origin/main && git push origin develop
```

Pushes to `develop` never release. Every push to `main` runs
`.github/workflows/auto-version.yml`: if there is a `feat`, `fix`, `perf` or breaking commit since the last
tag, it runs `commit-and-tag-version`, which bumps `info.json` from the commits, adds a section to
`CHANGELOG.md` and the in-game `changelog.txt` (via `tools/factorio-changelog.mjs`), commits
`chore(release): x.y.z` and tags `vx.y.z`. It pushes that and then runs the release workflow. Commits that
are only `docs`, `chore`, `ci`, `test` and similar don't cut a release.

`.github/workflows/release.yml` (also runs if you push a `v*` tag by hand) checks that the tag matches
`info.json`, builds `blueprint-designer_x.y.z.zip` (leaving out everything marked `export-ignore` in
`.gitattributes`), creates a GitHub release with the zip and the changelog section, and uploads the zip to the
Factorio mod portal.

The portal upload needs a repository secret `FACTORIO_API_KEY`: an API key from
https://factorio.com/create-api-key with the "ModPortal: Upload Mods" and "ModPortal: Publish Mods" usages.
Without it the workflow still makes the GitHub release and skips the portal with a warning.

The release workflow pushes to `main` with the built-in token. If you add branch protection to `main`, allow
GitHub Actions to bypass it, or the version commit will be rejected.

To version a release locally instead of in CI: `npm ci && npm run release && git push --follow-tags origin main`
(then sync `main` back into `develop` as above).

## Test builds on PRs

Every push to a PR runs `.github/workflows/pr-build.yml`, which uploads the mod as an artifact and keeps one
PR comment with a download link. The download is a ready-to-use `blueprint-designer_x.y.z.zip`.
