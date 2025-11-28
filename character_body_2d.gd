extends CharacterBody2D

const Gravity := 600.0

@export var speed : float
@export var damage : int
@export var health : int
@export var height_intensity : float

@onready var animation_player := $AnimationPlayer
@onready var damager_emitter := $DamagerEmitter
@onready var character_sprite :=  $characterSprites

enum State { WALK, IDLE, ATTACK , JUMP , LAND , TAKE_OFF }

var state = State.IDLE
var height := 0.0
var height_speed := 0.0

func _ready() -> void:
	damager_emitter.area_entered.connect(on_damage_receiver.bind())
	print("READY — state:", state)


func _process(delta: float) -> void:
	# DEBUG
	print("STATE:", state, " height:", height, " height_speed:", height_speed, " velocity:", velocity)

	handle_input()
	handle_movement()
	handle_animation()
	handle_air_time(delta)
	slip_sprite()
	character_sprite.position = Vector2.UP * height  
	move_and_slide()


func handle_input():
	var direction := Input.get_vector("ui_left", "ui_right","ui_up", "ui_down")

	if can_move():
		velocity = direction * speed
	else:
		velocity = Vector2.ZERO

	if can_attack() and Input.is_action_just_pressed("attack"):
		print(">>> ATTACK triggered")
		state = State.ATTACK
		
	if can_junp() and Input.is_action_just_pressed("jump"):
		print(">>> JUMP BUTTON PRESSED — switching to TAKE_OFF")
		state = State.TAKE_OFF

func handle_movement():
	# If we are in a non‑movement state, do not touch the state.
	if state == State.ATTACK or state == State.TAKE_OFF or state == State.JUMP or state == State.LAND:
		return

	# Only here are we allowed to change between IDLE and WALK.
	if velocity.length() == 0:
		state = State.IDLE
	else:
		state = State.WALK


func handle_animation() -> void:
	match state:
		State.WALK:      animation_player.play("walk")
		State.IDLE:      animation_player.play("idle")
		State.ATTACK:    animation_player.play("punch")
		State.JUMP:      animation_player.play("jump")
		State.TAKE_OFF:  animation_player.play("take_off")
		State.LAND:      animation_player.play("land")


func can_attack() -> bool:
	return state == State.IDLE or state == State.WALK 

func can_move() -> bool:
	return state != State.ATTACK


func on_action_complete() -> void:
	print(">>> ACTION ANIMATION COMPLETE")
	state = State.IDLE
	

func on_damage_receiver(damager_receiver:DamageReceiver):
	damager_receiver.damage_received.emit(damage)
	print("Damage given:", damage)


func slip_sprite():
	if velocity.x > 0:
		character_sprite.flip_h = false
		damager_emitter.scale.x = 1
	elif velocity.x < 0:
		character_sprite.flip_h = true
		damager_emitter.scale.x = -1


func can_junp():
	return state == State.IDLE or state == State.WALK


func on_takeoff_complete() -> void:
	print(">>> TAKE_OFF animation complete — switching to JUMP")
	state = State.JUMP
	height_speed = height_intensity


func on_land_complete() -> void:
	print(">>> LAND animation complete — switching to IDLE")
	state = State.IDLE


func handle_air_time(delta : float):
	if state == State.JUMP:
		print("JUMPING — height:", height, " speed:", height_speed)

		height += height_speed * delta
		if height < 0:
			print(">>> HIT GROUND — switching to LAND")
			height = 0
			state = State.LAND
		else:
			height_speed -= Gravity * delta
