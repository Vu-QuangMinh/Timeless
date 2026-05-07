## Character
## Base class for all characters (player and guard). Holds stats, class definition,
## carried weight, body weight, and carried item values.
## Does NOT handle input, selection, pathing, or visual rendering directly.

class_name Character
extends CharacterBody2D

enum CharacterClass { BRAWLER, CAT_BURGLAR, HACKER, APPRENTICE }

const CLASS_STATS := {
	CharacterClass.BRAWLER:     { "str": 3, "int": 0, "agi": 1 },
	CharacterClass.CAT_BURGLAR: { "str": 0, "int": 1, "agi": 3 },
	CharacterClass.HACKER:      { "str": 1, "int": 3, "agi": 0 },
	CharacterClass.APPRENTICE:  { "str": 1, "int": 1, "agi": 1 },
}

const CLASS_NAMES := {
	CharacterClass.BRAWLER:     "Brawler",
	CharacterClass.CAT_BURGLAR: "Cat Burglar",
	CharacterClass.HACKER:      "Hacker",
	CharacterClass.APPRENTICE:  "Apprentice",
}

@export var character_class: CharacterClass = CharacterClass.BRAWLER
@export var character_id: int = 0

var stat_str: int = 0
var stat_int: int = 0
var stat_agi: int = 0

var base_body_kg: float = 65.0   # randomized 60–70 at spawn
var body_weight_kg: float = 0.0  # computed from stats

var carried_kg: float = 0.0      # weight of all held items + locks
var carried_value: float = 0.0   # total $ value of held items

var is_neutralized: bool = false

func _ready() -> void:
	_apply_class(character_class)

func _apply_class(cls: CharacterClass) -> void:
	var s: Dictionary = CLASS_STATS[cls]
	stat_str = s["str"]
	stat_int = s["int"]
	stat_agi = s["agi"]
	base_body_kg = randf_range(60.0, 70.0)
	body_weight_kg = TimeCalculator.body_weight(base_body_kg, stat_str, stat_agi)

func effective_weight() -> float:
	return TimeCalculator.effective_weight(carried_kg, stat_str)

func effective_movespeed() -> float:
	return TimeCalculator.effective_movespeed(stat_agi)

func display_name() -> String:
	return CLASS_NAMES[character_class]

func pick_up_item(item_kg: float, item_value: float) -> void:
	carried_kg += item_kg
	carried_value += item_value

func drop_all_items() -> void:
	carried_kg = 0.0
	carried_value = 0.0
