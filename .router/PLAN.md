# PLAN — Rotten Crown Phase 3: Graphics polish ("الصقل الرسومي")

Read `.router/CONTEXT.md` first. Project root for all paths below: `/home/user/godot-mcp/rotten-crown`.

## 1. Goal
Turn the single test courtyard into a **semi-open, foggy kingdom** built from the user's 4 reference
paintings, and switch all characters to **high-quality pixel-art sprites** — while making the web build
**faster** on weak phones (the user reported stutter on Phase 2).

References (user, 2026-10-28):
1. Lone farmhouse at the end of a field, dead tree, broken fence, tall pale dry grass bent by wind, stormy grey sky.
2. Over-the-Garden-Wall pumpkin fields with a winding dirt road to a village with a chapel steeple — but gothic,
   surreal, body horror, wrecked, cursed, bloody.
3. Night forest path: a tunnel of twisted arching trees, moonlight, blue mist at the far end, mossy verges.
4. Pixel-art armoured knight kneeling in rain and mist — the target look for ALL characters.

### Non-goals (later phases)
Combat feel/dodge/navmesh/bosses (Phase 4), journal & map UI (Phase 4), Arabic localisation (Phase 8),
hand-painted final art (Phase 8 — sprites here are pre-rendered from 3D models, Doom-style).

## 2. Acceptance criteria (all must be demonstrated)
- AC1 New gameplay level `src/levels/valdron/valdron_overworld.tscn` (prologue -> wake-up -> here). Contains:
  Moonlit Meadows spawn + the existing Outer Ward gate/courtyard, and roads to **Thornfield** (ref 1 farmstead,
  ~120 m SW), **Hollowmere** (ref 2 pumpkin village with chapel, ~220 m S), **Whispering Wood** (ref 3 tree tunnel
  path, links the meadow to Hollowmere). Rolling terrain, region title cards, signposts at junctions.
- AC2 No runtime procedural generation in shipped levels: world + prologue scenery are **baked** to resources by
  `tools/bake_world.sh`; scenes load prebuilt meshes. Re-running the bake is deterministic.
- AC3 Characters are `PixelSprite3D` billboards (8 directions, animated, shaded, fogged): knight + villagers in the
  prologue, Hollow + Mourner in gameplay. No 3D character meshes are instanced at runtime.
- AC4 Weather: rain (post-process streaks + audio) and occasional lightning in Thornfield/meadow; forest has
  blue mist + moon shafts. Toggle via WeatherController exports.
- AC5 Quality setting Low/Medium/High in the pause menu, persisted; auto-downgrade to Low if gameplay averages
  < 40 FPS for 8 s (one-time, with a message).
- AC6 Performance (software Chromium, `tools/web_perf.cjs`): gameplay at spawn >= 6.25 FPS (Phase-1 baseline),
  in Hollowmere >= 5.0; prologue >= 6.0; prologue load (tap -> scene) <= 3.5 s.
- AC7 Checks green: validate_project.py, gdparse + gdlint, headless import + 120-frame run of overworld and
  prologue with no ERROR, web_smoke_test.cjs, web_touch_repro.cjs PASS.
- AC8 Review shots of each area (render_shots.sh) look like their reference; web build published to Pages.

## 3. Decisions
- D1 **Bake, don't generate at runtime.** Builders stay `@tool` GDScript (editable, deterministic), but a headless
  bake script saves their output (merged ArrayMeshes, MultiMeshes, HeightMapShape3D) into `.res` files and a
  `*_baked.tscn`. Runtime cost and load time drop; phones no longer run GDScript vertex loops.
- D2 **Sprites pre-rendered from detailed 3D rigs** (Doom/Diablo technique): rigs can be as detailed as we like
  because they only exist offline. Baker renders 8 dirs x frames at 256 px; Python pixelizer downsizes
  (humans ~64 px tall), quantizes palette, adds 1 px outline, packs sheets. Enemies are baked with their head
  always turned toward the viewer in every direction — an uncanny sprite trick that replaces the runtime
  head-tracking.
- D3 **Terrain**: noise heightmap (2 m grid) over x in [-260,260], z in [-70,450]; flattened plateaus for the
  castle and villages; roads as polylines carved 0.15 m and painted by vertex colour; chunked 32 m meshes with
  `terrain.gdshader` (lit, pixel-quantized world-space texturing, 3 masks); one HeightMapShape3D collider
  (uniform scale 2, heights pre-divided by 2).
- D4 Keep visibility short and moody: fog ~0.022-0.03, chunk `visibility_range_end` 150 (terrain),
  40 (grass), 90 (props). Horizon silhouettes stay as the far backdrop.
- D5 Sky clouds: replace per-pixel fbm loop with one seamless NoiseTexture2D lookup (+1 detail lookup).
- D6 Rain is a post-process layer (no particles); lightning = short sky/ambient flash + thunder.
- D7 Quality: Low = 480x270 content scale, no shadows, grass x0.5, no rain streak layer; Medium = 640x360,
  shadows 1024 / 25 m, grass x1; High = Medium + shadows 2048 / 40 m + grass x1.4.

## 4. Contracts (implement exactly; cheap agents build against these)

### C1 Sprite sheet data — `src/rendering/sprite_sheet_data.gd`
```gdscript
class_name SpriteSheetData extends Resource
@export var texture: Texture2D
@export var frame_size := Vector2i(64, 80)      # pixels per frame
@export var directions := 8                     # dir 0 = facing camera (front), then clockwise every 45 deg
@export var anims: Dictionary = {}              # name -> {"row": int, "frames": int, "fps": float, "loop": bool}
@export var pixel_size := 0.028                 # metres per sprite pixel
@export var foot_offset_px := 2                 # transparent pixels below the feet
# Sheet layout: row = anims[name].row + dir ; column = frame index.
```
Generated as `.tres` by the pixelizer next to the sheet PNG: `assets/sprites/<char>/<char>.png|.tres`.

### C2 `PixelSprite3D` — `src/rendering/pixel_sprite_3d.gd`
```gdscript
class_name PixelSprite3D extends Sprite3D
signal animation_finished(anim: StringName)
@export var sheet: SpriteSheetData
@export var anim: StringName = &"idle"
@export var speed_scale := 1.0
func play(name: StringName, restart := false) -> void
func get_direction_index() -> int            # from active camera vs global_basis forward (-Z = facing)
func flash(color := Color(1, 0.2, 0.15), time := 0.15) -> void
```
Billboard FIXED_Y, nearest filter, alpha-cut discard, shaded = true, double-sided, centred so feet sit at node
origin. Non-looping anims hold the last frame and emit `animation_finished`. One draw call per character.

### C3 Rig sampling (bake-time) — `src/characters/humanoid_rig.gd`, `src/enemies/creature_rig.gd`
```gdscript
func pose_at(anim: StringName, t: float) -> void   # deterministic pose, no _process accumulation
# HumanoidRig anims: idle, walk, dance, cheer, music, toast, stretch, lie
# CreatureRig anims: idle, walk, windup, strike, stagger, death ; plus `look_at_viewer: Vector3` (world pos)
```

### C4 Sprite baker CLI — `tools/sprite_baker/`
`tools/bake_sprites.sh <char|all>`: runs `sprite_baker.tscn` under xvfb (opengl3), writes raw frames to
`build/sprites_raw/<char>/<anim>_<dir>_<frame>.png`, then `python3 tools/pixelize_sprites.py <char>` writes
C1 outputs. Character specs (anims, frame counts, fps, loop, target height px, palette size) live in
`tools/sprite_baker/characters.json`.

### C5 Enemy visual — `src/enemies/sprite_creature_visual.gd` (replaces CreatureRig at runtime)
Same methods Enemy already calls: `setup(data)`, `set_look_target(n)`, `set_move_speed(s)`, `play_windup(d)`,
`play_strike()`, `play_recover()`, `play_stagger()`, `flash()`, `play_death() -> Signal`. Adds runtime twitch
(brief sprite offset/tilt jolts). `EnemyData.sprite_sheet: SpriteSheetData` selects the sheet.

### C6 World builders & bake
- `src/world/terrain_builder.gd` (`TerrainBuilder`, @tool): `build(root: Node3D, spec: TerrainSpec) -> void`;
  `height_at(x, z) -> float` (also used by builders to place props on the ground).
- `src/world/props/prop_kit.gd` (`PropKit`, static): fence_run, dead_tree, gnarled_tree, pumpkin, scarecrow,
  signpost, cottage (OTGW style), chapel, cart_wreck — all returning Node3D, using RetroMaterials.
- `src/world/regions/{thornfield,hollowmere,whispering_wood}_builder.gd` (@tool): `build(root, terrain)`.
- `tools/bake_world.gd` + `tools/bake_world.sh`: instantiates builders, runs MeshMerger, saves to
  `src/levels/valdron/baked/*.res` and `*_baked.tscn`; also bakes the prologue festival blockout.

### C7 Weather — `src/world/weather_controller.gd` (`WeatherController`, Node)
`@export rain := 0.0..1.0`, `@export lightning_interval := Vector2(14, 30)`, `@export environment: WorldEnvironment`,
`@export post: CanvasLayer`; drives post uniforms `rain_amount`, `flash`, and plays rain/thunder audio.

### C8 Quality — `Settings.quality: int` (0 Low, 1 Medium, 2 High), `Events.quality_changed(level)`;
`src/rendering/quality_manager.gd` (autoload `Quality`) applies content scale, shadows, grass density
(group "grass_chunks" visibility), post features.

### C9 Overworld layout (metres; -Z = towards the castle; the existing Outer Ward/meadow sit at the origin, flat at y=0)
- Terrain: `TerrainSpec` min (-260,-70) max (260,450), flat_center (0,10) r 58 (+45 falloff). Query ground with
  `terrain.ground(x, z)` / `terrain.height_at(x, z)` — never assume y=0 outside the flat circle.
- Roads (xz polylines): main road gate -> Hollowmere `(0,10) (0,60) (-10,120) (5,200) (10,270) (20,322)`;
  farm track `(-10,120) (-60,136) (-116,148)`; forest path `(0,60) (45,72) (100,112) (140,172) (130,242) (82,300) (34,322)`.
- **Thornfield** (ref 1): farmhouse at (-122,152), plateau Vector4(-122,152,16,14); dry field Vector3(-95,128,58)
  of tall pale grass on both sides of the farm track; huge dead tree at (-104,146); broken fences along the track.
- **Hollowmere** (ref 2): village plateau Vector4(22,338,44,24) with ~8 cottages + chapel at (30,368);
  pumpkin fields both sides of the main road z 236..304 (Vector3(-8,270,40) dry/field paint), split-rail fences.
- **Whispering Wood** (ref 3): forest zones Vector3 along the forest path: (60,85,30) (110,125,34) (140,180,34)
  (132,240,34) (96,292,30); gnarled trees in two rows 3.5-5 m either side of the path, limbs arching over it.
- Region builders: `class_name <X>Builder extends RefCounted`, `static func build(root: Node3D, terrain: TerrainBuilder,
  rng: RandomNumberGenerator) -> Node3D` returning a Node3D named after the region that contains its props plus
  `Marker3D` children named `Spawn_Enemy_N`, `Lore_N`, `Pickup_N`, `Light_N`, and one `RegionTrigger` area marker
  `Trigger` (Marker3D with meta "radius"). Grass via `GrassScatter.scatter(...)` with
  `res://assets/materials/grass_field.tres` / `grass_dry_tall.tres`. All meshes StandardMaterial3D (mergeable),
  ooze/blood splats via the existing ooze shader with `MeshMerger.SEED_META`. Keep omni lights <= 3 per region,
  range <= 7 m, no shadows. Terrain spec additions (plateaus/fields/forests) are owned by the overworld assembler (T15),
  builders only document what they assume in their header comment.

## 5. Tasks
Tiers: E haiku, N sonnet, H opus (me). `[ ]` open, `[x]` done (see PROGRESS.md).

| id | title | tier | depends | files | done_check |
|---|---|---|---|---|---|
| T01 | Rig `pose_at` + new poses (toast/stretch/lie), CreatureRig `pose_at` + viewer look | N | - | humanoid_rig.gd, creature_rig.gd, knight_model.gd | gdparse; prologue still renders (Movie Maker 40 frames, no ERROR) |
| T02 | High-detail Gothic knight rig (fluted plate, faulds, gauntlets, cape folds) for baking | N | T01 | knight_model.gd, part_builder.gd | render a turntable frame of KnightModel; looks closer to ref 4 |
| T03 | Sprite baker scene + script + characters.json + bake_sprites.sh | H | T01 | tools/sprite_baker/*, tools/bake_sprites.sh | raw frames exist for `knight` (8 dirs x anims) |
| T04 | Pixelizer (downscale, palette, outline, pack, write .tres per C1) | N | T03 | tools/pixelize_sprites.py, src/rendering/sprite_sheet_data.gd | knight sheet + .tres generated; contact image looks like pixel art |
| T05 | PixelSprite3D runtime (C2) | N | T04 | src/rendering/pixel_sprite_3d.gd | test scene shows knight sprite turning through 8 dirs; validate passes |
| T06 | Bake all characters: knight, 8 villager variants, hollow, mourner | E | T04,T05 | characters.json, assets/sprites/** | sheets + .tres for all 11 characters |
| T07 | SpriteCreatureVisual (C5) + hollow.tscn swap + EnemyData.sprite_sheet | N | T05,T06 | src/enemies/*, data/enemies/*.tres | headless run of overworld: no ERROR; enemy states animate in a review render |
| T08 | Prologue on sprites (SpriteActor helpers in director) | N | T05,T06 | src/cutscenes/prologue_cutscene.gd | Movie Maker render of prologue: all beats present, no 3D villagers |
| T09 | TerrainBuilder + terrain.gdshader + HeightMapShape collider (+ GrassScatter) | H | - | src/world/terrain_builder.gd, assets/shaders/terrain.gdshader | review shot of hills/roads; player walks without falling (headless walk test) |
| T10 | PropKit (fences, trees, pumpkins, scarecrow, signpost, cottage, chapel, cart) | N | - | src/world/props/prop_kit.gd | gdparse; prop gallery render |
| T11 | Tall dry grass + field grass variants (grass.gdshader params, wind gusts) | E | - | assets/shaders/grass.gdshader | render shows pale bent tall grass (ref 1) |
| T12 | Thornfield builder (ref 1) | N | T09,T10,T11 | src/world/regions/thornfield_builder.gd | review shot vs ref 1 |
| T13 | Hollowmere builder: pumpkin fields, road, village, chapel, gore/ruin (ref 2) | N | T09,T10,T11 | src/world/regions/hollowmere_builder.gd | review shot vs ref 2 |
| T14 | Whispering Wood builder: arched tree tunnel, moss, moon shafts, blue mist (ref 3) | N | T09,T10 | src/world/regions/whispering_wood_builder.gd, assets/shaders/moon_shaft.gdshader | review shot vs ref 3 |
| T15 | Bake tool + overworld scene assembly + level flow (prologue -> overworld), region data, signposts | H | T07,T09,T12-T14 | tools/bake_world.*, src/levels/valdron/*, data/regions/*, src/cutscenes/prologue_cutscene.gd | AC1, AC2; headless run no ERROR |
| T16 | Sky cloud texture optimisation (D5) | E | - | assets/shaders/night_sky.gdshader, scenes using it | visual parity render; web_perf not worse |
| T17 | WeatherController + rain/flash post layer + rain/thunder audio (C7) | N | T15 | weather_controller.gd, retro_post.gdshader, gen_audio.py | rain render; lightning flash frame |
| T18 | Quality manager + pause menu option + auto-downgrade (C8) | N | T15 | quality_manager.gd, settings.gd, events.gd, hud.* , project.godot | toggling changes content scale/shadows; persisted |
| T19 | Lore + enemies + pickups placed in the new regions | E | T15 | data/items/lore/*, overworld scene | validate passes; items reachable |
| T20 | Tests: smoke via overworld, perf at spawn+Hollowmere, prologue load time | N | T15 | tools/web_*.cjs | AC6 numbers printed |
| T21 | Integrate, perf-tune, router-reviewer diff review, fix findings | H | all | - | AC1-AC8 |
| T22 | Docs: ROADMAP (Phase 3 = graphics polish, renumber), GAME_DESIGN (map, art pipeline), ARCHITECTURE | E | T21 | docs/*.md, README.md, CLAUDE.md | docs mention every new system |
| T23 | Publish web build, verify Pages | H | T21,T22 | ../docs | Pages build.txt matches |
