extends Node

const PPM := 32.0
const COS30 := 0.8660254
const SIN30 := 0.5


func project(world: Vector2) -> Vector2:
	return Vector2((world.x + world.y) * COS30, (world.x - world.y) * SIN30) * PPM


func unproject(screen: Vector2) -> Vector2:
	var u := screen.x / (COS30 * PPM)
	var v := screen.y / (SIN30 * PPM)
	return Vector2((u + v) * 0.5, (u - v) * 0.5)
