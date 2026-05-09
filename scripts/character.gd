class_name Character
extends RefCounted

enum CharacterClass { BRAWLER, CAT_BURGLAR, HACKER }

# Indexed by CharacterClass int value
const CLASS_STATS: Array = [
	{"str": 3, "int": 1, "agi": 1, "name": "Brawler"},       # BRAWLER
	{"str": 1, "int": 1, "agi": 3, "name": "Cat Burglar"},   # CAT_BURGLAR
	{"str": 1, "int": 3, "agi": 1, "name": "Hacker"},        # HACKER
]

const BASE_WEIGHT_KG := 70.0

var char_class: CharacterClass = CharacterClass.BRAWLER
var char_str: int = 1
var char_int: int = 1
var char_agi: int = 1
var carried_kg: float = 0.0
var is_neutralized: bool = false


func _init(c: CharacterClass) -> void:
	char_class = c
	var s: Dictionary = CLASS_STATS[int(c)]
	char_str = s["str"]
	char_int = s["int"]
	char_agi = s["agi"]


func effective_weight() -> float:
	return BASE_WEIGHT_KG + carried_kg


func display_name() -> String:
	return CLASS_STATS[int(char_class)]["name"]


static func get_stats(c: CharacterClass) -> Dictionary:
	return CLASS_STATS[int(c)]
