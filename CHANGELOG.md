# Changelog

All notable changes to this project are documented here. Entries are generated from
[Conventional Commits](https://www.conventionalcommits.org/) by `npm run release`; the in-game
`changelog.txt` is generated from the same commits.

## [0.2.6](https://github.com/thattomperson/factorio-blueprints/compare/v0.2.5...v0.2.6) (2026-11-14)

### Bug Fixes

* support tiles in designs and placed copies ([a0ecd12](https://github.com/thattomperson/factorio-blueprints/commit/a0ecd12e02dbfad7d7fe34eb15a6e40bb577ae57))

## [0.2.5](https://github.com/thattomperson/factorio-blueprints/compare/v0.2.4...v0.2.5) (2026-11-14)

### Features

* delete blueprint tiers from the editing bar ([d0760fc](https://github.com/thattomperson/factorio-blueprints/commit/d0760fc2d4428d28fb89f4f230f005b7dc1304da))
* downgrade placed copies to the previous tier ([ffbadbd](https://github.com/thattomperson/factorio-blueprints/commit/ffbadbd5412f49dec9e44d7e6539d7c1cd55da66))
* redesign the Designs, Copies and editing-bar GUIs ([67cb93c](https://github.com/thattomperson/factorio-blueprints/commit/67cb93c1f5f23bd5e065ad5d7a4e83cb81646d04))

## 0.2.4 (2026-11-14)

### Features

* add blueprint tiers, placed-copy tracking and release tooling ([#1](https://github.com/thattomperson/factorio-blueprints/issues/1)) ([3731e77](https://github.com/thattomperson/factorio-blueprints/commit/3731e77e632dc14da129fb06e1011d8e51e57ace))

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
