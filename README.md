# Blueprint Designer (Factorio 2.1 mod)

Design and edit blueprints on a dedicated designer surface. See [docs/DESIGN.md](docs/DESIGN.md) for the full plan
and known limitations.

## Install for testing

Copy or symlink this folder into your Factorio `mods` directory as `blueprint-designer_0.2.3`
(or zip it as `blueprint-designer_0.2.3.zip` containing a top-level `blueprint-designer_0.2.3/` folder).

## Use

* Hold a blueprint and press **Ctrl+Alt+B** (or the shortcut-bar button): you're taken to the designer surface
  with the blueprint built there. Place ghosts, they build instantly. Deconstruct/upgrade planners act instantly.
* Press **Ctrl+Alt+B** again, click **Save & return**, or just press Escape: the design is saved and the updated
  blueprint is put in your cursor.
* With an empty hand, the hotkey opens the **Designs** window: rename, edit, get the latest blueprint, or start a
  new empty design.

## Tiers and placed copies

* While editing, **New tier** copies the current tier into the next one (e.g. T1 stone furnaces -> T2, then swap
  in steel furnaces). The T1/T2 buttons switch between tiers.
* **Delete tier** (on the editing bar, asks first) removes the tier you are editing and clears its design area.
  Later tiers move down one; their placed copies and saved blueprints keep working. Copies placed from the
  deleted tier are unlinked: their buildings stay, but they are no longer tracked. A design's only tier can't
  be deleted.
* Every blueprint the mod saves contains a small design marker. Wherever you place it, that copy is tracked
  (hold Alt to see its label).
* Designs window -> **Copies** lists every placed copy, flags outdated ones, and offers:
  * **Update**: apply what changed in the master since that copy was placed (hand-made additions are left alone).
  * **Upgrade to T(n+1)**: ghosts the new stuff, marks removed things for deconstruction, upgrades same-size
    replacements in place.
  * **Downgrade to T(n-1)**: the reverse of Upgrade, moving the copy back to the previous tier.
  * **Force match**: make the copy exactly match the master, removing anything extra in its footprint.
  * **Update all outdated** / **Upgrade all Tn -> Tn+1** / **Downgrade all Tn -> Tn-1**.

## Contributing and releases

See [CONTRIBUTING.md](CONTRIBUTING.md): Conventional Commits, squash merges, and `npm run release` + tag push
for GitHub and mod portal releases.

## Tests

`pip install lupa && python3 -I tests/run.py` runs the control logic against a mocked game runtime.
Not a substitute for an in-game test.
