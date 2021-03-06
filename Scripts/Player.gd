extends KinematicBody


const MOVEMENTINTERPOLATION = 15.0
const ROTATIONINTERPOLATION = 10.0
const CAMERA_X_ROT_MIN = -40
const CAMERA_X_ROT_MAX = 70

export var moveSpeed = 8.0
export var grabMoveSpeed = 1.0
export var jumpSpeed = 10.5
export var playerGravity = 9.8
export var gravityMultiplier = 2.5
export var mouseSensivilityX = 0.01
export var mouseSensivilityY = 0.004
export var rightJoySensivilityX = 0.07
export var rightJoySensivilityY = 0.035
export var cameraFollowsRotation = false

var isMovingCamera = false
var recalculateAngle = false
var jump = false
var is_hanging = false
var letGo = false

var moveAmount = 0.0
var angleOffset = 0.0
var camAngleOffset = 0.0
var camera_x_rot = 0.0

var cameraTarget = Vector2()
var motionTarget = Vector2()
var motion = Vector2()

var velocity = Vector3()
var letGoPosition = Vector3()
var targetPosition = Vector3()
var targetRotation = Vector3()
var edgeVelocity = Vector3()
var prevVelocity = Vector3()

var originBasis = Basis()
var orientation = Transform()

#Nodes Variables
var cameraBase
var cameraPivot
var prevFloor
var characterMesh
var camera
var rayDown
var rayForward
var rayMaxLeft
var rayMaxRight
var animationTree
var originParent


func _init():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _ready():
	#Gets all the needed charcter related variables
	characterMesh = $CharacterMesh
	orientation = characterMesh.global_transform
	orientation.origin = Vector3()
	
	#Gets all the needed camera related variables
	cameraBase = $CameraBase
	cameraPivot = $CameraBase/CameraPivot
	camera = $CameraBase/CameraPivot/CameraOffset/Camera
	
	#Gets all the raycasts
	rayDown = $CharacterMesh/LedgeDown
	rayForward = $CharacterMesh/LedgeFoward
	rayMaxRight = $CharacterMesh/LedgeMaxRight
	rayMaxLeft = $CharacterMesh/LedgeMaxLeft
	
	#Gets the animations of the charctermehs
	animationTree = characterMesh.find_node("AnimationTree")
	
	#Gets the original parent and basis, needed to reset some parameters
	originParent = get_parent()
	originBasis = global_transform.basis
	

func _input(event):
	if event is InputEventMouseMotion:
		isMovingCamera = true
		
		#Moves the camera taking the mouse input
		cameraBase.rotate_y(event.relative.x * -mouseSensivilityX)
		cameraBase.orthonormalize()
		camera_x_rot = clamp(camera_x_rot + event.relative.y * mouseSensivilityY, deg2rad(CAMERA_X_ROT_MIN), deg2rad(CAMERA_X_ROT_MAX) )
		cameraPivot.rotation.x = -camera_x_rot


func _process(delta): 
	#Quits the game
	if Input.is_action_just_pressed("ui_cancel"): get_tree().quit()
	
	#Takes the inputs of the keyboard/gamepad
	if Input.is_action_just_pressed("ui_accept"): jump = true
	if Input.is_action_just_pressed("ui_select") and is_hanging: letGo = true
	motionTarget = Vector2 (Input.get_action_strength("ui_left") - Input.get_action_strength("ui_right"), Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up"))
	
	#Takes the inputs of the joystick for the camera
	cameraTarget = Vector2 (Input.get_action_strength("camera_left") - Input.get_action_strength("camera_right"), Input.get_action_strength("camera_down") - Input.get_action_strength("camera_up"))
	
	if Input.get_action_strength("camera_left") > 0 or Input.get_action_strength("camera_right") > 0:
		isMovingCamera = true
	
	moveAmount = motionTarget.length()
	
	#Rotates the camera based on the gamepad input
	cameraBase.rotate_y(cameraTarget.x * rightJoySensivilityX)
	cameraBase.orthonormalize()
	camera_x_rot = clamp(camera_x_rot + cameraTarget.y * rightJoySensivilityY, deg2rad(CAMERA_X_ROT_MIN), deg2rad(CAMERA_X_ROT_MAX) )
	cameraPivot.rotation.x = -camera_x_rot
	
	#Resets the level if the character falls too low
	if global_transform.origin.y < -35:
		get_tree().reload_current_scene()


func _physics_process(delta):
	motion = motion.linear_interpolate(motionTarget * moveSpeed, MOVEMENTINTERPOLATION * delta)
	
	#Gets the floor velocity
	if is_on_floor(): prevVelocity = get_floor_velocity()
	
	#Adds the direction of the camera to the movement direction
	var cam_z = - camera.global_transform.basis.z
	var cam_x = camera.global_transform.basis.x
	cam_z.y = 0
	cam_z = cam_z.normalized()
	cam_x.y = 0
	cam_x = cam_x.normalized()
	
	var direction = - cam_x * motion.x -  cam_z * motion.y
	
	#Calculates the directon of movement for the grab movement
	var b = camera.global_transform.basis
	b.z.y = 0
	b.z = b.z.normalized()
	var edgeDirection = b.xform(Vector3(-motionTarget.x, 0, motionTarget.y))
	
	velocity.x = direction.x
	velocity.z = direction.z
	
	#Sets the animation state
	if is_on_floor():
		animationTree.set("parameters/State/current", 0)
		letGoPosition = translation
		
		var speed = motion.length() / moveSpeed
		# Animation speed
		animationTree.set("parameters/Iddle-Run/blend_position", speed)
	
	if not is_hanging:
		
		animationTree.set("parameters/State/current", 0)
		if motionTarget.length() > 0.01:
			#Rotates the charcter to the direction movement
			var q_from = Quat(orientation.basis)
			var q_to = Quat(Transform().looking_at(-direction,Vector3.UP).basis)
			
			#Interpolate current rotation with desired one
			orientation.basis = Basis(q_from.slerp(q_to, delta * ROTATIONINTERPOLATION))
			
			orientation = orientation.orthonormalized() # orthonormalize orientation
			characterMesh.global_transform.basis = orientation.basis
		
		if get_slide_count() != 0 and get_slide_collision(0).collider is RigidBody and cameraFollowsRotation:
			#Rotates the camera with the floor
			if isMovingCamera or recalculateAngle or (motionTarget.length() > 0.01 and prevFloor != get_slide_collision(0).collider):
				camAngleOffset = cameraBase.transform.basis.get_euler().y - get_slide_collision(0).collider.global_transform.basis.get_euler().y
				prevFloor = get_slide_collision(0).collider
			elif is_on_floor():
				cameraBase.transform.basis = Basis(Vector3.UP, get_slide_collision(0).collider.global_transform.basis.get_euler().y + camAngleOffset)
		
		#Rotates the character with the floor
		if get_slide_count() != 0 and get_slide_collision(0).collider is RigidBody:
			if motionTarget.length() > 0.01 or recalculateAngle:
				recalculateAngle = false
				angleOffset = characterMesh.transform.basis.get_euler().y - get_slide_collision(0).collider.global_transform.basis.get_euler().y
			elif is_on_floor():
				characterMesh.transform.basis = Basis(Vector3.UP, get_slide_collision(0).collider.global_transform.basis.get_euler().y + angleOffset)
		
		#Detects if the character can grab
		if rayMaxLeft.is_colliding() and rayMaxRight.is_colliding() and rayForward.is_colliding() and velocity.y < 0 and not is_on_floor():
			var fallDiff = translation - letGoPosition
			if rayDown.get_collision_normal().y > 0.5 and fallDiff.length() > 1:
				letGoPosition = Vector3()
				is_hanging = true
				
				var parent = rayDown.get_collider()
				var prevPosition = global_transform.origin
				var prevRotation = global_transform.basis
				var prevCamRotation = cameraBase.global_transform.basis
				
				#Reparents the character to the platform (to handle movement/rotation)
				if parent != null:
					get_parent().remove_child(self)
					parent.add_child(self)
					translation = Vector3()
					global_transform.origin = prevPosition
					if cameraFollowsRotation:
						global_transform.basis = prevRotation
						cameraBase.global_transform.basis = prevCamRotation
					
					prevVelocity = Vector3()
					if parent is RigidBody:
						prevVelocity = parent.linear_velocity
	
	elif is_hanging:
		
		motionTarget = Vector2()
		
		#Gets the movement of the platform
		if rayDown.is_colliding() and rayDown.get_collider() is RigidBody:
			prevVelocity.x = rayDown.get_collider().linear_velocity.x
			prevVelocity.z = rayDown.get_collider().linear_velocity.z
		
		#Gets the position and rotation relative to the wall of the platform
		targetPosition = rayForward.get_collision_point() + rayForward.get_collision_normal() * 0.35
		targetPosition.y = rayDown.get_collision_point().y - 1.82
		
		targetRotation = rayForward.get_collision_normal()
		targetRotation.y = 0
		targetRotation = targetRotation.normalized()
		
		#Rotates the character to face the edge
		var q_from = Quat(orientation.basis)
		var q_to = Quat(Transform().looking_at(targetRotation, Vector3.UP).basis)
		
		#Interpolate current rotation with desired one
		orientation.basis = Basis(q_from.slerp(q_to, delta * ROTATIONINTERPOLATION))
		
		orientation = orientation.orthonormalized() # orthonormalize orientation
		characterMesh.global_transform.basis = orientation.basis
		
		animationTree.set("parameters/State/current", 1)
		
		#Recalculates the chacter position relative to the wall (needed for curved walls and moving platforms)
		if moveAmount > 0.01 or (targetPosition - global_transform.origin).length() > 0.02:
			global_transform.origin = global_transform.origin.linear_interpolate(targetPosition, MOVEMENTINTERPOLATION * delta)
		else :
			global_transform.origin.y = targetPosition.y
		
		
		if letGo:
			letGo = false
			is_hanging = false
			
			clear_parent()
			
			letGoPosition = translation
		
		velocity = Vector3()
		
		#Moves the character relative to the platform's wall
		if rayDown.is_colliding() and rayDown.get_collision_normal().y >= 0.96:
			var calculateRight = rayForward.get_collision_normal().cross(Vector3.UP)
			var edgeMovement = Vector3()
			
			animationTree.set("parameters/Hanging/blend_position", edgeVelocity.length() / grabMoveSpeed)
			
			if not rayMaxRight.is_colliding() or not rayMaxLeft.is_colliding(): edgeVelocity = Vector3.ZERO
			
			if edgeDirection.dot(calculateRight) > 0.25 and rayMaxLeft.is_colliding():
				edgeMovement += calculateRight
				animationTree.set("parameters/Hanging/blend_position", -edgeVelocity.length() * moveAmount/ grabMoveSpeed)
			elif edgeDirection.dot(calculateRight) < -0.25 and rayMaxRight.is_colliding():
				edgeMovement -= calculateRight
				animationTree.set("parameters/Hanging/blend_position", edgeVelocity.length() * moveAmount/ grabMoveSpeed)
			
			edgeMovement = edgeMovement.normalized()
			edgeVelocity = edgeVelocity.linear_interpolate(edgeMovement * grabMoveSpeed, MOVEMENTINTERPOLATION * delta)
			
			velocity += edgeVelocity * moveAmount
	
	
	if is_on_floor() and jump:
		#Adds the jump speed and the floor velocity to the character velocity
		velocity += prevVelocity
		velocity.y += jumpSpeed
		velocity = move_and_slide(velocity, Vector3.UP)
	elif jump and is_hanging:
		clear_parent()
		#Adds the jump speed and the platform velocity to the character velocity
		velocity += prevVelocity
		velocity.y += jumpSpeed - 0.5
		is_hanging = false
		velocity = move_and_slide(velocity, Vector3.UP)
	else:
		#Moves the charcter with the platform/floor velocity
		if not is_on_floor() and not is_hanging:
			velocity.x += prevVelocity.x
			velocity.z += prevVelocity.z
		velocity = move_and_slide_with_snap(velocity, Vector3.DOWN, Vector3.UP)
		velocity.y += -playerGravity * gravityMultiplier * delta
	
	if not is_on_floor() and not is_hanging: animationTree.set("parameters/State/current", 2)
	
	jump = false
	
	isMovingCamera = false
	
	#Resets the camera basis
	if cameraFollowsRotation:
		global_transform.basis.x.y = 0
	else:
		global_transform.basis = originBasis
	
	if not is_on_floor() : recalculateAngle = true


func clear_parent():
	var position = global_transform.origin
	var prevRotation = global_transform.basis
	var prevCamRotation = cameraBase.global_transform.basis
	
	#Reparents the character to its original parent
	get_parent().remove_child(self)
	originParent.add_child(self)
	global_transform.origin = position
	if cameraFollowsRotation:
		global_transform.basis = prevRotation
		cameraBase.global_transform.basis = prevCamRotation