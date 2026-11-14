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
| U4/U5 | H | done | assets/sprites/{knight,villager_man,villager_woman,villager_musician,hollow,mourner} | all Blender renders pixelized to v2 sheets; old villager_0..7 removed; prologue on new sheets |
| U6b | N (router-normal) | done | tools/assets/{fetch_opengameart,process_blend,build_oga}.py, 16 oga_* models | CC0 OpenGameArt houses + village props (no account needed) |
| U7 | H (router-hard) | done | thornfield_builder.gd, thornfield_props.gd, thornfield_field_props.gd, thornfield_wheat.gdshader | verified side-by-side with ref 1; +87k tris |
| U8 | H (router-hard) | done | hollowmere_builder.gd, hollowmere_{props,batch,village}.gd, hollowmere_flesh.gdshader | verified renders; tris ~flat, draw calls -27..51% |
| bake fix | H | done | tools/bake_world.sh | headless bakes saved grass MultiMesh with zero transforms -> bake under xvfb/opengl3 |
| size | H | done | export_presets.cfg | assets/models excluded from export (bake-only): pck 26.5 -> 18.8 MB |
| tint | H | done | pixel_sprite_3d.gd, enemy_data.gd, sprite_creature_visual.gd | creature sprite tint |
| perf check | H | measured | - | Medium, real grass: spawn 7.75, Hollowmere 6.75, prologue 5.75 fps, load 4.9 s (Phase 3: 8 / 6.25 / 5.25 / 5.2) |
| U9 / U14 | H (router-hard) | running | wood / UI | resumed after rate limit |
| U9 | H (router-hard) | done | whispering_wood_builder.gd, wood_props.gd, wood_mist/motes shaders (+ small level.gd/region_trigger.gd fix for overlapping triggers) | tree tunnel, verified vs ref 3 |
| U14 | H (router-hard) | done | UI theme+fonts (OFL), main menu, HUD, pause, inventory, web/shell.html launch page | taste-skill applied; smoke PASS |
| touch fix | H | done | touch_controls.gd | re-anchor on UI rescale (Low auto switch flung the camera 16 deg) |
| U10 | H (router-hard) | done | castle_props.gd, meadow_builder.gd, meadow_props.gd, meadow shaders | spawn view: Gothic gate, feast spill, plains landmarks |
| U13 publish | H | done | docs/ | smoke PASS, touch PASS; Medium: spawn 7.5-8.75, Hollowmere 7.5-7.75, prologue 4.5 fps (regressed: castle front dressing also built in the festive set -> follow-up), load 6.4-7 s; pck 25 MB |
| review 3b | router-reviewer | interrupted by rate limit | - | resume next session |

## Phase 3c
| task | tier | status | note |
|---|---|---|---|
| P0 | H | done | Pages via Actions workflow on this branch (githack blocked big files = the 17% hang) |
| P1 | N | done | tools/web_turn_test.cjs + DebugBridge render stats; cold-sweep spikes 600-780 ms |
| P2 | H | done | ShaderPrewarm behind the loading fade; after: Hollowmere cold max 317 ms (was 667), cold = warm |
| P3/P4 | H | partial | probe flags (hide:, nocutout, cutcheap...) found alpha-cut leaf cards = wood cost; bake lights them per vertex, no shadow receive (+19% wood, look kept) |
| P5 | E->H | done | festive castle front lighter |
| P6 | H | done | quality watchdog on sustained low fps |
| P7 | H | done | smoke + touch PASS; turn test Medium: spawn 5.2 fps sweep (max 433 vs 600), Hollowmere 4.4 (max 317 vs 667), wood 2.45 (was 2.11) |

## Phase 3d
| task | tier | status | note |
|---|---|---|---|
| D1 | H (me) | done | DialogueUI autoload (THOUGHT subtitles, ENTITY glitch window), wake_thoughts.tres, Level.wake_dialogue |
| D2 | N | done | screen fit: visualViewport shell, fullscreen+landscape on Wake up, UiSafeArea, web_fit_test 6 viewports OK |
| D3 | E | done | static_burst/static_loop + garble_1..4 (gen_audio.py witness) |
| D4+D6 models | H (rate-limited once, resumed) | done | Blender monsters.py/witnesses.py: steeple, grinner, bent, witness_star/root/chair v2 sheets |
| D5 | N | done | EnemyData attack styles LUNGE/STAB/LEAP/SLAM, skitter, tremble, SlamTelegraph |
| D6 runtime | H (me) | done | Witness (src/npc/witness.gd), 3 lines, placed in valdron_overworld.tscn; populator uses the new creatures |
| review | router-reviewer | done | 12 findings, all fixed (5a55da9) |
| D7 | H | done | smoke PASS, touch PASS (1 flake on slow software GL), perf ~ previous (spawn 4.0 vs 4.5, Hollowmere 1 vs 1 software) |

## Phase 3e
| task | tier | status | note |
|---|---|---|---|
| E1 | H | done | Godot 4.4.1 -> 4.7.1; VirtualJoystick -> TouchJoystick (4.7 native class); re-bake; parity ~0.5/255; steady web fps +35% |
| E6 | N | done | Android toolchain (JDK 21, SDK 36), arm64 APK ~58 MB; Compatibility renderer on Android too (Mobile/Vulkan changed the look) |
| E2 | N | done | FPS overlay: fps, 1% low, ms, draws; pause toggle + ?fps=1 |
| E5 | N | done | physics 30 Hz + interpolation, top-level camera rig, far enemies/witnesses parked, sprites idle off screen; physics ~3 ms -> ~0.6 ms/frame |
| E3+E4 | H (rate-limited once, resumed) | done | draws -21..-68% per pose (spawn 429->135); 6/8 poses <= 150; shadow stand-ins, colour-variant merge, range-sized cells, grass 3x3. DEVIATION: no vertex-colour light bake - measured unshadowed omni lights cost 0 extra draw calls in 4.7.1 |
| review | router-reviewer | done | 9 findings: fixed interpolation of tweened nodes, merged-chunk range spread, grass cull collapsed in vertex(), near sprites update, ?fps parse, APK link + version code. Not fixed: fixed signing key (committing a keystore was blocked) -> uninstall old APK before installing a new one |

## Phase 4a
| inc | tier | status | note |
|---|---|---|---|
| 1 | H (me) | done, published | moonlit-blue palette (runtime only) |
| 2 | H (me) | done, approved | world bible v1: kingdom_map.json + render_world_map.py + WORLD_BIBLE.md + map PNG |
| 3 | H (router-hard) | published, awaiting feedback | ForestBuilder + ForestTrees: ~2,800 trees (T1 0.8 / T2 2.2 / T3 3.0 per 100 m2), 3 silhouettes, MultiMesh 48 m chunks near/far, trunk colliders, WhisperingWood pocket removed (enemies/lore re-homed to Forest markers), fog 0.038. Probe (Low): draws <= 192 everywhere; prims <= 260k, deep_old 341k (over the 300k target). Scene 25.4 -> 15.9 MB, pck 32.7 -> 23.1 MB. I raised the agent's densities (1.4 -> 2.2 etc.) after the contact sheet read as open woodland. Weakness: dark, uniform blue; open look on the road itself (trunks keep 3.5 m from the centreline). |
| 4-S4 | H (router-hard) | done | kingdom walls + gate (from arena 941b339, cheaper), ward -> citadel (125,210) rot 180, Royal Keep sealed, paved King's Road (kerbs, 7 waymarkers, 5 lanterns), MeadowBuilder = empty plains outside only, world-edge colliders, signposts, save WORLD_VERSION 2, test_kingdom_layout 0 failures. Not taken from arena: netlify/hosting/docs/shell text. |
| 4-F4 | H (router-hard, rate-limited once, resumed) | done | 3,677 trees (T1 1.0 / T2 3.0 / T3 4.2), 7 styles, mesh < 26 m then 4-tri impostors (256 px atlas), ForestFloor kits (28.6k cards, 2.8k small, 495 large with colliders), green rot (glow + pulse), bark faces/hands rare, kingswood/cellar_hollow regions + deep triggers, smallest zone wins. Probe Low: all poses <= 190 draws, <= 250k prims. pck 22.9 MB. |
| 4 integrate | H (me) | published, awaiting feedback | merged both, brightened forest ambient/fill (content was unreadably dark), tests 0 failures, smoke OK, touch PASS |

## V5 (phone report: colour clash, floating grass, forest/Thornfield fps)
| task | tier | status | note |
|---|---|---|---|
| V5 | H | done (branch v5-work, not published) | root cause floating "grass": fog-free HorizonBackdrop seen between fogged trees (+289 unattached overhang clumps); depth fog ViewDistance (Kingswood 45 m, deep 34-36, villages 55, plains 70) drives all ranges; palette blue-grey; Low draws forest -55..-60%, Thornfield field 122 -> 91; tests 0 failures, smoke OK, touch PASS |

## V6 (phone report: floating moss, grain, path readability, too dark)
| task | tier | status | note |
|---|---|---|---|
| V6 | H | done (branch v6-work, not published) | root cause: 4,644 floor "hang" cards drawn to 13/17/21 m from the card while the host tree became a 32x64 impostor at 16/20/24 m from its foot (503 cards > 3 m from the nearest trunk); moss now baked into tree meshes (per-instance amount), free overhang clumps removed; corridors 1.0 -> 4.2 trunks/10 m of path edge; no grain, light dither, fog-fade far cards, 64x128 impostors; exposure/ambient/contrast lifted; Low probe all <= 99 draws / 153k prims; tests 0 failures, smoke OK, touch PASS, swap PASS |

## V7 (phone video: black ground, cheap tree pop, flat/random lighting) - plan approved 2026-11-13
| task | tier | status | note |
|---|---|---|---|
| baseline | H (me) | done | V6 shots at 8 poses (scratch v6shots); bottom-third luminance: road 16.3, cross 8.3, wood 8.2, spawn 16.7, thornfield 29.7, hollowmere 19.5, kingswood 9.0, plains 11.6. web_perf V6 (software GL): Low spawn 2.5 / hollowmere 1.75 fps, Medium 2.0 / 1.75 |
| V7-1 | H (router-hard) | done | project.godot shader_globals, moonlight.gdshaderinc, moonlight.gd, overworld MoonlightModel node | verified: import/run clean, validate OK; me: colour-space fix (unshaded helpers light in linear, return display; moon_color pushed linear) |
| V7-2 | H (router-hard) | done | moon_shade_baker.gd, bake_world.gd, assets/textures/world/moon_shade.png | 1040x980 L8, 4049 trees + 239 structures + 549 kits, +4 s bake, deterministic; paths lifted (ROAD_OPEN) so they read as lit corridors - accepted |
| V7-7 | N (router-normal) | done | grass, meadow_grass, thornfield_wheat, meadow_far shaders | per-vertex model ratio (calibrated to the clear-moon look, MOON_REF_IRR), shade+cloud, wind from global; brightness +0..7% vs V6; 0 shader errors; prologue/test unchanged |
| V7-3 | N (router-normal) | done | terrain.gdshader | custom light(): moon x min(shadow, canopy shade x cloud), lambert match 0.04/255 mean; tints renamed *_albedo (baked scn kept old values), GROUND_GAIN 2.2; bottom-third lum x1.6-4.5 (road 1.94); watch: Hollowmere path patches pale -> V7-8 |
| V7-4 | H (router-hard) | done | forest.gdshaderinc + forest_card/solid/floor_card | forest UNSHADED on the model (only 3/4049 trees near fixed omnis; carried lantern reproduced in shader); key+ambient per pixel; rigid wind sway by origin; trunk base identical, crowns move |
| V7-6 | H (router-hard) | done | forest.gdshaderinc, view_distance.gd | SHRINK_FADE removed; floor fades to fog_tint over 6 m at fog-relative range (capped by baked reach 22/30 m) |
| V7-5 | H (router-hard) | done | forest_atlas.gd, forest_far.gdshader, forest_trees.gd, tools/test_impostor_match.* | atlas 2048x640, 128x256 tiles, 4 views + normal atlas, coverage mips; match test 0 failures (mean <= 3.2/255, worst 9.9); Low probe max 101 draws / 165.5k prims; pck +1.24 MB. Finding: trunks under deep canopy near-black -> V7-8 |
| V7-8 | H (me) | done | forest.gdshaderinc (albedo_gain 1.7), terrain.gdshader (grass/dry albedo down), overworld tscn (sky ambient 0.26/0.3/0.44 + 0.1/0.1/0.12), re-bake both | trunks were near-black under the plain model (old colours relied on the fill) -> one gain on mesh+impostor; impostor test mean <= 4.9/255, per-view cap 10 -> 13 (scales with brightness). Bottom-third lum V6 -> V7: road 16.3->39.9, cross 8.3->36.8, wood 8.2->23.1, spawn 16.7->34.3, thornfield 29.7->42.0, hollowmere 19.5->35.8, kingswood 9.0->21.7, plains 11.6->40.6. NOTE terrain uniform defaults only apply after a re-bake (the bake stores them) |
| V7-9 | H (me) | decided, not measured on GPU | - | real-time moon shadows stay off on Low: the baked canopy map now gives every level ground shade; software-GL web_perf cannot measure GPU shadow cost, so enabling it on Low would be a blind fps risk on the phones that need Low most |
| V7-10a | H (me) | done | ../docs (local, not pushed) | publish OK; smoke OK (WebGL2, 0 shader/console errors), touch PASS, swap PASS. web_perf (software GL) V6 -> V7: Low spawn 2.5 -> 1.75, hollowmere 1.75 -> 1.75; Medium spawn 2.0 -> 1.5, hollowmere 1.75 -> 1.25 => AC6 FAILS (> 10%) -> V7-R fixes perf |
| V7-R review | router-reviewer | done | - | blocking: (1) floor fog_tint not pushed + FLOOR_FADE unused; (2) terrain ambient = separate env knob vs moon_ambient. optional: grass MOON_REF_IRR/wind tied to old defaults, impostor normals in camera axes, per-pixel pow x2 + vertex double fetches, cloud clock drift on pause, prologue without Moonlight node, lantern copy hard-coded, nits |
| V7-R | H (router-hard, resumed after rate limit) | done | shaders (moonlight/forest/grass/meadow/wheat/terrain), moonlight.gd, view_distance.gd, flicker_light.gd, player.tscn, region tres, project.godot, overworld + prologue tscn, re-baked overworld | all 9 findings fixed: fog_tint to every forest family + FLOOR_FADE; one sky ambient (Moonlight derives sky_ambient_top from the Environment each frame; terrain disables renderer ambient and adds moon_ambient in light(); lit StandardMaterial props keep the plain Environment ambient - logged decision); moon_ref_irr/wind_ref globals; single shade fetch, no matrix inverse; early discard, one pow, nearest-within-mip normal atlas (-9 ms at wood), per-vertex floor lighting; impostor normals from card axes turned half toward camera (pure fixed axes failed the match test); cloud_offset global (clock independent of TIME); lantern globals driven by FlickerLight; prologue MoonlightModel (no clouds/wind/shade map); albedo_gain 2.0. Look vs c6 within +-12% (road +5%, wood +10%, kingswood +10%, hollowmere +4%) |
| V7-R2 review | router-reviewer | done | - | blocking: impostor quad side read after wind sway (ZY quad top vertices got the wrong frame/UV in gusts; test runs windless) -> fixed (read before sway). optional fixed: NaN guard on zero-scale instances (grass pad + forest_unbasis), moon alignment warning tolerance, stale comments. optional kept: terrain sky ambient lives in the directional branch (needs one moon per scene; commented); lantern globals follow visibility not active camera (no player in cutscenes today) |
| V7-10 | H (me) | done | ../docs (published 2026-11-14) | verified myself: impostor match 0 failures, layout 0, forest walkable 0, validate OK, gdlint clean, visual_test only the known rain.wav exit leak; shots = agent's within 0.5 lum; smoke OK (WebGL2, 0 console errors), touch PASS, swap PASS; long-window web_perf V6 vs V7 below; before/after sheets + clip in rotten-crown/build/v7_compare |
| V7-10 perf | H (me) | done | - | long-window web_perf (12 s settle, 8 s window, software GL, V6 = HEAD~ docs served side by side): Low spawn 4.31 -> 4.31, hollowmere 3.75 -> 3.75 (0%); Medium spawn 3.31 -> 3.56 (+8%), hollowmere 2.63 -> 3.13 (+19%) => AC6 PASS. Known: native llvmpipe wood/Low ~9% slower than V6 (impostor mip sampling, required by AC5) |
| V7-11 | H (me) | done | web/shell.src.html, tools/export_web.sh, tools/build_web_shell.py, project.godot (config/build_label, config/build_stamp), src/ui/main_menu.*, CLAUDE.md | phone report: link never showed V7. Reproduced with a simulated phone holding the V6 service worker + cache: 4 reloads of index.html stayed on V6 (cache-first worker, browsers re-check workers only ~daily). Fix: build label V7 + UTC stamp on the launch page and the in-game menu; pack requested as index.pck?b=STAMP; page compares itself with build.txt and wipes workers/caches on mismatch; page forces registration.update(); export patches the worker (skipWaiting, claim, reload fetch). Simulation: V6-stuck phone reaches V7 on first open of / or /?v7, old cache replaced. smoke/touch/swap PASS |

## V8 (phone: lighting/colour immature; reference = user's edited screenshot; remove player light) - plan written, awaiting approval
| task | tier | status | note |
|---|---|---|---|
| recon | H (me) | done | measured REF vs V7 (see PLAN V8 diagnosis); grey comes from retro_post desaturation + env saturation 0.8 + grey fog; player light = Head/Lantern omni + shader lantern globals |
