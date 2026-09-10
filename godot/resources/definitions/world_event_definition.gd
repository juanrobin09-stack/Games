class_name WorldEventDefinition
extends Resource
## Ports data/types.ts's WorldEventDefinition + data/events.ts's 6 entries.

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var options: Array[EventOption] = []
## When set, this event only ever appears in this zone id (and is
## preferred there). Empty means it can appear in any zone.
@export var zone_id: String = ""
