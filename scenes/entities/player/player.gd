extends CharacterBody2D

enum State { IDLE, MOVE, ATTACK }

var current_state = State.IDLE 
var was_in_air: bool = false

const SPEED = 200.0
const JUMP_VELOCITY = -250.0 

@onready var anim_player = $AnimationPlayer
@onready var hitbox = $Pivot/Hitbox
@onready var pivot = $Pivot
@onready var coyote_timer = $CoyoteTimer
@onready var jump_buffer_timer = $JumpBufferTimer

func _physics_process(delta: float) -> void:
	# 1. Gravitație
	if not is_on_floor():
		velocity += get_gravity() * delta

	# 2. Reținem dacă am părăsit solul în acest cadru pentru Coyote Time
	var was_on_floor_last_frame = is_on_floor()

	match current_state:
		State.IDLE, State.MOVE:
			handle_movement()
			handle_attack()
			
		State.ATTACK:
			velocity.x = move_toward(velocity.x, 0, SPEED)

	# Lansasem detectarea părăsirii solului pentru Coyote Time
	if was_on_floor_last_frame and not is_on_floor() and velocity.y >= 0:
		coyote_timer.start()

	move_and_slide()


func handle_movement() -> void:
	var direction = Input.get_axis("ui_left", "ui_right")
	
	# --- GESTIONARE ANIMAȚII ȘI ATERIZARE ---
	if is_on_floor():
		if was_in_air:
			anim_player.play("land")
			was_in_air = false
		else:
			if anim_player.current_animation == "land" and anim_player.is_playing():
				pass
			else:
				if direction == 0:
					anim_player.play("idle")
				else:
					anim_player.play("walk")
	else:
		was_in_air = true
		anim_player.play("jump")
		
		if velocity.y < 0:
			anim_player.seek(0.1, true)
		else:
			anim_player.seek(0.2, true)

	# --- MIȘCARE ORIZONTALĂ & ORIENTARE ---
	if direction != 0:
		velocity.x = direction * SPEED
		current_state = State.MOVE
		if direction > 0:
			pivot.scale.x = 1
		elif direction < 0:
			pivot.scale.x = -1
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		current_state = State.IDLE

	# --- SISTEMUL RAFINAT DE SĂRITURĂ ---
	
	# 1. Jump Buffer: Dacă apăsăm tasta, pornim buffer-ul
	if Input.is_action_just_pressed("ui_up"):
		jump_buffer_timer.start()

	# 2. Execuție Săritură: Putea să sară dacă e pe sol SAU dacă coyote_timer încă rulează
	var can_jump = is_on_floor() or not coyote_timer.is_stopped()
	var has_buffered_jump = not jump_buffer_timer.is_stopped()

	if can_jump and has_buffered_jump:
		execute_jump()

	# 3. Variable Jump Height: Dacă dăm drumul tastei în timp ce urcăm, reducem viteza verticală
	if Input.is_action_just_released("ui_up") and velocity.y < 0:
		velocity.y *= 0.4 # Înjumătățim urcarea instant pentru săritură scurtă


func execute_jump() -> void:
	velocity.y = JUMP_VELOCITY
	coyote_timer.stop() # Consumăm coyote time
	jump_buffer_timer.stop() # Consumăm buffer-ul


func handle_attack() -> void:
	if Input.is_action_just_pressed("ui_accept"): 
		current_state = State.ATTACK
		anim_player.play("punch")


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "punch":
		current_state = State.IDLE


func _on_hitbox_body_entered(body: Node2D) -> void:
	if body.name == "Enemy":
		body.velocity.x = 200
		Engine.time_scale = 0.2
		await get_tree().create_timer(0.15 * Engine.time_scale).timeout
		Engine.time_scale = 1.0
