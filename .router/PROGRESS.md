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
