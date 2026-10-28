# Rotten Crown — agent context (Phase 3 "graphics polish")

Repo root: /home/user/godot-mcp (git; contains the MCP server at root and the game in rotten-crown/).
Game root: /home/user/godot-mcp/rotten-crown. Web build is served from /home/user/godot-mcp/docs (GitHub Pages).
Design docs: rotten-crown/docs/GAME_DESIGN.md, ARCHITECTURE.md (Arabic), ROADMAP.md (update checklist when done).

## 1. Stack
- Godot 4.4.1 (project features "4.4", "Mobile"), GDScript only, Android landscape + HTML5 web.
- Renderer: `mobile` for native/Android; `gl_compatibility` for web (renderer/rendering_method.web).
- Viewport: 640x360 internal (window/size/viewport_width/height).
- Autoloads (load order, project.godot [autoload]):
  1. Events (src/autoload/events.gd) - signal bus
  2. Settings (src/autoload/settings.gd) - sensitivity, invert, audio, forced touch; user://settings.cfg
  3. GameState (src/autoload/game_state.gd) - inventory, equipped weapon, upgrades, flags, docs, relic stats
  4. SaveManager (src/autoload/save_manager.gd) - user://savegame.json
  5. AudioManager (src/autoload/audio_manager.gd) - SFX pools 2D/3D, music crossfade
  6. SceneLoader (src/autoload/scene_loader.gd) - fade-to-black, threaded load
  7. DebugBridge (src/autoload/debug_bridge.gd) - ?debug=1 FPS/touch overlay + window.rcState for browser tests (register(key, Callable))
- Physics layers: 1 world, 2 player, 3 enemies, 4 interactables, 5 player_hurtbox, 6 enemy_hurtbox.
- Input: gameplay reads only Input Actions; touch is routed into actions (TouchControls).

## 2. Commands (verbatim)
Paths outside the repo (verified to exist):
- Godot binary: /tmp/claude-0/-home-user-godot-mcp/bbd3ba3c-e2c7-5ce1-b8e0-8b1a5b7ac4eb/scratchpad/godot/Godot_v4.4.1-stable_linux.x86_64
- Env helper: `source /tmp/claude-0/-home-user-godot-mcp/bbd3ba3c-e2c7-5ce1-b8e0-8b1a5b7ac4eb/scratchpad/env.sh` (exports GODOT)
- gdtoolkit venv: /tmp/claude-0/-home-user-godot-mcp/bbd3ba3c-e2c7-5ce1-b8e0-8b1a5b7ac4eb/scratchpad/gdvenv/bin/ (gdparse, gdlint, gdformat)

Run from /home/user/godot-mcp/rotten-crown:
- Import: `"$GODOT" --headless --path . --import`
- Headless scene run: `"$GODOT" --headless --path . --quit-after 120 src/levels/test/visual_test.tscn`
- Validate refs: `python3 tools/validate_project.py`
- Lint/parse: `gdparse <changed .gd files>` ; `gdlint src` (reads ./gdlintrc)
- Web export + publish to ../docs: `GODOT=$GODOT tools/publish_web.sh` (wraps tools/export_web.sh release; output build/web/)
- Screenshots (Compatibility renderer, virtual display): `GODOT=$GODOT tools/render_shots.sh OUT_DIR scene.tscn "name:x,y,z,yaw,pitch" ...`
  - internally: `RC_SHOT="x,y,z,yaw,pitch" xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-driver opengl3 --write-movie F.png --fixed-fps 10 --quit-after 30 SCENE`
- Movie Maker of a cutscene (verified): `xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-driver opengl3 --write-movie OUT/f.png --fixed-fps 4 --quit-after 230 src/cutscenes/prologue.tscn` -> OUT/f00000000.png...
- Dev hooks live in src/world/level.gd: RC_SHOT="x,y,z,yaw,pitch" places the player; RC_PERF / ?perf=nosky,nograss,nohorizon,nopost,nofog disables features.
- Web tests (need local server on ../docs, start with run_in_background):
  - Server: `python3 -m http.server 8766 --directory /home/user/godot-mcp/docs` (run_in_background: true)
  - Smoke: `node tools/web_smoke_test.cjs http://localhost:8766/index.html build/smoke`
  - Touch regression: `node tools/web_touch_repro.cjs http://localhost:8766/index.html`
  - Perf: `node tools/web_perf.cjs http://localhost:8766/index.html` (compare with previous build; `?perf=` toggles features)
- Node scripts MUST be `.cjs` (repo-root package.json is "type": "module").
- Godot setup: `export GODOT=$(tools/setup_godot.sh)` (downloads 4.4.1 + web templates only).

Pre-commit (CLAUDE.md): validate_project.py passes; gdparse each changed .gd; import + headless run clean; for web-facing work publish + smoke + touch repro + perf, then commit ../docs with the change.

## 3. Folder map (rotten-crown/)
Only the Phase 3 areas. `class_name` in brackets.

### World / level (src/world/)
- level.gd [Level] - root script for every playable level; region wiring.
- outer_ward_blockout.gd [OuterWardBlockout] - procedural greybox of Moonlit Meadows and Outer Ward; main target for merge_static.
- region_data.gd [RegionData] - resource describing a region (data/regions/*.tres).
- region_trigger.gd [RegionTrigger] - Area3D on player layer that enters a region.
- flicker_light.gd [FlickerLight] - animated lantern OmniLight3D (no shadows).
- ambient_drone.gd [AmbientDrone] - looping drone AudioStreamPlayer (PLAYBACK_TYPE_STREAM).
- sky_billboard.gd [SkyBillboard] - keeps moon at fixed direction/distance.
- src/levels/test/visual_test.tscn - main visual test scene (headless run + screenshots target).

### Rendering (src/rendering/, assets/shaders/)
- mesh_merger.gd [MeshMerger] - merge_static(root, cell 20m) per material x cell; bake_character(root) vertex-colour bake; SEED_META="seed01" per-mesh seed in COLOR.r.
- retro_materials.gd [RetroMaterials] - static palette materials (stone, mossy_stone, cobble, dead_grass, red_earth...) with tiny NoiseTexture2D.
- post_process.tscn - retro_post post-process overlay.
- assets/shaders/retro_post.gdshader - post pass (pixelation/dither).
- assets/shaders/flesh.gdshader - creature skin (instance uniforms hit_flash/time_offset; NOT mergeable).
- assets/shaders/ooze.gdshader - ooze/blood splats; seed = instance `seed` + COLOR.r*100 so merged splats keep variety (SEED_META).
- assets/shaders/grass.gdshader - unshaded instanced grass (chunked 12m, visibility_range_end 40m).
- assets/shaders/moon.gdshader, night_sky.gdshader - sky.
- assets/shaders/silhouette.gdshader - unshaded far silhouettes.
- assets/ui/rotten_theme.tres - UI theme.

### Characters (src/characters/)
- part_builder.gd [PartBuilder] - helpers to assemble primitive meshes into parts.
- humanoid_rig.gd [HumanoidRig] - shared pose/animation base for knight and villagers.
- knight_model.gd [KnightModel] - player knight in cutscenes (plate harness).
- villager_model.gd [VillagerModel] - townsfolk, warm and alive.

### Enemies (src/enemies/, data/enemies/)
- enemy.gd [Enemy] - base AI; variants override _should_wake / attack states.
- creature_rig.gd [CreatureRig] - procedural, deliberately wrong animation for transformed citizens.
- enemy_data.gd [EnemyData] - stats + behaviour flags resource.
- hollow.tscn - base enemy scene (data = data/enemies/hollow.tres); also data/enemies/mourner.tres.

### Prologue (src/cutscenes/)
- prologue.tscn - opening feast cinematic scene.
- prologue_cutscene.gd [PrologueCutscene] - shot/text director.

### Tools (rotten-crown/tools/)
- validate_project.py - static check of res:// refs and paths (must pass).
- export_web.sh - Web export to build/web/ (Compatibility, no threads, PWA).
- publish_web.sh - export + copy to ../docs.
- setup_godot.sh - downloads Godot 4.4.1 + web templates, prints binary path.
- render_shots.sh - screenshot frames via xvfb + opengl3.
- web_smoke_test.cjs, web_touch_repro.cjs, web_perf.cjs - browser tests (Chromium, need URL).
- gen_audio.py - generates placeholder WAV music/SFX with loop points.
- fetch_zip_members.py - helper (not gameplay).

### Other relevant
- src/player/player.gd [Player], player_weapon.gd [PlayerWeapon] - player controller; weapon uses Tween wind-up and HitboxComponent.
- src/components/{health,hurtbox,hitbox}_component.gd [HealthComponent, HurtboxComponent, HitboxComponent]
- src/combat/damage_info.gd [DamageInfo]
- src/ui/touch_controls.gd [TouchControls], virtual_joystick.gd [VirtualJoystick], touch_action_button.gd [TouchActionButton]
- src/items/item_data.gd [ItemData] (+ weapon_data, consumable_data, relic_data, lore_data), inventory.gd [Inventory], weapon_model_builder.gd [WeaponModelBuilder]
- src/interaction/interactable.gd [Interactable], item_pickup.gd [ItemPickup]
- src/autoload/events.gd, src/autoload/debug_bridge.gd
- assets/: shaders/, ui/ used; textures/, models/, audio/, fonts/ empty until Phase 7.
- data/: enemies/, items/{weapons,consumables,relics,lore}/, regions/ (8 region .tres incl. outer_ward, moonlit_meadows).

## 4. Conventions (copy from these)
- Tabs, GDScript 4, static typing everywhere (`var x := ...`, typed params/returns). class_name for reusable types.
- Example file to copy: src/components/health_component.gd (typed, class_name, signals), or src/rendering/retro_materials.gd for static palette builders.
- @tool procedural builders: greybox and scenery are built in code (outer_ward_blockout.gd), then merged.
- RetroMaterials palette: add a static func returning StandardMaterial3D; do not inline colours in scenery.
- MeshMerger: merge_static(root) for scenery (run after build); bake_character(root) for rigs (vertex colours). Tag meshes with SEED_META for seed-driven shader variation.
- PartBuilder: build characters from primitives; then bake_character.
- Events bus: systems talk through Events; no direct cross-system references.
- Physics layers as listed above; never scale a physics shape non-uniformly.
- Data as .tres under data/ (Resource subclasses: ItemData, EnemyData, RegionData, LoreData).
- Gameplay reads Input Actions only.
- Horror rule: no jump scares; fear from uncanny bodies/behaviour.
- Player-facing text English for now.

## 5. Performance
Rules (CLAUDE.md, web/Compatibility renderer draws each object once per touching omni light):
- Keep omni light ranges small; no lights on effects (fireworks); no shadows on omni lights; max 8 omni lights per mesh (mobile).
- Procedural geometry must go through MeshMerger (merge_static for scenery, bake_character for rigs).
- Big surfaces (grass, far ground, silhouettes) unshaded; grass chunked with visibility_range_end.
- Ground split into 20 m squares.
- Textures compressed ETC2/ASTC.
- No MSAA; a single shadow caster (moon).

Measured software-Chromium FPS (web_perf.cjs; not phone numbers):
- Phase 1 gameplay: 6.25 FPS
- Current gameplay: ~4.75 FPS
- Prologue: ~4.5 FPS

Known cost centres: per-object re-draw under many omni lights (lanterns in Outer Ward and Meadows), unmerged procedural geometry, grass instance count, prologue crowd (many VillagerModel/KnightModel rigs with separate meshes), post-process pass on the web build.

## 6. Gotchas
- package.json at repo root is "type": "module": node test scripts must be .cjs.
- Godot web touch: InputEventScreenDrag.relative is unreliable on web (reports relative to the other finger, causes camera fling). TouchControls computes its own deltas.
- AudioStreamGenerator / AudioStreamPlayer generated audio needs playback_type = AudioServer.PLAYBACK_TYPE_STREAM on web.
- Non-uniform scale must not be applied to physics shapes (CollisionShape3D); scale visuals only.
- Untyped array element access cannot be type-inferred with `:=` in GDScript; annotate explicitly (`var x: float = arr[i]`).
- Mouse events synthesised from touch must not trigger attacks (only mouse when captured).
- Godot binary on web: Compatibility renderer only; keep shaders working there.
- docs/ at repo root is the built web output, not source; never hand-edit it.
- Each publish commits the engine .wasm once; only .pck changes per build.
