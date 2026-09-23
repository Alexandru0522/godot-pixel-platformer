extends CharacterBody2D

func _physics_process(delta: float) -> void:
	# 1. Adăugăm gravitația exact cum a făcut Godot, ca inamicul să cadă pe podea
	if not is_on_floor():
		velocity += get_gravity() * delta

	# 2. Frecarea: Încetinim inamicul treptat. 
	# Dacă nu punem asta, când îi dăm un pumn, va aluneca pe ecran la infinit ca pe gheață.
	velocity.x = move_toward(velocity.x, 0, 15)

	# 3. Aplicăm fizica
	move_and_slide()
