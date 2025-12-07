extends CharacterBody2D

# WALK CONFIG
@export var SPEED = 500
@export var ACCELERATE = 30
# CRAWL CONFIG
@export var CRAWL_SPEED = 100
# JUMP CONFIG
@export var MAX_GRAVITY = 800
@export var JUMP_SPEED = 600
@export var MULITPLE_JUMP_SPEED = 500
@export var MAX_JUMP = 2
@export var JUMP_BUFFER_TIME = 0.1
@export var JUMP_FORGIVENESS_TIME = 0.15
@export var JUMP_CANCELING_VELOCITY = 0.5
@export var JUMP_APEX = 300
@export var JumpDust: PackedScene
@export var DashDust: PackedScene 
@export var WallJumpDust: PackedScene
# DASH CONFIG
@export var DASH_DURATION = 0.2
@export var DASH_COOLDOWN_TIME = 0.6
@export var DASH_SPEED = 1000
#WALL SLIDE & JUMP CONFIG
@export var WALL_MAX_GRAVITY = 180
@export var WALL_GRAVITY_FACTOR = 0.3
@export var INITIAL_WALL_GRAVITY = 30
@export var WALL_JUMP_DURATION = 0
@export var WALL_JUMP_SPEED_HORIZONTAL = 350
@export var WALL_JUMP_SPEED_VERTICAL = 700
# BAD
@export var HURT_DURATION = 0.5
@export var KNOCKBACK_SPEED = 300
@export var INVINCIBLE_DURATION = 2

@onready var screen_size
@onready var standing_collision = $StandingCollision
@onready var crawling_collision = $CrawlingCollision
@onready var ceiling_detection = $CeilingDetection
# crawl state
var crawling = false
var forced_crawl = false
# walk stated
var latest_direction = 1
# wall slide state
var wall_sliding = false
# wall jump state
var wall_jumping = false
# jump state
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var jumped = 0
var jump_buffer_timer = 0
var jump_forgiveness_timer = 0
# dash state
var dashing = false
var dash_cooldown_time = 0
var dash_direction = 1
# hurt state
var hurting = false
var invincible = false

func _ready():
	screen_size = get_viewport_rect().size

func _process(_delta):
#	reserved for animation and general function for character
	var input_direction = Input.get_axis("move_left", "move_right")
	if input_direction != 0 and not dashing:
		$AnimatedSprite2D.flip_h = input_direction < 0
	if hurting:
		$AnimatedSprite2D.animation = "knockback"
	elif wall_sliding:
		$AnimatedSprite2D.animation = "wall_slide"
	elif dashing:
		if crawling:
			$AnimatedSprite2D.animation = "slide"
		else:
			$AnimatedSprite2D.animation = "dash"
	elif is_on_floor():
		if input_direction != 0:
			if crawling:
				$AnimatedSprite2D.animation = "crawl"
			else:
				$AnimatedSprite2D.animation = "run"
		elif velocity.x != 0:
			if crawling:
				$AnimatedSprite2D.animation = "crawl"
			else:
				$AnimatedSprite2D.animation = "stop_run"
		elif crawling:
			$AnimatedSprite2D.animation = "crouch"
		else:
			$AnimatedSprite2D.animation = "idle"
	else:
		if velocity.y < 0:
			$AnimatedSprite2D.animation = "jump_rise"
		elif velocity.y > 0:
			if velocity.y < JUMP_APEX:
				$AnimatedSprite2D.animation = "jump_mid"
			else:
				$AnimatedSprite2D.animation = "jump_fall"
	$AnimatedSprite2D.play()
	if invincible:
		$AnimatedSprite2D.set_visible(randi_range(0,1))
	else:
		$AnimatedSprite2D.set_visible(true)


func _physics_process(delta: float) -> void:
	handle_gravity(delta)
	handle_walk(delta)
	handle_dash(delta)
	handle_jump(delta)
	handle_wall_slide()
	handle_wall_jump()
	handle_duck()
	move_and_slide()
	render_collision()
	if is_on_floor():
		jumped = 0
	handle_collision()

func handle_walk(delta):
	if disable_action():
		return
	var input_direction = Input.get_axis("move_left", "move_right")
	if input_direction:
		latest_direction = input_direction
		var speed = SPEED if not crawling else CRAWL_SPEED
		if abs(velocity.x) >= speed:
			velocity.x = speed * input_direction
		else:
			velocity.x += input_direction * ACCELERATE
	else:
#		handle friction
		if velocity.x > 0:
			velocity.x -= ACCELERATE
			if velocity.x < 0:
				velocity.x = 0
		elif velocity.x < 0:
			velocity.x += ACCELERATE
			if velocity.x > 0:
				velocity.x = 0

func handle_gravity(delta):
	if disable_action():
		return
	var max_gravity = WALL_MAX_GRAVITY if wall_sliding else MAX_GRAVITY
	var target_gravity = gravity * WALL_GRAVITY_FACTOR if wall_sliding else gravity
	if velocity.y < max_gravity:
		velocity.y = min(velocity.y + (target_gravity * delta), max_gravity )
	else:
		velocity.y = max_gravity


func handle_jump(delta):
	if disable_action() or wall_sliding or forced_crawl:
		return
	var jump_key_pressed = Input.is_action_just_pressed("jump")
	var is_rising = velocity.y < 0
	var is_jump_canceled = Input.is_action_just_released("jump") and is_rising 

	if is_on_floor():
		jump_forgiveness_timer = JUMP_FORGIVENESS_TIME
	if jump_forgiveness_timer > 0:
		jump_forgiveness_timer = max(jump_forgiveness_timer - delta, 0.0)

	if jump_key_pressed:
		jump_buffer_timer = JUMP_BUFFER_TIME
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0)
	if is_jump_canceled:
		velocity.y *= JUMP_CANCELING_VELOCITY
	if jump_buffer_timer > 0 and jump_forgiveness_timer > 0:
		velocity.y -= (JUMP_SPEED + velocity.y)
		jump_buffer_timer = 0
		jump_forgiveness_timer = 0
		jumped += 1
	var jump_available = jumped < MAX_JUMP
	if jump_key_pressed and not is_on_floor() and jump_available:
		render_jump_dust()
		velocity.y -=  (MULITPLE_JUMP_SPEED + velocity.y)
		jumped += 1

func get_collide_physics_layers():
	var layers = []
	for collision_id in get_slide_collision_count():
		var collision = get_slide_collision(collision_id)
		var rid = collision.get_collider_rid()
		layers.append(PhysicsServer2D.body_get_collision_layer(rid))
	return layers

func handle_wall_slide():
	if disable_action() or  is_on_floor():
		wall_sliding = false
		return 
	if is_on_wall() and Input.get_axis("move_left", "move_right"):
		var layers = get_collide_physics_layers()
		if GameEnums.PHYSICS_LAYERS.CLIMB_WALL in layers:
			if not wall_sliding:
				velocity.y = INITIAL_WALL_GRAVITY
			wall_sliding = true
			jumped = 0
		else:
			wall_sliding = false
	else:
		wall_sliding = false

func handle_wall_jump():
	if disable_action():
		return
	var jump_key_pressed = Input.is_action_just_pressed("jump")
	if wall_sliding and jump_key_pressed and not wall_jumping:
		var push_back_direction = get_wall_normal().x
		velocity.x = push_back_direction * WALL_JUMP_SPEED_HORIZONTAL
		velocity.y -= WALL_JUMP_SPEED_VERTICAL
		get_tree().create_timer(WALL_JUMP_DURATION).timeout.connect(_end_wall_jump)
		wall_jumping = true
		jumped += MAX_JUMP
		render_wall_jump_dust()

func _end_wall_jump():
	wall_jumping = false

func handle_dash(delta):
	if hurting or wall_sliding:
		return
	var dash_key_pressed = Input.is_action_just_pressed("dash")
	dash_cooldown_time = max(dash_cooldown_time - delta, 0)
	if dash_key_pressed and not dashing and not dash_cooldown_time:
		dashing = true
		dash_cooldown_time = DASH_COOLDOWN_TIME
		get_tree().create_timer(DASH_DURATION).timeout.connect(_end_dash)
		velocity.x = latest_direction * DASH_SPEED
		velocity.y = 0
		render_dash_dust()

func _end_dash():
	dashing = false
	if velocity.x < 0:
		velocity.x += SPEED
	else:
		velocity.x -= SPEED

func render_dash_dust():
	var dust_instance = DashDust.instantiate()
	get_tree().current_scene.add_child(dust_instance)
	dust_instance.global_position = $Marker2D.global_position
	dust_instance.flip_h = latest_direction < 0

func render_jump_dust():
	var dust_instance = JumpDust.instantiate()
	get_tree().current_scene.add_child(dust_instance)
	dust_instance.global_position = $Marker2D.global_position

func render_wall_jump_dust():
	var wall_dust_instance = WallJumpDust.instantiate()
	get_tree().current_scene.add_child(wall_dust_instance)
	wall_dust_instance.global_position = $Marker2D.global_position

func handle_duck():
	if disable_action() or not is_on_floor():
		crawling = false
		return
	forced_crawl = ceiling_detection.is_colliding()
	crawling = Input.is_action_pressed("crouch") or forced_crawl
	
func render_collision():
	if crawling:
		standing_collision.set_deferred("disabled", true)
		crawling_collision.set_deferred("disabled", false)
	else:
		standing_collision.set_deferred("disabled", false)
		crawling_collision.set_deferred("disabled", true)

func handle_collision():
	var layers = get_collide_physics_layers()
	if GameEnums.PHYSICS_LAYERS.DANGER_WALL in layers and not hurting and not invincible:
		hurting = true
		invincible = true
		velocity.x = 0
		velocity.x += -latest_direction * KNOCKBACK_SPEED
		get_tree().create_timer(HURT_DURATION).timeout.connect(_end_hurt)
		get_tree().create_timer(INVINCIBLE_DURATION).timeout.connect(_end_invincible)

func _end_hurt():
	hurting = false
	velocity.x = 0

func _end_invincible():
	invincible = false

func disable_action():
	return dashing or hurting
