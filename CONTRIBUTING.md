# Contributing

## Commits and PRs

We use [Conventional Commits](https://www.conventionalcommits.org/): `feat: ...`, `fix: ...`, `perf: ...`,
`docs: ...`, `chore: ...`, `refactor: ...`, `test: ...`, `ci: ...`. Add `!` (`feat!: ...`) or a
`BREAKING CHANGE:` footer for breaking changes.

PRs are **squash-merged**, and the PR title becomes the commit on `main`, so CI checks that the PR title is
conventional. Direct pushes to `main` are linted too. Check a message locally with
`echo "feat: something" | npx commitlint`.

## Tests

```
pip install lupa
npm test            # python3 -I tests/run.py: control logic against a mocked runtime
```

## Releasing

```
npm ci
npm run release                      # or: npm run release -- --release-as minor
git push --follow-tags origin main
```

`npm run release` works out the next version from the commits since the last tag, bumps `info.json`, adds a
section to `CHANGELOG.md` and the in-game `changelog.txt` (via `tools/factorio-changelog.mjs`), commits
`chore(release): x.y.z` and tags `vx.y.z`.

Pushing the tag runs `.github/workflows/release.yml`, which checks that the tag matches `info.json`, builds
`blueprint-designer_x.y.z.zip` (leaving out everything marked `export-ignore` in `.gitattributes`), creates a
GitHub release with the zip and the changelog section, and uploads the zip to the Factorio mod portal.

The portal upload needs a repository secret `FACTORIO_API_KEY`: an API key from
https://factorio.com/create-api-key with the "ModPortal: Upload Mods" and "ModPortal: Publish Mods" usages.
Without it the workflow still makes the GitHub release and skips the portal with a warning.
