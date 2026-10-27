class_name RegionData
extends Resource
## One area of the kingdom of Valdron. Drives the region title card and
## per-region atmosphere (fog, ambient tint) in later phases.

@export var id := ""
@export var display_name := ""
@export var arabic_name := ""
@export var subtitle := ""
@export_multiline var description := ""
@export var fog_color := Color(0.09, 0.11, 0.09)
@export var fog_density := 0.05
@export var ambient_color := Color(0.16, 0.17, 0.2)
@export var music: AudioStream
## Development phase in which this region is built (see docs/ROADMAP.md).
@export var planned_phase := 1
