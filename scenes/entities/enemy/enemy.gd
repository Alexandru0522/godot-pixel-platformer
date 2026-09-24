extends CharacterBody2D

enum State { IDLE, PATROL, CHASE, ATTACK, STUNNED }

@export var max_health: int = 3
@export var speed: float = 60.0
@export var chase_speed: float = 110.0
@export var attack_cooldown: float = 1.5
@export var damage_amount: int = 1 # Cantitatea de daune pe care o dă inamicul

var current_health: int
var current_state: State = State.IDLE
var patrol_dir: int = 1
var player_ref: CharacterBody2D = null
var can_attack: bool = true
var is_changing_state: bool = false # Previne resetarea timer-ului de patrulă

const FRICTION = 800.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var pivot: Node2D = $Pivot
@onready var floor_checker: RayCast2D = $FloorChecker
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var hitbox_shape: CollisionShape2D = $Pivot/Hitbox/CollisionShape2D

func _ready() -> void:
	current_health = max_health
	if hitbox_shape:
		hitbox_shape.disabled = true
	
	# Pornim ciclul de patrulare aleatorie
	choose_random_patrol()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	match current_state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
			if anim_player.has_animation("idle"):
				anim_player.play("idle")

		State.PATROL:
			velocity.x = patrol_dir * speed
			
			if anim_player.has_animation("walk"):
				anim_player.play("walk")
			
			# Dacă atinge un perete sau o prăpastie, schimbă direcția pe loc
			if is_on_wall() or (is_on_floor() and floor_checker and not floor_checker.is_colliding()):
				patrol_dir *= -1
				pivot.scale.x = patrol_dir

		State.CHASE:
			if player_ref:
				var diff_x = player_ref.global_position.x - global_position.x
				var dist_x = abs(diff_x)
				var stop_distance = 25.0

				if dist_x > stop_distance:
					var dir = sign(diff_x)
					velocity.x = dir * chase_speed
					
					if dir != 0:
						patrol_dir = dir
						pivot.scale.x = dir
					
					if anim_player.has_animation("walk"):
						anim_player.play("walk")
				else:
					velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
					
					if sign(diff_x) != 0:
						pivot.scale.x = sign(diff_x)

					if can_attack:
						start_attack()
					else:
						if anim_player.has_animation("idle"):
							anim_player.play("idle")

		State.ATTACK:
			velocity.x = move_toward(velocity.x, 0, FRICTION * delta)

		State.STUNNED:
			velocity.x = move_toward(velocity.x, 0, FRICTION * delta)

	move_and_slide()

# --- LOGICĂ PATRULARE ALEATORIE ---
func choose_random_patrol() -> void:
	if current_state == State.CHASE or current_state == State.ATTACK or current_state == State.STUNNED:
		return
		
	is_changing_state = true
	
	# Alege aleatoriu dacă stă pe loc (IDLE) sau merge (PATROL)
	var random_choice = randi() % 2 # Returnează 0 sau 1
	
	if random_choice == 0:
		current_state = State.IDLE
	else:
		current_state = State.PATROL
		# Alege o direcție aleatorie: -1 (stânga) sau 1 (dreapta)
		patrol_dir = 1 if randf() > 0.5 else -1
		pivot.scale.x = patrol_dir

	# Așteaptă un timp aleatoriu între 1.5 și 3.5 secunde până la următoarea decizie
	var wait_time = randf_range(1.5, 3.5)
	await get_tree().create_timer(wait_time).timeout
	
	is_changing_state = false
	choose_random_patrol()

# --- ATAC INAMIC ---
func start_attack() -> void:
	current_state = State.ATTACK
	can_attack = false
	
	if anim_player.has_animation("attack"):
		anim_player.play("attack")
	elif anim_player.has_animation("punch"):
		anim_player.play("punch")

# --- PRIMIRE DAUNE & KNOCKBACK ---
func take_damage(amount: int, knockback_force: Vector2) -> void:
	current_health -= amount
	current_state = State.STUNNED
	
	if hitbox_shape:
		hitbox_shape.set_deferred("disabled", true)
	
	velocity = knockback_force
	
	if anim_player.has_animation("hurt"):
		anim_player.play("hurt")
		
	hit_flash()

	if current_health <= 0:
		die()

func hit_flash() -> void:
	sprite.modulate = Color(5, 5, 5, 1)
	await get_tree().create_timer(0.08).timeout
	sprite.modulate = Color(1, 1, 1, 1)

func die() -> void:
	queue_free()

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "attack" or anim_name == "punch":
		current_state = State.CHASE if player_ref else State.IDLE
		start_attack_cooldown()
		if not player_ref:
			choose_random_patrol()
	elif anim_name == "hurt":
		if current_health > 0:
			current_state = State.CHASE if player_ref else State.IDLE
			if not player_ref:
				choose_random_patrol()

func start_attack_cooldown() -> void:
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

# --- DETECTARE PLAYER ---
func _on_player_detector_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player") or body.name == "Player":
		player_ref = body
		if current_state != State.ATTACK and current_state != State.STUNNED:
			current_state = State.CHASE

func _on_player_detector_body_exited(body: Node2D) -> void:
	if body == player_ref:
		player_ref = null
		if current_state != State.ATTACK and current_state != State.STUNNED:
			choose_random_patrol()

# --- COLIZIUNE HITBOX (Trimitere Daune către Player) ---
func _on_hitbox_area_entered(area: Area2D) -> void:
	print("Hitbox-ul inamicului a atins aria: ", area.name)
	
	var target = area.owner if area.owner else area.get_parent()
	if target and target.has_method("take_damage") and target != self:
		var knockback_dir = pivot.scale.x
		var knockback_force = Vector2(knockback_dir * 250.0, -120.0)
		
		# Aici aplică daunele salvate în 'damage_amount'
		target.take_damage(damage_amount, knockback_force)
