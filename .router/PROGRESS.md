# PROGRESS — Phase 3 (graphics polish)

| task | tier used | status | files | note |
|---|---|---|---|---|
| recon | E (router-scout) | done | .router/CONTEXT.md | 149 lines; 4 unverified details corrected by H |
| plan | H | done, awaiting user approval | .router/PLAN.md | 23 tasks: 5 E, 13 N, 5 H |
| T16 | E (router-easy) | done | night_sky.gdshader, cloud_noise.tres, 2 scenes | worktree base fixed after a first attempt on main; clouds thinner -> retune in T21 |
| T11 | E (router-easy) | done | grass.gdshader, grass_field.tres, grass_dry_tall.tres | first attempt blocked (worktree from main) |
| T01 | N (router-normal) | done | humanoid_rig.gd, creature_rig.gd, knight_model.gd | first attempt blocked; retry in a pre-made worktree passed; verified by H |
| T10 | N (router-normal) | done | prop_kit.gd, retro_materials.gd (palettes), prop_gallery | verified by H render; gnarled canopy + chapel spire to refine in T13/T14 |
| T09 | H | done | terrain_spec.gd, terrain_builder.gd, terrain.gdshader, grass_scatter.gd, terrain_preview | crash traced to "".split_floats() engine bug in the preview, not terrain |
| T03 | H | done | tools/sprite_baker/*, tools/bake_sprites.sh | hollow: 296 frames in 6.8 s; head faces viewer in all 8 dirs |
| T12 | N (router-normal) | done | regions/thornfield_builder.gd | verified by H render: composition matches ref 1; dry grass too sparse/white -> tune in T21 |
| T14 | N (router-normal) | done | regions/whispering_wood_builder.gd, moon_shaft.gdshader, prop_kit gnarled_tree | verified by H render (matches ref 3); ~15k meshes -> measure verts after merge (T21); forest road paint -> pale dirt (T21) |
| T18 | N (router-normal) | done | quality_manager.gd, settings, events, hud, project.godot | printed D7 values verified; live auto-downgrade to check in T21 |
| T13 | N (router-normal) | done | regions/hollowmere_builder.gd, prop_kit chapel/pumpkin | verified by H render (matches ref 2); flesh pumpkins dark -> brightness pass T21 |
| T17 | N (router-normal) | done | weather_controller.gd, retro_post rain/flash, rain+thunder wavs | verified by H renders |
| T02 | N (router-normal) | done | knight_model.gd, part_builder.gd, knight_turntable | verified by H render; sword looks thin from the side (minor) |
| T04+T05 | N (router-normal) | done | pixelize_sprites.py, sprite_sheet_data.gd, pixel_sprite_3d.gd, hollow sheet | verified dirs/feet in renders; death framing widened in characters.json |
| T15 | H | done | tools/bake_world.*, src/levels/valdron/*, data/regions/*, prologue | overworld baked (2.3M tri verts after budget cuts); region triggers + rain verified in renders |
| T06 | E (router-easy) | done | assets/sprites/* (11 sheets, 3256 frames) | contact sheet checked by H; one non-fatal ERR_CANT_OPEN in bake log -> T21 |
| T19 | E (router-easy) | done | data/items/lore/{farmers_ledger,harvest_hymn,chapel_confession,hunters_warning}.tres | validator OK |
| T07 | N (router-normal) | done | sprite_creature_visual.gd, enemy.gd, enemy_data.gd, hollow.tscn, enemy data | verified by H (montage); baker now uses tools/sprite_baker/creature_rig.tscn (old rig scene) since hollow.tscn is sprite-based |
| T08 | N (router-normal) | done | prologue_cutscene.gd | verified by H Movie Maker sheet; H follow-up: rim light back, lie pose = full billboard + fixed side direction (PixelSprite3D.fixed_direction) |
| T21a | H | done | terrain.gdshader, grass_dry_tall.tres, thornfield_builder.gd, valdron_overworld.tscn, villager_model.gd, bake_sprites.sh | road muddy brown/pale in forest, brighter overworld env, denser dry grass, muted villager dyes (re-baked), bake_sprites expands variants |
| T22 | E (router-easy) | done | ROADMAP, GAME_DESIGN, ARCHITECTURE, rotten-crown/CLAUDE.md | phases renumbered (Phase 3 = graphics polish, localisation stays 8); H checked cottage count claim |
| T20 | N (router-normal) | done | level.gd (?tp=), web_perf.cjs, web_smoke_test.cjs | smoke PASS; spawn 8.25 / Hollowmere 6.25 / prologue 5.5 fps, prologue load 5.3 s (phase 2 build, same tool: 4.75 fps, 6.2 s) |
| review | router-reviewer | done | - | 3 blocking + 10 minor -> T24 (N) + T25 (H) |
| T24 | N (router-normal) | done | pixel_sprite_3d.gd, sprite_creature_visual.gd | findings 8,9,10,13; H read diff |
| T25 | H | done | grass_scatter, quality_manager, weather_controller, level, region_trigger, events, hud, bake_world, wood builder, baker | findings 1-6, 11a; verified headless (grass group 527, Low halves grass + no streaks, region re-entry restores fog/rain). Not done: 7 (32 m chunks: more draw calls, targets met), 11 C3 naming, horizon still runtime (cheap) |
| T23 | H | done | docs/ (web build), export_presets.cfg, bake_sprites.sh (build/.gdignore) | pck 30 MB -> 11.5 MB (raw sprite renders were imported+exported); smoke PASS, touch PASS; Medium: spawn 8, Hollowmere 6.25, prologue 5.25 fps, load 5.2 s (phase 2: ~5 / - / 4.75 / 6.2); AC6 prologue fps + load time not met in absolute terms |

## Phase 3b (quality upgrade after the user's Phase 3 report)
| task | tier used | status | files | note |
|---|---|---|---|---|
| plan 3b | H | approved by user (Blender route, no PixelLab) | .router/PLAN.md | skills: taste/pixel-art/pxl downloaded; install into the project denied by auto-mode classifier -> user to decide |
| U1 | H | done | docs/ART_DIRECTION.md | palettes, texel density, sprite scale |
| U2+U6 | N (router-normal) | done | tools/assets/*, assets/models (38 CC0 GLB), assets/textures/world (12) | verified gallery; pines sparse |
| U3 | N | done | tools/pixelize_sprites.py, tools/sprite_compare.py | crisp downscale, OKLab ramps, selective outline; verified compare sheets |
| U3c | N | done | sprite_sheet_data.gd, pixel_sprite_3d.gd, pixel_sprite.gdshader, test sheet | v2 runtime (indexed, trimmed); verified contact sheet; + extra_offset follow-up |
| U3b | N | done | tools/pixelize_sprites.py | v2 writer: material ramps, palette variants, L8 atlas |
| U4 | H | rendering | tools/blender/* (rig, materials, renderer, knight) | knight 150 px, 51 frames x 8 dirs; material-id pass |
| U5 | H | rendering | tools/blender/characters/{villager,creature}.py | 3 villager types + variants; hollow, mourner |
| R1 | H | done | retro_materials.gd, terrain shader/builder, asset_kit.gd | scanned textures on all procedural world surfaces |
| U7/U8/U9 | H (router-hard x3) | running | regions | parallel worktrees |
