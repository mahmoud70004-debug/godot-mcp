extends Node
## Localisation: Arabic (source language), English and Japanese.
## Every displayed string goes through Loc.t(). Translations are maps from the Arabic
## source text to the target text (data/i18n/en.json, data/i18n/ja.json).

signal language_changed

const LANGS := ["ar", "en", "ja"]
const NAMES := {"ar": "العربية", "en": "English", "ja": "日本語"}

var lang := "ar"
var _tables := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for l in ["en", "ja"]:
		var path := "res://data/i18n/%s.json" % l
		if FileAccess.file_exists(path):
			var d = JSON.parse_string(FileAccess.get_file_as_string(path))
			_tables[l] = d if typeof(d) == TYPE_DICTIONARY else {}
		else:
			_tables[l] = {}


func t(s: String) -> String:
	if lang == "ar" or s == "":
		return s
	return _tables[lang].get(s, s)


func has(s: String, l: String) -> bool:
	return _tables.get(l, {}).has(s)


func set_lang(l: String) -> void:
	if not l in LANGS or l == lang:
		return
	lang = l
	language_changed.emit()


func rtl() -> bool:
	return lang == "ar"


func align() -> HorizontalAlignment:
	return HORIZONTAL_ALIGNMENT_RIGHT if rtl() else HORIZONTAL_ALIGNMENT_LEFT


func dir() -> Control.TextDirection:
	return Control.TEXT_DIRECTION_RTL if rtl() else Control.TEXT_DIRECTION_LTR


func layout() -> Control.LayoutDirection:
	return Control.LAYOUT_DIRECTION_RTL if rtl() else Control.LAYOUT_DIRECTION_LTR


## Title font: Lalezar for Arabic, IM Fell English for Latin, Noto Serif JP for Japanese.
func title_font() -> Font:
	match lang:
		"en": return load("res://assets/fonts/IMFellEnglishSC.ttf")
		"ja": return load("res://assets/fonts/NotoSerifJP-subset.ttf")
	return load("res://assets/fonts/Lalezar.ttf")


## Menu font with a 19th-century feel.
func menu_font() -> Font:
	match lang:
		"en": return load("res://assets/fonts/IMFellEnglish.ttf")
		"ja": return load("res://assets/fonts/NotoSerifJP-subset.ttf")
	return load("res://assets/fonts/Lalezar.ttf")
