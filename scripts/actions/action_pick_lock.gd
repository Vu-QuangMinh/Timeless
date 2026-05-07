## ActionPickLock
## Picks the lock on a nearby locked object (≤ 0.5 m).
## Cost: lock_time(level, stat1, stat2) — stats depend on lock type:
##   glass (smash): AGI + STR  |  digital: AGI + INT  |  mechanical: AGI + AGI

class_name ActionPickLock
extends ActionBase

var lock_level: int   = 1        # 1 | 2 | 3
var lock_type: String = "glass"  # "glass" | "digital" | "mechanical"

func _init() -> void:
	action_type = "pick_lock"

func execute_visual(character: PlayerCharacter, tween: Tween) -> void:
	# Jittery precision micro-pulses: working a lock under tension.
	tween.tween_callback(func(): character.scale = Vector2.ONE)
	tween.tween_property(character, "scale", Vector2(1.06, 1.06), get_animation_duration() * 0.2)
	tween.tween_property(character, "scale", Vector2(0.97, 0.97), get_animation_duration() * 0.2)
	tween.tween_property(character, "scale", Vector2(1.06, 1.06), get_animation_duration() * 0.2)
	tween.tween_property(character, "scale", Vector2(0.97, 0.97), get_animation_duration() * 0.2)
	tween.tween_property(character, "scale", Vector2.ONE,         get_animation_duration() * 0.2)

func undo_visual(character: PlayerCharacter) -> void:
	character.scale = Vector2.ONE
