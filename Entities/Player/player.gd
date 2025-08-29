extends CharacterBody2D

@export var SPEED = 400
@export var ACCELERATE = 50
@export var MAX_GRAVITY = 500
@export var WALL_GRAVITY = 50
@export var JUMP_SPEED = 400
@export var MULITPLE_JUMP_SPEED = 300
@export var MAX_JUMP = 2

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var screen_size
var jumped = 0

func _ready():
	screen_size = get_viewport_rect().size

func _process(_delta):
#	reserved for animation and general function for character
	pass

func _physics_process(delta: float) -> void:
	handle_walk()
	if velocity.y <= MAX_GRAVITY:
		velocity.y += gravity * delta
	handle_jump()
	handle_wall_jump()
	move_and_slide()
	if is_on_floor():
		jumped = 0

func handle_walk():
	var input_direction = Input.get_axis("move_left", "move_right")
	velocity.x = SPEED * input_direction

func get_jump_speed():
	return JUMP_SPEED if jumped == 0 else MULITPLE_JUMP_SPEED

func handle_jump():
	var jump_key_pressed = Input.is_action_just_pressed("jump")
	var is_rising = velocity.y < 0
	var is_jump_canceled = Input.is_action_just_released("jump") and is_rising 
	var jump_available = jumped < MAX_JUMP

	if jump_key_pressed and jump_available:
		velocity.y -= (get_jump_speed() + velocity.y)
		jumped += 1
	if is_jump_canceled:
		velocity.y = 0
		
func get_collide_physics_layers():
	var layers = []
	for collision_id in get_slide_collision_count():
		var collision = get_slide_collision(collision_id)
		var rid = collision.get_collider_rid()
		layers.append(PhysicsServer2D.body_get_collision_layer(rid))
	return layers

func handle_wall_jump():
	if is_on_wall() and Input.get_axis("move_left", "move_right"):
		var layers = get_collide_physics_layers()
		if GameEnums.PHYSICS_LAYERS.CLIMB_WALL in layers:
			velocity.y = WALL_GRAVITY
			jumped = 0
