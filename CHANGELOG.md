# Changelog

All notable changes to this project are documented here. Entries are generated from
[Conventional Commits](https://www.conventionalcommits.org/) by `npm run release`; the in-game
`changelog.txt` is generated from the same commits.

## 0.2.3 (2026-11-14)

### Features

* Blueprint tiers: "New tier" copies the current tier into the next; tier buttons switch between them.
* Placed blueprints are tracked through their design marker, including rotation and flips.
* Copies window per design: Show, Update (safe), Upgrade to next tier, Force match, Update all, Upgrade all.
* Updates place ghosts for new entities, mark removed ones for deconstruction, and upgrade same-size replacements in place.
* Alt-mode label over each placed copy's marker.
* Target Factorio 2.1.

### Bug Fixes

* Use `minable_flag`; `LuaEntity::minable` is read-only in 2.1.
* Stop using `table.deepcopy`, which is nil at runtime.

## 0.1.0 (2026-11-14)

### Features

* Designer surface with one lab-tiled cell per design; edit a held blueprint there and save it back to your cursor.
* Ghosts on the designer build instantly; deconstruction and upgrade marks apply instantly.
* Design marker embedded in saved blueprints; Designs window with Edit / Get blueprint / New.
