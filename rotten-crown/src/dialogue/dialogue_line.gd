class_name DialogueLine
extends Resource
## One line of dialogue (contract C13). speaker "" is the knight's own thought.

enum Style { THOUGHT, ENTITY }

@export var speaker := ""
@export_multiline var text := ""
@export var style: Style = Style.THOUGHT
## Seconds the line stays after it has fully appeared.
@export var hold := 2.4
