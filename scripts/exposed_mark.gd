class_name ExposedMark
extends GlowLines
## A bright gold ring on the floor round a creature while it is Exposed (hit by
## a pulse front). The ring shrinks towards the body as the Exposed time runs
## out, so the Guardian can see how long he has left to land the finisher.
## Small marks on the ring, like a target lock. Drawn over rock.

@export var creature: Creature
@export var color: Color = Color(1.0, 0.78, 0.2)
@export var width: float = 0.06
## Ring radius at the start, added to the body radius...
@export var start_extra_radius: float = 0.44
## ...and when Exposed is about to end.
@export var end_extra_radius: float = 0.06
@export var tick_count: int = 4
@export var tick_length: float = 0.14


func _process(_delta: float) -> void:
	clear()
	if creature and creature.is_exposed():
		var ratio: float = creature.get_exposed_ratio()
		var center: Vector3 = creature.get_global_transform_interpolated().origin
		var radius: float = creature.body_radius + lerpf(end_extra_radius, start_extra_radius, ratio)
		var tint := Color(color, lerpf(0.5, 1.0, ratio))
		add_ring(center, radius, width, tint)
		for i: int in tick_count:
			var angle: float = TAU * float(i) / float(tick_count) + PI * 0.25
			var out := Vector3(cos(angle), 0.0, sin(angle))
			add_polyline(PackedVector3Array([center + out * radius, center + out * (radius + tick_length)]), width, tint)
	commit()
