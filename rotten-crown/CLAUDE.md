# Rotten Crown — notes for Claude

Godot 4.7 (Mobile renderer) first-person retro dark-fantasy horror game for Android, landscape.
Design: docs/GAME_DESIGN.md. Architecture: docs/ARCHITECTURE.md. Phases: docs/ROADMAP.md (update the checklist when finishing work).

## Conventions
- GDScript, tabs, static typing everywhere (`var x := ...`, typed params/returns). `class_name` for reusable types.
- Content is data: new items/enemies/regions are `.tres` resources under `data/`, not code.
- Systems talk through the `Events` autoload; do not reach across systems directly.
- Gameplay reads only Input Actions; touch/mouse/gamepad are routed into actions (see src/ui/touch_controls.gd).
- Physics layers: 1 world, 2 player, 3 enemies, 4 interactables, 5 player_hurtbox, 6 enemy_hurtbox.
- Horror rule: no jump scares. Fear comes from uncanny bodies and behaviour (see CreatureRig).
- Keep mobile budgets in mind: 640x360 internal resolution, <= 8 omni lights per mesh, no shadows on omni lights.
- Player-facing text is English for now (Arabic localisation is Phase 8); docs are Arabic.

## Content pipelines (baked content)
- The world is baked, not generated at runtime. After changing `src/world`, `src/levels/valdron`, regions or props, run `GODOT=... tools/bake_world.sh overworld` and `... prologue`, and commit the regenerated `src/levels/valdron/baked/*.scn` with the change.
- After changing a character (rig, `creature_rig.gd`, `tools/sprite_baker/characters.json`), run `GODOT=... tools/bake_sprites.sh <char>` and commit `assets/sprites/<char>/`.
- The sprite direction convention lives in `SpriteSheetData.direction_index` (`src/rendering/sprite_sheet_data.gd`). The baker and `PixelSprite3D` must agree: change both or neither.
- `hollow.tscn` is sprite based (`SpriteCreatureVisual`). The baker poses creatures through `tools/sprite_baker/creature_rig.tscn`, not through the hollow scene.

## Before committing
- `python3 tools/validate_project.py` must pass.
- `gdparse` every changed .gd (pip install "gdtoolkit==4.*"); `gdlint src` uses ./gdlintrc.
- Godot: `export GODOT=$(tools/setup_godot.sh)` (downloads 4.7.1 + web templates only). Then
  `$GODOT --headless --path . --import` and `$GODOT --headless --path . --quit-after 120 src/levels/test/visual_test.tscn` - no errors.

## Every phase / feature: publish a phone-testable web build
The user tests on their phone through GitHub Pages (https://mahmoud70004-debug.github.io/godot-mcp/, served from <repo>/docs).
1. `tools/publish_web.sh` (exports the "Web" preset: Compatibility renderer, no threads, PWA).
2. Serve ../docs locally and run `node tools/web_smoke_test.cjs http://localhost:PORT/index.html build/smoke`; look at the screenshots.
3. Commit `../docs` together with the change and push.
Web uses the Compatibility renderer: keep shaders/features working there too (e.g. generated audio needs PLAYBACK_TYPE_STREAM).
Also run `node tools/web_touch_repro.cjs URL` (joystick regression) and compare `node tools/web_perf.cjs URL` with the previous build.

## Performance rules (web / Compatibility renderer)
- Every object is drawn again for each light touching it: keep omni ranges small, no lights on effects (fireworks), unshaded for big surfaces (grass, far ground, silhouettes).
- Procedural geometry must go through MeshMerger (merge_static for scenery, bake_character for rigs).
- Large instanced surfaces (grass) must be chunked with visibility_range_end.
- Visual review without a phone: `tools/render_shots.sh` (RC_SHOT) or Movie Maker on the cutscene (see docs/ARCHITECTURE.md).
