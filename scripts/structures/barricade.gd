class_name Barricade
extends Structure

func blocks_segment(from: Vector3, to: Vector3, padding := 1.0) -> Dictionary:
	if destroyed or not blocks_movement:
		return {}
	var half_x := footprint_size.x * 0.5 + padding
	var half_z := footprint_size.y * 0.5 + padding
	var start := from - global_position
	var end := to - global_position
	var direction := end - start
	var best_t := INF
	for axis in [0, 1]:
		var start_value: float = start.x if axis == 0 else start.z
		var direction_value: float = direction.x if axis == 0 else direction.z
		var limit: float = half_x if axis == 0 else half_z
		if absf(direction_value) < 0.0001:
			continue
		for side in [-limit, limit]:
			var t: float = (side - start_value) / direction_value
			if t < 0.0 or t > 1.0:
				continue
			var other: float = (start.z + direction.z * t) if axis == 0 else (start.x + direction.x * t)
			var other_limit: float = half_z if axis == 0 else half_x
			if absf(other) <= other_limit and t < best_t:
				best_t = t
	if best_t == INF:
		return {}
	var point := from.lerp(to, maxf(0.0, best_t - 0.03))
	return {"point": Vector3(point.x, 0.0, point.z), "blocker": self}
