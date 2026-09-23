extends CharacterBody2D

# 1. Definim Stările posibile ale jucătorului.
# Un "enum" este pur și simplu o listă de etichete pe care le inventăm noi.
enum State { IDLE, MOVE, ATTACK }

# 2. Definim starea curentă. Când pornește jocul, jucătorul stă pe loc (IDLE).
var current_state = State.IDLE 
var was_in_air: bool = false

const SPEED = 200.0
const JUMP_VELOCITY = -200.0

# 3. "@onready" îi spune jocului: "Înainte să pornești codul, asigură-te că ai găsit nodul AnimationPlayer și memorează-l în variabila anim_player ca să îl folosim mai târziu."
@onready var anim_player = $AnimationPlayer
@onready var hitbox = $Pivot/Hitbox
@onready var pivot = $Pivot

# 4. _physics_process este inima jocului. Rulează de 60 de ori pe secundă non-stop.
func _physics_process(delta):
	# 1. Aplicăm gravitația dacă jucătorul nu este pe podea
	if not is_on_floor():
		velocity += get_gravity() * delta

	# "match" este ca un macaz de cale ferată. Verifică în ce stare suntem.
	match current_state:
		State.IDLE, State.MOVE:
			# Dacă stăm sau mergem, avem voie să ne mișcăm și avem voie să dăm pumn
			handle_movement()
			handle_attack()
			
		State.ATTACK:
			# Dacă suntem în starea ATTACK, nu chemăm funcțiile de mișcare!
			# Tot ce facem este să frânăm caracterul ca să nu alunece pe podea ca pe gheață.
			# move_toward duce viteza (velocity.x) către 0 treptat.
			velocity.x = move_toward(velocity.x, 0, SPEED)
			
	# La finalul celor 60 de cadre pe secundă, spunem motorului Godot să aplice fizica
	move_and_slide()


# --- FUNCȚIILE SECUNDARE ---

func handle_movement():
	# Input.get_axis ne dă valoarea 1 (dreapta), -1 (stânga) sau 0 (nu apăsăm nimic)
	var direction = Input.get_axis("ui_left", "ui_right")
	
	if is_on_floor():
		if was_in_air:
			# Tocmai a atins solul -> lansăm animația scurtă de aterizare (land)
			anim_player.play("land")
			was_in_air = false
		else:
			# Dacă încă rulează aterizarea (cadrele de 0.1s cu genunchii îndoiți), o lăsăm să se termine
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
		
		# Controlăm cadrul din aer în funcție de urcare/coborâre:
		if velocity.y < 0:
			anim_player.seek(0.1, true) # Sare la timpul pentru Frame 1 (Urcare)
		else:
			anim_player.seek(0.2, true) # Sare la timpul pentru Frame 2 (Coborâre)
	
	if direction != 0:
		velocity.x = direction * SPEED
		current_state = State.MOVE # Schimbăm starea internă în MOVE
		if direction > 0:
			pivot.scale.x = 1 # Ne uităm la dreapta
		elif direction < 0:
			pivot.scale.x = -1 # Ne uităm la stânga (oglindă)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		current_state = State.IDLE # Schimbăm starea în IDLE
		
	if Input.is_action_just_pressed("ui_up") and is_on_floor():
		velocity.y = JUMP_VELOCITY # Forța cu care sare în sus


func handle_attack():
	# ui_accept este presetat în Godot pentru tasta Space sau Enter
	if Input.is_action_just_pressed("ui_accept"): 
		current_state = State.ATTACK # ACUM blocăm mișcarea! Trecem în modul atac.
		anim_player.play("punch") # Cerem nodului de animație să ruleze ce am făcut la Pasul 1


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "punch": # Verificăm dacă animația care s-a terminat este fix pumnul
		current_state = State.IDLE # Deblocăm jucătorul! Poate să meargă din nou.


func _on_hitbox_body_entered(body: Node2D) -> void:
	if body.name == "Enemy":
		# 1. KNOCKBACK: Modificăm viteza inamicului. Îl aruncăm puternic spre dreapta!
		body.velocity.x = 200
		# 2. HIT PAUSE: Modificăm curgerea timpului în tot jocul. 
		# 1.0 este viteza normală. 0.1 înseamnă "slow motion" extrem.
		Engine.time_scale = 0.2
		# 3. Așteptăm o fracțiune de secundă (0.05 secunde) ca jucătorul să simtă încetinirea.
		await get_tree().create_timer(0.15 * Engine.time_scale).timeout
		# 4. Readucem timpul la normal ca jocul să continue.
		Engine.time_scale = 1.0
