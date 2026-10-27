# Rotten Crown — notes for Claude

Godot 4.4 (Mobile renderer) first-person retro dark-fantasy horror game for Android, landscape.
Design: docs/GAME_DESIGN.md. Architecture: docs/ARCHITECTURE.md. Phases: docs/ROADMAP.md (update the checklist when finishing work).

## Conventions
- GDScript, tabs, static typing everywhere (`var x := ...`, typed params/returns). `class_name` for reusable types.
- Content is data: new items/enemies/regions are `.tres` resources under `data/`, not code.
- Systems talk through the `Events` autoload; do not reach across systems directly.
- Gameplay reads only Input Actions; touch/mouse/gamepad are routed into actions (see src/ui/touch_controls.gd).
- Physics layers: 1 world, 2 player, 3 enemies, 4 interactables, 5 player_hurtbox, 6 enemy_hurtbox.
- Horror rule: no jump scares. Fear comes from uncanny bodies and behaviour (see CreatureRig).
- Keep mobile budgets in mind: 640x360 internal resolution, <= 8 omni lights per mesh, no shadows on omni lights.
- Player-facing text is English for now (Arabic localisation is Phase 7); docs are Arabic.

## Before committing
- `python3 tools/validate_project.py` must pass.
- `gdparse` every changed .gd (pip install "gdtoolkit==4.*"); `gdlint src` uses ./gdlintrc.
- If a Godot binary is available: `godot --headless --path . --import` then `--quit-after 2` on the test scene.
