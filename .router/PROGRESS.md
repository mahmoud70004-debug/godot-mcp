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
