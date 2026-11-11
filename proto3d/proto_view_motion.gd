class_name ProtoViewMotion
extends RefCounted
## Movement on the floor under a tilted camera. A step away from the camera is
## squashed on screen by sin(pitch), so without help "up" looks slower than
## sideways. These helpers turn input into floor directions and say how much
## faster a mover must go in a direction to look equally fast on screen.
## Angles in radians; yaw as on Camera3D.rotation.y, pitch = degrees looked down.


## The floor direction that is "right" on screen.
static func right(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


## The floor direction that is "up" on screen (away from the camera).
static func forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Keys: the plain camera-relative direction. Two keys held together give an
## exact floor diagonal, so at yaw 45 they run along the room's walls.
static func plain(input: Vector2, yaw: float) -> Vector3:
	return right(yaw) * input.x - forward(yaw) * input.y


## Stick: the floor direction that looks exactly like input on screen (a stick
## pushed at 30 degrees moves the character at 30 degrees on screen).
static func screen_exact(input: Vector2, yaw: float, pitch: float) -> Vector3:
	var direction: Vector3 = right(yaw) * input.x - forward(yaw) * input.y / maxf(sin(pitch), 0.01)
	return direction.normalized() * input.length()


## How long one unit of floor in this direction looks on screen
## (1 = sideways, sin(pitch) = straight away from the camera).
static func screen_length(direction: Vector3, yaw: float, pitch: float) -> float:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.000001:
		return 1.0
	flat = flat.normalized()
	var sideways: float = flat.dot(right(yaw))
	var away: float = flat.dot(forward(yaw)) * sin(pitch)
	return sqrt(sideways * sideways + away * away)


## Speed multiplier for a mover going in direction. compensation 1 = looks
## equally fast every way, 0 = no help (the same floor speed every way).
static func speed_scale(direction: Vector3, yaw: float, pitch: float, compensation: float) -> float:
	return lerpf(1.0, 1.0 / maxf(screen_length(direction, yaw, pitch), 0.01), compensation)
