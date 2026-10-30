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

**Direction convention (shared by baker and runtime — do not change one without the other):**
the baker renders direction `k` (0..dirs-1) with the camera on world +Z looking -Z and the model yawed by
`theta_k = PI + k * TAU / dirs` (k=0: the character faces the camera). At runtime, with
`v = global_basis.inverse() * (camera_pos - global_position)` (y ignored) and `phi = atan2(v.x, v.z)`,
`k = posmod(roundi((-phi - PI) / (TAU / dirs)), dirs)`. Implement it once as
`static func direction_index(local_to_camera: Vector3, dirs: int) -> int` in SpriteSheetData.
Raw frames: `build/sprites_raw/<char>/<anim>_<k>_<frame>.png` (RGBA, transparent background) plus
`build/sprites_raw/<char>/meta.json` = {"dirs", "render_px", "camera_size", "anims": {name: {"frames","fps","loop"}}}.

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

---

# PLAN — Phase 3b: quality upgrade (after the user's Phase 3 test report)

## Feedback (user, phone test)
- Pixel art and characters weak: the knight looks smeared, its animation unclear and low quality -> denser pixels, more frames, finer detail.
- Exploration, villages and the Whispering Wood path not good enough in graphics quality, detail and creativity.
- User suggested drawing skills (Taste skill, Figma) and offered to connect drawing tools.

## Diagnosis (H)
1. Sprite density: the knight sheet is 76 px tall but fills ~180 of the 360 internal rows in close shots -> upscaled ~2.4x. The pixelizer area-averages (blur) before quantising -> "smeared".
2. Source models are boxes and cylinders, so even a perfect pixelizer has no detail to keep. Animation is procedural (sin waves) with few frames.
3. The world is procedural primitives with tiny noise textures: no material detail, no silhouettes, repetitive.
4. Skills: Taste skill = web-page art direction (useful later for menus and HUD only); Figma = UI vector design (needs authorisation, not a game-art tool). Relevant: pixel-art knowledge skills, pxl (pixel art as code), PixelLab (AI pixel characters; paid API key), Blender (installed in the session, headless works), Poly Haven / ambientCG / Quaternius CC0 assets (reachable).

## Decisions
- D1' Characters are modelled, rigged and animated in Blender (rigid plate/limb pieces parented to bones, no skinning needed),
  rendered there in 8 directions, then pixelized v2. Keyframed animations with anticipation/overshoot and more frames.
- D2' Sprite heights: knight 150 px, villagers 120, hollow 140, mourner 150 (pixel_size halves, so in-world size stays).
- D3' Pixelizer v2: nearest/majority downscale (no blur), per-character hue-shifted palette ramps, selective (coloured) outline,
  highlight preservation; follows the pixel-art skill rules.
- D4' World = CC0 scanned assets (Poly Haven, ambientCG, Quaternius) processed offline in Blender: decimated to a budget,
  textures baked/downscaled to 128-256 px, palette-quantised, nearest filtering (PS1/"Dusk" look under the retro post), GLB with LODs.
- D5' Regions rebuilt as composed sets following references 1-3 (hero views first, then filler), instancing for repeats.
- D6' Performance gate: no regression vs Phase 3 (software Chromium, Medium: spawn >= 8, Hollowmere >= 6.25, prologue >= 5.25 fps).
- D7' Optional PixelLab route for characters only if the user provides an API key (env secret, never committed).

## Tasks
| id | title | tier | depends |
|---|---|---|---|
| U1 | Art direction sheet (palette ramps per region, texel density, sprite scale, silhouettes) docs/ART_DIRECTION.md | H | - |
| U2 | Blender pipeline: tools/blender/{fetch_assets.py, process_asset.py, render_sprites.py}, CC0 licence log | H | - |
| U3 | Pixelizer v2 (D3') + comparison sheet old/new on the current knight renders | N | - |
| U4 | Knight remake in Blender: gothic plate (fluted, bevelled), mail, tabard, plume; anims idle 8, walk 12, toast 8, cheer 10, stretch 12, lie | H | U2,U3 |
| U5 | Villagers (shared rig, 8 variants, cloth/props) and creatures (hollow, mourner: body-horror anatomy) remade + anims | N | U4 |
| U6 | World asset kit: ~25 CC0 props/trees/rocks + ~12 ground/wall/roof/bark textures at retro resolution | N | U2 |
| U7 | Thornfield rebuilt to reference 1 (field to the lone farmhouse, wheat, scarecrows, fences, fog) | H | U6 |
| U8 | Hollowmere rebuilt to reference 2 (path through pumpkin fields, gothic houses, chapel, body horror, ruin, blood) | H | U6 |
| U9 | Whispering Wood rebuilt to reference 3 (dense real trunks, canopy, ferns, roots, logs, moon shafts, fireflies) | H | U6 |
| U10 | Pixel decals and signage with pxl (blood, curse sigils, signposts) | N | skill install |
| U11 | Perf pass (instancing, LOD, atlases, visibility) against D6' | H | U4-U10 |
| U12 | Docs | E | U11 |
| U13 | Publish web build + tests + report | H | U12 |

## Contract C10 — sprite sheets v2 (indexed, trimmed, material ramps)   [replaces C1 for Phase 3b]
Why: 150 px characters with 8 dirs x ~50 frames would need ~7680 px tall RGBA sheets (~40 MB VRAM, over the
4096 px texture limit of many phones). v2 = 1 byte/px index atlas of trimmed frames + a tiny palette texture.

Raw renders (Blender, rc_blender/sprite_render.py): next to every `<anim>_<k>_<f>.png` an `<anim>_<k>_<f>_id.png`
(8-bit grey, value = material_pass_index * 16, 0 = background; decode round(v / 16)). meta.json gains
`"materials": {"<pass_index>": {"name": str, "shades": int}}` and optional `"variants": [{"<material name>": [r, g, b]}]`
(palette-swap recolours; variant 0 = as rendered).

Pixelizer output (tools/pixelize_sprites.py): `<char>.png` = L8 index atlas (0 transparent), trimmed frames shelf-packed,
width <= 2048, height <= 4096; `<char>_palette.png` = RGBA 256 x variants (row v = variant v); a `.png.import`
for both forcing lossless, no mipmaps, no VRAM compression; and `<char>.tres`:
```gdscript
class_name SpriteSheetData extends Resource
@export var texture: Texture2D            # index atlas
@export var palette: Texture2D            # 256 x variants RGBA
@export var variants := 1
@export var frame_size := Vector2i()      # untrimmed box shared by all frames
@export var frames := PackedInt32Array()  # 6 ints per frame: atlas x, y, w, h, x/y of the rect's top-left inside the box
@export var directions := 8
@export var anims: Dictionary = {}        # name -> {"start", "frames", "fps", "loop"}; index = start + dir * frames + f
@export var pixel_size := 0.014
@export var foot_offset_px := 2           # box rows below the feet
static func direction_index(local_to_camera: Vector3, dirs: int) -> int   # unchanged convention
```
Palette: per material, the opaque pixels of that material are clustered into `shades` luminance-ordered colours
(OKLab, mild hue shift: darks cooler, lights warmer); index = running offset of the material + shade (+1, 0 is
transparent). Variant rows recolour each material's ramp to the variant colour keeping the ramp's lightness profile.
Runtime: PixelSprite3D keeps its API (+ `variant: int`), uses one cached ShaderMaterial per (sheet, variant):
index lookup with nearest sampling -> palette colour * vertex COLOR (modulate/flash), discard index 0, FIXED_Y
billboard in the vertex shader, shaded. Per frame it sets region_rect and offset from `frames`.
| U14 | UI pass with taste-skill principles: main menu, pause/quality, inventory, HUD, region title cards, and the web launch page that wraps the game (the skill's "page" run) | H | U11 |

---

# PLAN — Phase 3c: performance on weak/mid phones + loading fix (user report after Phase 3b)

## Report
1. Low performance on weak and mid phones; noticeable frame drops when turning the camera; weak phones struggle to move around. Goal: smoother and faster with no loss of graphics quality.
2. Redmi Note 11 / Chrome: loading stops at 17%.

## Diagnosis (H)
- (2) The test link was the raw.githack fallback (GitHub Pages now serves another branch's preview, deployed by a GitHub
  Actions workflow from arena/9d0420eb-godot-mcp). githack now answers index.wasm with an HTML page and index.pck with 403:
  large files are blocked, so the download stalls. Not a phone bug. Fix = real hosting (Pages) + a test on the public URL.
- (1) Drops while turning = first-sight shader/material compilation in the Compatibility renderer (each new material in view
  compiles on the main thread), plus many draw calls (kit models keep one material each) and per-light passes.

## Tasks
| id | title | tier |
|---|---|---|
| P0 | Hosting: deploy docs/ to GitHub Pages again (Actions workflow on this branch, or the user switches Pages back to branch /docs) + smoke test on the public URL | H |
| P1 | Measurement: web_perf turn test (360 deg yaw sweep at spawn / Hollowmere / wood: avg fps, p95 and max frame ms, hitches > 100 ms) + CPU-throttled run (Chrome CPU x4, weak-phone proxy) + DebugBridge draw calls / primitives / process time | N |
| P2 | Shader pre-warm: at level load (behind the fade) draw every unique material once (overworld, prologue) so nothing compiles mid-game; same for sprites/post/sky | H |
| P3 | Draw calls: share/merge kit-model materials (atlas or per-texture dedupe), merge across bigger cells for far props, cull small props earlier with fade | N |
| P4 | Light/shadow budget: omni lights only touch nearby merged chunks; shadow casters limited to near hero meshes; directional shadow distance per quality | N |
| P5 | Prologue regression: festive castle front lighter (it is mostly seen from above) | E |
| P6 | Weak-phone path: auto quality re-check after the first minute and on sustained drops (not only once), keep UI crisp | N |
| P7 | Verify all, publish, report | H |
Gate: no visible quality change at Medium/High (side-by-side renders), turn test hitches eliminated, avg fps up.

---

# PLAN — Phase 3d: the knight's inner voice, screen fit, new creatures and the Witnesses (user request)

## Request
1. Inner monologue as subtitles at the bottom after waking ("What happened?", "Where is everyone?"), plus an adaptive
   fullscreen/screen-fit so bottom text is never cut off on some phones.
2. Replace the creatures: 3 new monster types with new attack styles, inspired by the user's two weirdcore reference boards
   (/root/.claude/uploads/bbd3ba3c-e2c7-5ce1-b8e0-8b1a5b7ac4eb/51fc010b-image.jpg, e898b306-image.jpg): non-human, creepy,
   surreal faces. Plus harmless side entities that appear beside/in front of the knight when he wakes, speak garbled
   frightening words with radio static, then a dialogue window shows their line ("Everyone exploded.", "Did you see the
   child? He grew so big."). Gothic + surreal + weirdcore; creative freedom.

## Designs
Monsters (Blender sprites, 8 dirs, same pipeline):
- THE STEEPLE: a hooded cone-skull on a crouched black body folded over six too-long stilt legs (board 1, top left). Slow,
  stalks; attack = long-reach stab with the two front legs after a long tremble (dodge window); 3.2 m reach.
- THE GRINNER: pale, starved, a face that is mostly grin, crawls on all fours with arms twice too long and spider fingers,
  head upside down (board 2, ceiling crawler). Fast skitter in bursts, freezes when looked at directly, attack = leap + rake.
- THE BENT ONE: a black arched giant walking on four impossibly long limbs, tiny head hanging under the arch (board 2,
  street-light walker). Very slow, huge; attack = rises and slams down (area hit, telegraphed by its shadow).
Witnesses (harmless, weirdcore; static + garbled speech + a line in a dialogue window, then they are gone):
- THE STAR-EYED GENTLEMAN: a man in a black suit whose head is a five-pointed star with one huge eye (board 1, bottom
  right) - stands beside the knight when he wakes: "Everyone exploded."
- THE ROOT SAINT: a pale figure whose arms are branching roots, floating over the field (board 1, bottom left) - Thornfield:
  "Did you see the child? He grew so big."
- THE CHAIR MAN: a long-necked, top-hatted figure sitting on a too-tall chair, head tilted 90 degrees (board 2, bottom
  left) - Hollowmere: a third hint line.

## Tasks
| id | title | tier |
|---|---|---|
| D1 | Dialogue system: DialogueLine/DialogueSequence data, Events.dialogue_requested, bottom subtitle (inner voice, italic, typed out) and entity window (glitch, static) in the HUD; wake-up monologue sequence + a few region thoughts | H |
| D2 | Screen fit: launch page uses dynamic viewport height (100dvh + visualViewport), fullscreen + landscape on Wake up, Godot stretch aspect "expand" with safe margins so HUD/subtitles never fall off; Playwright check at 19.5:9, 20:9, 16:9, 4:3 with browser bars | N |
| D3 | Audio: radio static + garbled reversed whisper voices (tools/gen_audio.py) | E |
| D4 | Monster models + anims in Blender (Steeple, Grinner, Bent One) -> v2 sheets | H |
| D5 | Monster behaviours: Enemy subclasses / EnemyData (reach, telegraph, burst speed, freeze-when-watched, area slam); populator uses the 3 new types instead of hollow/mourner | N |
| D6 | Witnesses: models in Blender + Witness scene (idle twitch, faces the player, static + voice, dialogue window, vanishes); wake-up placement beside the knight + 2 regions | N |
| D7 | Verify (renders, smoke/touch/turn tests), docs, publish | H |

## Contracts (Phase 3d)
- C11 creature sheets: assets/sprites/{steeple,grinner,bent}/ (v2, C10), anims exactly idle(loop), walk(loop), windup, strike,
  stagger, death (one-shots) - SpriteCreatureVisual keeps working; data/enemies/{steeple,grinner,bent}.tres.
- C12 witness sheets: assets/sprites/{witness_star,witness_root,witness_chair}/ (v2), anims idle(loop), speak(loop).
- C13 dialogue: `DialogueLine` Resource {speaker: String ("" = the knight's thought), text: String, style: int (0 THOUGHT
  bottom subtitle, 1 ENTITY glitch window), hold: float seconds}; `Events.dialogue_requested(lines: Array)`;
  `Events.dialogue_finished`; UI = autoload scene `Dialogue` (CanvasLayer), anchored to the bottom with safe margins.
- C14 audio: assets/audio/sfx/static_burst.wav, static_loop.wav (loop), assets/audio/voices/garble_1..4.wav.

---
# Phase 3e — Engine and performance (target: steady 60 fps on most phones, same look)

## Goal / acceptance
- Same picture: before/after render_shots at fixed poses (spawn, Hollowmere, wood, Thornfield, prologue) look the same.
- Draw calls in typical views <= 150 (now 490-620), objects drawn <= 400 (now 1200-1400), per-object light passes cut.
- No hitches: turn test max frame within 2x median (software GL proxy).
- Real phones: an in-game FPS / 1%-low overlay so the user can report true numbers (we have no phone GPU here).
- Native Android APK (Mobile renderer, Vulkan, GLES3 fallback) downloadable from the Pages site; the web build stays for quick tests.
- Honest limit: in a browser (WebGL2, one thread) a locked 60 on weak phones cannot be promised; the APK is the real 60 fps path.

## Decisions
- Upgrade Godot 4.4.1 -> 4.7.1-stable (latest stable here): WASM SIMD on web, newer Compatibility/Mobile renderers. Re-import and re-bake everything.
- Static lights baked into vertex colour at bake time (keeps the look, removes per-light draw passes); only moving lights stay dynamic.
- Bigger merge cells + far-region HLOD meshes; visibility ranges everywhere.
- Physics interpolation on, physics 30 Hz; far enemies/sprites stop processing.

## Tasks
| id | tier | depends | what | done_check |
|---|---|---|---|---|
| E1 | H | - | Godot 4.7.1 upgrade: setup script, templates, convert project, fix API breaks, re-bake, web smoke | headless runs clean, smoke PASS, shots match |
| E2 | N | E1 | FPS overlay (avg, 1% low, frame ms) toggled in pause menu and ?fps=1 | visible in smoke screenshot |
| E3 | H | E1 | draw-call diet: bigger merge cells, HLOD for far regions, grass chunking, visibility ranges | rcState.render draw_calls <= 150 at spawn/Hollowmere/wood |
| E4 | H | E1 | bake static lights into vertex colour; cap dynamic lights | same shots, fewer draw passes |
| E5 | N | E1 | CPU: physics interpolation + 30 Hz, process culling for far enemies/Witnesses/sprites | process ms down, gameplay tests PASS |
| E6 | H | E1 | Android APK export (SDK+JDK in container, debug keystore), APK in docs/ + link on launch page | APK builds, installs config valid (aapt dump), size noted |
| E7 | H | all | verify (shots, turn/perf/touch/fit tests), router-reviewer, publish, push | public build.txt matches, smoke on public URL |
