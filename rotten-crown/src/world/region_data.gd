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
## Levels with a ViewDistance node (the overworld) use depth fog instead of fog_density:
## the fog is complete at view_distance metres and nothing beyond it is drawn. 0 = the
## level's default.
@export var view_distance := 0.0
## How much of the night sky the fog veils (Environment.fog_sky_affect).
@export_range(0.0, 1.0) var fog_sky := 0.6
## Ground mist: extra fog on everything below the player's feet (valleys, slopes down);
## Environment.fog_height_density.
@export var mist_density := 0.0
## 0..1: how much the painted far horizon (HorizonBackdrop) is veiled; 1 hides it.
@export_range(0.0, 1.0) var horizon_haze := 1.0
@export var music: AudioStream
## Rain intensity while the player is in this region (WeatherController).
@export_range(0.0, 1.0) var rain := 0.0
## Development phase in which this region is built (see docs/ROADMAP.md).
@export var planned_phase := 1
