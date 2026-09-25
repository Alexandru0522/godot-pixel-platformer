extends CharacterBody2D

enum State { IDLE, PATROL, CHASE, ATTACK, STUNNED, DEAD }

@export var max_health: int = 3
@export var speed: float = 60.0
@export var chase_speed: float = 110.0
@export var attack_cooldown: float = 1.5
@export var damage_amount: int = 1

var current_health: int
var current_state: State = State.IDLE
var patrol_dir: int = -1
var player_ref: CharacterBody2D = null
var can_attack: bool = true
var is_changing_state: bool = false

const FRICTION = 800.0

@onready var sprite: Sprite2D = $Pivot/Sprite2D
@onready var pivot: Node2D = $Pivot
@onready var floor_checker: RayCast2D = $Pivot/FloorChecker
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var hitbox_shape: CollisionShape2D = $Pivot/Hitbox/CollisionShape2D

func _ready() -> void:
	current_health = max_health
	if hitbox_shape:
		hitbox_shape.disabled = true
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
			
			if is_on_wall() or (is_on_floor() and floor_checker and not floor_checker.is_colliding()):
				patrol_dir *= -1
				pivot.scale.x = patrol_dir

		State.CHASE:
			if player_ref:
				var diff_x = player_ref.global_position.x - global_position.x
				var dist_x = abs(diff_x)
				var stop_distance = 30.0

				if dist_x > stop_distance:
					var dir = sign(diff_x)
					velocity.x = dir * chase_speed
					if dir != 0:
						patrol_dir = dir
						pivot.scale.x = dir
					
					if current_state != State.ATTACK and anim_player.has_animation("walk"):
						anim_player.play("walk")
				else:
					velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
					if sign(diff_x) != 0:
						pivot.scale.x = sign(diff_x)

					if can_attack:
						start_attack()
					else:
						if current_state != State.ATTACK and anim_player.has_animation("idle"):
							anim_player.play("idle")

		State.ATTACK, State.STUNNED, State.DEAD:
			velocity.x = move_toward(velocity.x, 0, FRICTION * delta)

	move_and_slide()

func choose_random_patrol() -> void:
	if current_state == State.CHASE or current_state == State.ATTACK or current_state == State.STUNNED or current_state == State.DEAD:
		return
		
	is_changing_state = true
	var wait_time: float = 0.0
	
	if randf() < 0.10:
		current_state = State.IDLE
		wait_time = randf_range(0.5, 1.0)
	else:
		current_state = State.PATROL
		patrol_dir = 1 if randf() > 0.5 else -1
		pivot.scale.x = patrol_dir
		wait_time = randf_range(2.0, 4.0)

	await get_tree().create_timer(wait_time).timeout
	
	is_changing_state = false
	choose_random_patrol()

func start_attack() -> void:
	current_state = State.ATTACK
	can_attack = false
	if anim_player.has_animation("attack"):
		anim_player.play("attack")
	elif anim_player.has_animation("punch"):
		anim_player.play("punch")

func take_damage(amount: int, knockback_force: Vector2) -> void:
	if current_state == State.DEAD:
		return # Dacă e deja pe moarte, ignorăm alte lovituri

	current_health -= amount
	
	if hitbox_shape:
		hitbox_shape.set_deferred("disabled", true)
		
	hit_flash()

	if current_health <= 0:
		# --- LOVITURA FATALĂ ---
		current_state = State.DEAD
		
		# Îi dăm un knockback uriaș (x2 pe orizontală, și îl ridicăm un pic pe verticală)
		velocity = Vector2(knockback_force.x * 1.2, -100.0)
		
		if anim_player.has_animation("death"):
			anim_player.play("death")
	else:
		# --- LOVITURĂ NORMALĂ ---
		current_state = State.STUNNED
		velocity = knockback_force
		if anim_player.has_animation("hurt"):
			anim_player.play("hurt")

# --- EXECUTAT DE CĂTRE JUCĂTOR (PERFECT PARRY) ---
func get_executed() -> void:
	current_state = State.STUNNED
	
	# Dezactivăm absolut toate coliziunile ca să poți trece prin el după ce moare
	if hitbox_shape:
		hitbox_shape.set_deferred("disabled", true)
	
	# Oprim procesarea fizicii pentru inamic
	velocity = Vector2.ZERO
	set_physics_process(false) 
	
	# 1. Joacă animația de șoc în timp ce jucătorul tău îl ține în aer (Cadrele 1 și 2 din Finisher)
	if anim_player.has_animation("hurt"):
		anim_player.play("hurt")
		
	# 2. Așteptăm fix momentul impactului (Ajustează 0.4 în funcție de când dă jucătorul cu pumnul de pământ)
	await get_tree().create_timer(0.4).timeout 
	
	if anim_player.has_animation("dead_ground"):
		anim_player.play("dead_ground")
		
	sprite.position.y += 3

	# Dezactivăm coliziunea principală a inamicului ca să nu te blochezi în cadavru
	$CollisionShape2D.set_deferred("disabled", true)
	# 3. IMPACTUL CU SOLUL!
	# Declanșăm explozia de particule!
	if has_node("SlamParticles"):
		$SlamParticles.emitting = true
	
	var camera = get_tree().get_first_node_in_group("PlayerCamera")
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(15.0)
	# Schimbăm animația în cea de strivit de pământ
	# Îl dăm puțin mai jos (opțional, ajustează valoarea dacă pare că plutește)

func hit_flash() -> void:
	sprite.modulate = Color(5, 5, 5, 1)
	await get_tree().create_timer(0.08).timeout
	sprite.modulate = Color(1, 1, 1, 1)

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "death":
		# Când s-a terminat de bălăngănit, cade pe pământ
		if anim_player.has_animation("dead_ground"):
			anim_player.play("dead_ground")
		
		sprite.position.y += 3 # Îl coborâm ca la finisher
		$CollisionShape2D.set_deferred("disabled", true) # Ca să poți merge prin el
		set_physics_process(false) # Îngheață cadavrul pe loc
		return # Ieșim din funcție
	if anim_name == "attack" or anim_name == "punch":
		current_state = State.CHASE if player_ref else State.IDLE
		start_attack_cooldown()
		if not player_ref:
			choose_random_patrol()
	elif anim_name == "hurt":
		can_attack = true
		if current_health > 0:
			current_state = State.CHASE if player_ref else State.IDLE
			if not player_ref:
				choose_random_patrol()

func start_attack_cooldown() -> void:
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func _on_player_detector_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player") or body.name == "Player":
		player_ref = body
		if current_state != State.ATTACK and current_state != State.STUNNED and current_state != State.DEAD:
			current_state = State.CHASE

func _on_player_detector_body_exited(body: Node2D) -> void:
	if body == player_ref:
		player_ref = null
		if current_state != State.ATTACK and current_state != State.STUNNED and current_state != State.DEAD:
			choose_random_patrol()

func _on_hitbox_area_entered(area: Area2D) -> void:
	var target = area.owner if area.owner else area.get_parent()
	if target and target.has_method("take_damage") and target != self:
		var knockback_dir = pivot.scale.x
		var knockback_force = Vector2(knockback_dir * 250.0, -50.0)
		
		# Am adăugat 'self' ca argument pentru a permite jucătorului să identifice atacatorul
		target.take_damage(damage_amount, knockback_force, self)
