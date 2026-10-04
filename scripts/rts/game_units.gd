extends RefCounted
## All gameplay ranges and speeds are expressed in small RTS units, not metres.

const PER_METRE: float = 20.0
const FLOOR_Y: float = 0.5
const ARENA_LIMIT: float = 47.0


static func to_metres(units: float) -> float:
	return units / PER_METRE


static func to_units(metres: float) -> float:
	return metres * PER_METRE


static func clamp_to_arena(point: Vector3) -> Vector3:
	return Vector3(clampf(point.x, -ARENA_LIMIT, ARENA_LIMIT), FLOOR_Y, clampf(point.z, -ARENA_LIMIT, ARENA_LIMIT))
