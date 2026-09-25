extends Camera2D

var shake_strength: float = 0.0
var shake_fade: float = 5.0 # Cât de repede se oprește tremuratul

func apply_shake(random_strength: float) -> void:
	shake_strength = random_strength

func _process(delta: float) -> void:
	if shake_strength > 0:
		shake_strength = lerpf(shake_strength, 0, shake_fade * delta)
		offset = Vector2(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength))
	else:
		offset = Vector2.ZERO
