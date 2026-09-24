extends CharacterBody2D

enum State { IDLE, MOVE, ATTACK, HURT }

var current_state = State.IDLE 
var was_in_air: bool = false

# --- SISTEM COMBO ---
var combo_count: int = 0
@export var combo_reset_time: float = 0.8 # Timpul în care poți continua combo-ul
var combo_timer: SceneTreeTimer = null

const SPEED = 200.0
const JUMP_VELOCITY = -250.0 

@export var max_health: int = 5
var current_health: int = 5

@onready var anim_player = $AnimationPlayer
@onready var hitbox = $Pivot/Hitbox
@onready var pivot = $Pivot
@onready var coyote_timer = $CoyoteTimer
@onready var jump_buffer_timer = $JumpBufferTimer

func _ready() -> void:
	current_health = max_health

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
			velocity.x = move_toward(velocity.x, 0, 800 * delta)

		State.HURT:
			# În timpul stării de HURT, jucătorul este împins de knockback și își revine lin
			velocity.x = move_toward(velocity.x, 0, 500 * delta)

	# Detectarea părăsirii solului pentru Coyote Time
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
		if anim_player.current_animation != "jump":
			anim_player.play("jump")
			anim_player.pause()
			
			if velocity.y < 0:
				anim_player.seek(0.0, true)
			else:
				anim_player.seek(0.1, true)

	# --- MIȘCARE ORIZONTALĂ & ORIENTARE ---
	if direction != 0:
		velocity.x = direction * SPEED
		current_state = State.MOVE
		pivot.scale.x = sign(direction)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		current_state = State.IDLE

	# --- SISTEMUL RAFINAT DE SĂRITURĂ ---
	if Input.is_action_just_pressed("ui_up"):
		jump_buffer_timer.start()

	var can_jump = is_on_floor() or not coyote_timer.is_stopped()
	var has_buffered_jump = not jump_buffer_timer.is_stopped()

	if can_jump and has_buffered_jump:
		execute_jump()

	if Input.is_action_just_released("ui_up") and velocity.y < 0:
		velocity.y *= 0.4


func execute_jump() -> void:
	velocity.y = JUMP_VELOCITY
	coyote_timer.stop()
	jump_buffer_timer.stop()


func handle_attack() -> void:
	if Input.is_action_just_pressed("ui_accept"): 
		current_state = State.ATTACK
		
		# Incrementăm contorul de lovituri
		combo_count += 1
		
		if combo_count >= 3:
			# Al 3-lea pumn este cel puternic!
			anim_player.play("alternate_punch")
			velocity.x += pivot.scale.x * 300.0 # Impuls mai mare pentru atacul greu
			combo_count = 0 # Resetăm combo-ul după lovitura finală
		else:
			# Primul și al doilea pumn sunt normale
			anim_player.play("punch")
			velocity.x += pivot.scale.x * 150.0
			
			# Resetăm timer-ul de combo (dacă nu apasă din nou în 0.8s, combo-ul se pierde)
			start_combo_reset_timer()


func start_combo_reset_timer() -> void:
	combo_timer = get_tree().create_timer(combo_reset_time)
	await combo_timer.timeout
	# Dacă player-ul nu a atacat din nou în starea de ATTACK, resetăm la 0
	if current_state != State.ATTACK:
		combo_count = 0


# --- PRIMIRE DAUNE & KNOCKBACK ---
func take_damage(damage_amount: int, knockback_force: Vector2) -> void:
	current_health -= damage_amount
	current_state = State.HURT
	velocity = knockback_force
	combo_count = 0 # Anulăm orice combo dacă suntem loviți
	
	if anim_player.has_animation("hurt"):
		anim_player.play("hurt")
	
	hit_flash()
	
	if current_health <= 0:
		die()

func die() -> void:
	# Aici poți da reload la scenă sau juca o animație de moarte
	get_tree().reload_current_scene()

func hit_flash() -> void:
	modulate = Color(5, 5, 5, 1)
	await get_tree().create_timer(0.08).timeout
	modulate = Color(1, 1, 1, 1)


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "punch" or anim_name == "alternate_punch" or anim_name == "hurt":
		current_state = State.IDLE


# Schimbat în area_entered pentru a detecta corect Hurtbox-ul inamicului
func _on_hitbox_area_entered(area: Area2D) -> void:
	var target = area.owner if area.owner else area.get_parent()
	
	if target and target.has_method("take_damage"):
		var knockback_dir = pivot.scale.x
		
		# Dacă atacul curent este cel greu, dăm daune și knockback dublu!
		var damage = 2 if anim_player.current_animation == "alternate_punch" else 1
		var force_x = 600.0 if anim_player.current_animation == "alternate_punch" else 300.0
		
		var knockback_force = Vector2(knockback_dir * force_x, -150.0)
		
		target.take_damage(damage, knockback_force)

		# Hit-Stop
		Engine.time_scale = 0.1
		await get_tree().create_timer(0.03, true, false, true).timeout
		Engine.time_scale = 1.0
