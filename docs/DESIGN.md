# Blueprint Designer: design plan

Target: Factorio 2.1 (`factorio_version` in `info.json`). No Space Age dependency.

## Core idea

The **designer surface** is the source of truth. Every design has a cell on it, and a blueprint item is just an
export of that cell. Every exported blueprint contains one **design marker** entity carrying tags
`{bpd_design, bpd_tier, bpd_version}`. The marker is what lets the mod recognise its own blueprints, and later
what identifies each copy placed in the world.

```
designer surface (lab tiles, always day, no enemies)
            tier 1        tier 2        tier 3
design 1  [ cell 1,1 ]  [ cell 1,2 ]  [ cell 1,3 ]     cell = 224x224 design area,
design 2  [ cell 2,1 ]  [ cell 2,2 ]                   256-tile spacing, marker at centre
```

## Part 1: editor surface (built, v0.1.0)

* Shortcut / `Ctrl+Alt+B`:
  * holding a blueprint (inventory item or library record): open it on the designer. If it already has our
    marker, go to that design's cell; otherwise import it into a new design.
  * on the designer: save and return. The fresh blueprint lands in your cursor.
  * otherwise: open the Designs window (rename, Edit, Get blueprint, New design).
* You view the designer through **remote view**, so your character stays put and safe. An invisible void-powered
  radar per cell keeps it live-visible.
* Creative rules on the designer only: ghosts are revived instantly (modules filled in), deconstruction marks
  delete instantly, upgrade marks replace instantly. Entities are `disabled_by_script` so designs cost no UPS.
  Building outside a design area is refused.
* Leaving remote view any other way (Escape, switching surface) auto-saves.
* Each save normalises the cell (positions relative to the marker) and bumps the tier's `version` only if
  something actually changed. That snapshot is the input for parts 2 and 3.

Known gaps in 0.1: editing a library blueprint gives you an updated *copy* in the cursor rather than overwriting
the library entry; no blueprint book support; blueprints bigger than 224x224 get clipped.

## Part 2: tiers / upgrades (built, v0.2.0)

* "New tier" button on the editing bar copies tier N's cell into tier N+1 (one column right), then you edit it,
  e.g. swap stone furnaces for steel furnaces.
* **Diff engine** (shared with part 3): compare two snapshots by (position, name, direction):
  * same position, different entity of the same footprint and upgrade-compatible -> `order_upgrade`
    (bots do a fast-replace, so belts/inserters around it are untouched)
  * in old, not in new -> `order_deconstruction`
  * in new, not in old -> ghost (`create_entity{name="entity-ghost"}`, with recipe/settings via a one-entity
    blueprint so configuration is preserved)
  * same entity, different settings (recipe, filters, circuit conditions) -> paste settings / ghost over it
* "Upgrade to tier N+1" acts on one placed instance, or from the designs window on all instances of a tier.
* Placed rotation/flip is applied when mapping snapshot offsets to world positions.
* "Delete tier" removes tier N: cells N+1.. are cloned one column left (the last column is wiped back to lab
  tiles), cell records and placed copies on later tiers are renumbered, and copies of tier N are unlinked (their
  marker is destroyed, buildings stay). Tier numbers stay stable for blueprints already saved: each design keeps
  `deleted_tiers` (in order) and every marker is tagged `bpd_rev = #deleted_tiers`, so an old blueprint's
  `bpd_tier` is replayed through later deletions (`designs.resolve_tier`). A blueprint of a deleted tier is
  imported as a new design / not tracked when placed.

## Part 3: instance tracking (built, v0.2.0)

* When a blueprint containing our marker is placed, `on_pre_build` gives the placement direction and flip, and
  the marker ghost's tags give design/tier/version. The mod revives marker ghosts instantly (no item needed)
  and records the instance:
  `storage.instances[unit_number] = {design, tier, version, surface, position, direction, flip}`.
* Mining the marker forgets the instance (the built entities stay).
* Designs window shows per design: number of placed copies, how many are behind the current version, with
  "Update all" and per-instance "Show on map".
* "Update" = diff(snapshot at instance's version -> current snapshot), applied at the instance. We keep each
  tier's snapshots by version (pruned once no instance references an old version).
* Optional drift check: compare the world footprint against the snapshot to flag copies that were hand-edited.

## Decisions

* Updating placed copies is **safe by default**: only what changed in the master between the copy's version and
  the latest is applied, so hand-made additions survive. **Force match** (per copy) makes a copy exactly match:
  anything else in its footprint is marked for deconstruction and every master entity is rebuilt superforced.

## Known limitations (v0.2)

* Circuit/copper wires are not part of diffs: newly ghosted entities come without wires, and wire-only edits
  don't count as a change. Placing the whole blueprint again fixes wires.
* Tile changes between versions/tiers are not applied to placed copies.
* Mirrored (flipped) placements depend on the flip-then-rotate order assumed in `scripts/transform.lua`;
  needs an in-game check.
* Snapshots of old versions are kept forever (no pruning yet).
* A blueprint you capture by hand on the designer surface gets the tags of the last *saved* version.
