extends CharacterBody2D

enum State { IDLE, MOVE, ATTACK, HURT, BLOCK, DASH, FINISHER }

@export var max_health: int = 5
var current_health: int = 5

var current_state = State.IDLE 
var was_in_air: bool = false

# --- SISTEM COMBO ---
var combo_count: int = 0
@export var combo_reset_time: float = 0.8 
var combo_timer: SceneTreeTimer = null

# --- VARIABILE VITEZĂ ---
const SPEED = 200.0
const BLOCK_SPEED = 90.0 
const DASH_SPEED = 450.0 
const JUMP_VELOCITY = -250.0 

# --- VARIABILE NOI (DASH & PARRY) ---
var can_air_dash: bool = true 
var dash_direction: int = 1
var block_active_time: float = 0.0 
var trail_timer: float = 0.0

@onready var sprite = $Pivot/Sprite2D
@onready var anim_player = $AnimationPlayer
@onready var hitbox = $Pivot/Hitbox
@onready var pivot = $Pivot
@onready var coyote_timer = $CoyoteTimer
@onready var jump_buffer_timer = $JumpBufferTimer

func _ready() -> void:
	current_health = max_health

func _physics_process(delta: float) -> void:
	var was_on_floor_last_frame = is_on_floor()

	if is_on_floor():
		can_air_dash = true

	if not is_on_floor() and current_state != State.DASH and current_state != State.FINISHER:
		velocity += get_gravity() * delta

	match current_state:
		State.IDLE, State.MOVE:
			handle_movement()
			handle_attack()
			
			if Input.is_action_just_pressed("block"):
				current_state = State.BLOCK
				block_active_time = 0.0 
				
			if Input.is_action_just_pressed("dash") and (is_on_floor() or can_air_dash):
				execute_dash()

		State.BLOCK:
			block_active_time += delta 
			handle_block()
			
			if Input.is_action_just_pressed("dash") and (is_on_floor() or can_air_dash):
				execute_dash()

		State.DASH:
			velocity.y = 0 
			velocity.x = dash_direction * DASH_SPEED
			trail_timer += delta
			if trail_timer > 0.05: # Creează o fantomă la fiecare 0.05 secunde
				spawn_dash_trail()
				trail_timer = 0.0

		State.FINISHER:
			velocity = Vector2.ZERO # Înghețat pe loc în timpul animației de execuție

		State.ATTACK:
			velocity.x = move_toward(velocity.x, 0, 800 * delta)

		State.HURT:
			velocity.x = move_toward(velocity.x, 0, 500 * delta)

	if was_on_floor_last_frame and not is_on_floor() and velocity.y >= 0:
		coyote_timer.start()

	move_and_slide()

# --- GESTIONARE MIȘCARE NORMALĂ ---
func handle_movement() -> void:
	var direction = Input.get_axis("ui_left", "ui_right")
	
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

	if direction != 0:
		velocity.x = direction * SPEED
		current_state = State.MOVE
		pivot.scale.x = sign(direction)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		current_state = State.IDLE

	if Input.is_action_just_pressed("ui_up"):
		jump_buffer_timer.start()

	var can_jump = is_on_floor() or not coyote_timer.is_stopped()
	var has_buffered_jump = not jump_buffer_timer.is_stopped()

	if can_jump and has_buffered_jump:
		execute_jump()

	if Input.is_action_just_released("ui_up") and velocity.y < 0:
		velocity.y *= 0.4

# --- GESTIONARE BLOCK & MERS ÎN GARDĂ ---
func handle_block() -> void:
	if not Input.is_action_pressed("block"):
		current_state = State.IDLE
		return
		
	var direction = Input.get_axis("ui_left", "ui_right")
	
	if direction != 0:
		velocity.x = direction * BLOCK_SPEED
		pivot.scale.x = sign(direction)
		
		if anim_player.current_animation not in ["block_hurt", "finisher"]:
			if anim_player.has_animation("block_walk"):
				anim_player.play("block_walk")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		if anim_player.current_animation not in ["block_hurt", "finisher"]:
			if anim_player.has_animation("block"):
				anim_player.play("block")

# --- EXECUȚIE DASH ---
func execute_dash() -> void:
	current_state = State.DASH
	if not is_on_floor():
		can_air_dash = false 
		
	var direction = Input.get_axis("ui_left", "ui_right")
	if direction != 0:
		dash_direction = sign(direction)
		pivot.scale.x = dash_direction
	else:
		dash_direction = pivot.scale.x 
		
	if anim_player.has_animation("dash"):
		anim_player.play("dash")

# --- GESTIONARE SĂRITURĂ ȘI ATAC ---
func execute_jump() -> void:
	velocity.y = JUMP_VELOCITY
	coyote_timer.stop()
	jump_buffer_timer.stop()

func handle_attack() -> void:
	if Input.is_action_just_pressed("ui_accept"): 
		current_state = State.ATTACK
		combo_count += 1
		
		if combo_count >= 3:
			anim_player.play("alternate_punch")
			velocity.x += pivot.scale.x * 300.0 
			combo_count = 0
		else:
			anim_player.play("punch")
			velocity.x += pivot.scale.x * 150.0
			start_combo_reset_timer()

func start_combo_reset_timer() -> void:
	combo_timer = get_tree().create_timer(combo_reset_time)
	await combo_timer.timeout 
	if current_state != State.ATTACK:
		combo_count = 0

# --- SISTEMUL DE DAUNE (PERFECT PARRY & FINISHER) ---
func take_damage(damage_amount: int, knockback_force: Vector2, attacker: Node2D = null) -> void:
	if current_state == State.BLOCK:
		if block_active_time <= 0.2:
			# -> PERFECT PARRY & FINISHER
			velocity = Vector2.ZERO 
			current_state = State.FINISHER
			
			Engine.time_scale = 0.1
			apply_color_flash(Color(2.0, 2.0, 1.0, 1))
			await get_tree().create_timer(0.05, true, false, true).timeout
			Engine.time_scale = 1.0
			
			if attacker:
				var dir = sign(attacker.global_position.x - global_position.x)
				if dir != 0:
					pivot.scale.x = dir
				
				# Teleportare lângă inamic
				global_position.x = attacker.global_position.x - (dir * 25)
				
				if attacker.has_method("get_executed"):
					attacker.get_executed()
			
			if anim_player.has_animation("finisher"):
				anim_player.play("finisher")
				
		else:
			# -> BLOCK NORMAL
			velocity = knockback_force * 0.5 
			if anim_player.has_animation("block_hurt"):
				anim_player.play("block_hurt")
			apply_color_flash(Color(1.5, 1.5, 2.0, 1)) 
	else:
		# -> LOVITURĂ NORMALĂ
		current_health -= damage_amount
		current_state = State.HURT
		velocity = knockback_force
		combo_count = 0
		if anim_player.has_animation("hurt"):
			anim_player.play("hurt")
		apply_color_flash(Color(5, 5, 5, 1)) 

	if current_health <= 0:
		die()

func apply_color_flash(color: Color) -> void:
	modulate = color 
	await get_tree().create_timer(0.08).timeout
	modulate = Color(1, 1, 1, 1) 

func spawn_dash_trail() -> void:
	# 1. Creăm un Sprite nou (clona) direct din cod
	var trail = Sprite2D.new()
	trail.texture = sprite.texture
	trail.hframes = sprite.hframes
	trail.vframes = sprite.vframes
	trail.frame = sprite.frame
	
	# 2. Îi dăm poziția și orientarea (stânga/dreapta) exactă a jucătorului
	trail.global_position = global_position
	trail.scale.x = pivot.scale.x 
	
	# Îi dăm și o culoare ușor diferită (opțional - aici un albăstrui transparent)
	trail.modulate = Color(0.5, 0.5, 2.0, 0.8) 
	
	# 3. Adăugăm clona în scena principală (ca să nu se miște o dată cu tine)
	get_tree().current_scene.add_child(trail)
	
	# 4. Folosim un Tween (Animație din cod) ca să îi scădem transparența la 0 și apoi să îl ștergem
	var tween = get_tree().create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, 0.3) # Se evaporă în 0.3 secunde
	tween.tween_callback(trail.queue_free) # Se șterge din memorie

func die() -> void:
	get_tree().reload_current_scene()

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name in ["punch", "alternate_punch", "hurt", "dash", "block_hurt", "finisher"]:
		if Input.is_action_pressed("block"):
			current_state = State.BLOCK
		else:
			current_state = State.IDLE

func _on_hitbox_area_entered(area: Area2D) -> void:
	var target = area.owner if area.owner else area.get_parent()
	
	if target and target.has_method("take_damage"):
		var knockback_dir = pivot.scale.x
		
		if current_state == State.DASH:
			var dash_knockback = Vector2(knockback_dir * 150.0, -50.0)
			# Transmitem 'self' ca jucătorul să fie identificat (deși la inamic nu îi pasă cine l-a lovit încă)
			target.take_damage(0, dash_knockback)
		else:
			var damage = 2 if anim_player.current_animation == "alternate_punch" else 1
			var force_x = 250.0 if anim_player.current_animation == "alternate_punch" else 150.0
			var knockback_force = Vector2(knockback_dir * force_x, -50.0)
			
			target.take_damage(damage, knockback_force)

			Engine.time_scale = 0.1
			await get_tree().create_timer(0.03, true, false, true).timeout
			Engine.time_scale = 1.0
