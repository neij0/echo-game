class_name AnglerVisual
extends Node2D
## The look of "The Angler" (boss): a huge dark anglerfish (AnglerBody), its
## lure with a real light (AnglerLure) and its glowing details (AnglerGlow, on
## an own unlit CanvasLayer). This node holds the states and one-shot moments
## and drives the three parts every frame; the fight logic (or the preview
## tool) only calls the API below. Visual only: no collision, no damage.
## States (set_state): SWIM (idle / swimming: slow, heavy undulation; teal
## lure), TELEGRAPH (lure flares hot white-yellow and flickers, jaw opens wide,
## body coils back), CHARGE (fast: tight quick undulation, fins tucked, jaw
## half open, afterimage trail, sediment kicked up), STUNNED (rolled on its
## side, lure dim, drooping and flickering, slack jaw, glints circling).
## One-shots: bite() (jaw opens, snaps shut, teeth flash, head lunges),
## hit(from) (flinch away, rim flash), roar() (phase change: jaw wide, body
## shudders, a light ring from the lure, screen shake), die() (eyes go out,
## the body sinks into the dark with bubbles, the lure fades out last),
## hide_for_intro() / reveal() (only the lure is seen, then a light flash
## reveals the body). set_exposed(ratio): sonar outline on the plates + weak spots.
## Motion: the parent's velocity (a CharacterBody2D) or set_motion(); facing:
## the motion, or face() while aiming (telegraph).
## Always seen in side profile: it faces left or right (a turn is a flip) and
## tilts at most max_tilt_degrees towards up / down, never a view from above.

signal state_changed(new_state: State)
signal bitten
signal hit_taken
signal roared
signal revealed
signal died
## Emitted when a charge starts (sound).
signal charge_started

enum State { SWIM, TELEGRAPH, CHARGE, STUNNED }

@export_group("Body")
## The head centre sits this far ahead of this node (the middle of the body).
@export var head_offset: float = 70.0
## Telegraph: the head pulls back this far as the body coils.
@export var coil_pullback: float = 18.0

@export_group("Turning")
## Degrees per second it turns towards its heading (heavy and slow)...
@export var turn_speed: float = 75.0
## ...while telegraphing (it lines up the charge)...
@export var telegraph_turn_speed: float = 140.0
## ...and while charging (almost straight).
@export var charge_turn_speed: float = 12.0

@export_group("Profile")
## Moving up / down the screen tilts the side view this much at most.
@export var max_tilt_degrees: float = 30.0
## It flips to the other side only when the wanted direction points this
## much (share of its length) that way...
@export_range(0.0, 1.0) var flip_threshold: float = 0.2
## ...and not again within this many seconds.
@export var flip_cooldown: float = 0.4
## Stunned: the nose dips this much (rolled onto its side).
@export var stun_tilt_degrees: float = 14.0

@export_group("Swimming")
## Undulation (cycles per second): standing, at full_speed, charging, stunned.
@export var idle_wave_speed: float = 0.28
@export var swim_wave_speed: float = 0.85
@export var charge_wave_speed: float = 2.6
@export var stunned_wave_speed: float = 0.12
@export var full_speed: float = 170.0
## Undulation amplitude share while charging / stunned.
@export_range(0.0, 2.0) var charge_wave_scale: float = 0.45
@export_range(0.0, 2.0) var stunned_wave_scale: float = 0.2
## How fast states blend in / out (per second).
@export var blend_speed: float = 4.0
## Seconds to coil fully at the start of a telegraph.
@export var telegraph_ramp_time: float = 0.45

@export_group("Jaw")
@export_range(0.0, 1.0) var idle_jaw: float = 0.08
## Slow breathing of the jaw: amount and cycles per second.
@export_range(0.0, 1.0) var jaw_breath: float = 0.07
@export var jaw_breath_speed: float = 0.2
@export_range(0.0, 1.0) var telegraph_jaw: float = 0.95
@export_range(0.0, 1.0) var charge_jaw: float = 0.5
@export_range(0.0, 1.0) var stunned_jaw: float = 0.4
## Gill pulse (cycles per second), faster when telegraphing or charging.
@export var gill_speed: float = 0.5
@export var gill_fast_speed: float = 2.2

@export_group("Lure")
@export var calm_color: Color = Color(0.25, 1.0, 0.85)
@export var calm_energy: float = 1.6
@export var calm_light: float = 1.15
@export var telegraph_color: Color = Color(1.0, 0.93, 0.62)
@export var telegraph_energy: float = 3.6
@export var telegraph_light: float = 2.3
## Telegraph flicker (cycles per second) and depth (0-1).
@export var telegraph_flicker_speed: float = 15.0
@export_range(0.0, 1.0) var telegraph_flicker: float = 0.35
@export var stunned_color: Color = Color(0.32, 0.6, 0.55)
@export var stunned_energy: float = 0.45
@export var stunned_light: float = 0.35
## Light added at a roar / reveal (fades out).
@export var flash_light: float = 5.0
@export var flash_decay: float = 3.0

@export_group("Bite")
@export var bite_time: float = 0.36
## Seconds into the bite when the jaw snaps shut.
@export var bite_snap_at: float = 0.17
@export var bite_lunge: float = 16.0
@export var teeth_flash_time: float = 0.18

@export_group("Hit")
@export var hit_time: float = 0.3
@export var flinch_distance: float = 10.0
@export var flinch_kink: float = 14.0
@export var rim_flash_time: float = 0.16

@export_group("Roar")
@export var roar_time: float = 1.5
@export var shudder_amount: float = 3.5
@export var shudder_speed: float = 38.0
@export var shake_strength: float = 11.0
@export var shake_duration: float = 0.7

@export_group("Death")
@export var death_time: float = 4.6
## Pixels the body sinks (down the screen) while it fades into the dark.
@export var death_sink: float = 30.0
@export_range(0.0, 1.0) var death_scale: float = 0.9
@export var eyes_out_at: float = 0.5
@export var lure_hold_until: float = 3.0
@export var bubbles_per_second: float = 16.0

@export_group("Tail Sweep")
## The tail bends this far (pixels) while it coils and when it sweeps.
@export var sweep_curl_amount: float = 70.0
## Radius of the glowing arc the sweep traces round it.
@export var sweep_arc_radius: float = 190.0

@export_group("Intro")
@export var reveal_time: float = 0.6

@export_group("Charge")
## Seconds between afterimages.
@export var trail_interval: float = 0.05
@export var sediment_color: Color = Color(0.55, 0.5, 0.4, 0.7)
@export var sediment_amount: int = 70

var state: State = State.SWIM
## Where it faces: always mostly left or right (see max_tilt_degrees).
var heading: Vector2 = Vector2.RIGHT
## Set by the fight logic (or the preview) when the parent is no CharacterBody2D.
var motion_velocity: Vector2 = Vector2.ZERO
var is_dead: bool = false
var is_hidden_for_intro: bool = false

var body: AnglerBody
var lure: AnglerLure
var glow: AnglerGlow
var _sediment: CPUParticles2D
var _time: float = 0.0
var _face: Vector2 = Vector2.ZERO
## heading with the stunned nose dip (what the body and the lure use).
var _shown: Vector2 = Vector2.RIGHT
var _flip_left: float = 0.0
var _fake: float = 0.0
## The sweep's warning (0-1, set by the fight logic) and the sweep itself.
var _sweep_wind: float = 0.0
var _sweep_age: float = -1.0
var _sweep_time: float = 0.45
var _sweep_flipped: bool = false
var _fake_offset: Vector2 = Vector2.ZERO
var _telegraph: float = 0.0
var _charge: float = 0.0
var _stun: float = 0.0
var _exposed: float = 0.0
var _exposed_target: float = 0.0
var _bite_age: float = -1.0
var _hit_age: float = -1.0
var _hit_dir: Vector2 = Vector2.ZERO
var _roar_age: float = -1.0
var _death_age: float = -1.0
var _reveal_age: float = -1.0
var _flash: float = 0.0
var _trail_left: float = 0.0
var _bubble_left: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	body = AnglerBody.new()
	add_child(body)
	lure = AnglerLure.new()
	add_child(lure)
	var layer := CanvasLayer.new()
	layer.follow_viewport_enabled = true
	add_child(layer)
	glow = AnglerGlow.new()
	glow.body = body
	glow.lure = lure
	layer.add_child(glow)
	_sediment = _make_sediment()
	add_child(_sediment)
	_shown = heading
	body.reset(_head_position(), heading)
	lure.reset(_lure_base(), heading)


# --- API -------------------------------------------------------------------

func set_state(new_state: State) -> void:
	if new_state == state or is_dead:
		return
	state = new_state
	if state == State.CHARGE:
		charge_started.emit()
	state_changed.emit(state)


func set_motion(velocity: Vector2) -> void:
	motion_velocity = velocity


## Turns towards direction (zero = follow the motion again).
func face(direction: Vector2) -> void:
	_face = direction.normalized() if direction.length() > 0.001 else Vector2.ZERO


## Points it at direction right away (spawning, the preview).
func snap_heading(direction: Vector2) -> void:
	heading = _profile_direction(direction)
	_shown = heading
	body.reset(_head_position(), heading)
	lure.reset(_lure_base(), heading)


func set_exposed(ratio: float) -> void:
	_exposed_target = clampf(ratio, 0.0, 1.0)


func bite() -> void:
	if is_dead:
		return
	_bite_age = 0.0
	bitten.emit()


func hit(from_position: Vector2) -> void:
	if is_dead:
		return
	_hit_age = 0.0
	_hit_dir = from_position.direction_to(global_position)
	hit_taken.emit()


func roar() -> void:
	if is_dead:
		return
	_roar_age = 0.0
	_flash = 1.0
	glow.add_ring(lure.get_orb_position())
	var camera: Node = get_tree().get_first_node_in_group("shared_camera")
	if camera and camera.has_method("shake_with"):
		camera.call("shake_with", shake_strength, shake_duration)
	roared.emit()


func die() -> void:
	if is_dead:
		return
	is_dead = true
	_death_age = 0.0
	died.emit()


## Intro: only the lure (and its light) is seen.
func hide_for_intro() -> void:
	is_hidden_for_intro = true
	_reveal_age = -1.0


## Intro: a light flash from the lure reveals the body.
func reveal() -> void:
	is_hidden_for_intro = false
	_reveal_age = 0.0
	_flash = 1.0
	glow.add_ring(lure.get_orb_position())
	revealed.emit()


## Phase 2 trick: the orb goes dark and a lure glows at orb + offset instead
## (its light moves there too). strength 0 = off, 1 = fully faked.
func set_fake_lure(offset: Vector2, strength: float) -> void:
	_fake_offset = offset
	_fake = clampf(strength, 0.0, 1.0)


## The tail sweep's warning: 0 = none, 1 = fully coiled, fins flared.
func set_sweep_wind(amount: float) -> void:
	_sweep_wind = clampf(amount, 0.0, 1.0)


## The tail sweep: the tail whips round (one turn in duration seconds, the
## body turning about halfway) and a glowing arc traces it.
func sweep(duration: float) -> void:
	if is_dead:
		return
	_sweep_age = 0.0
	_sweep_time = maxf(duration, 0.05)
	_sweep_flipped = false
	glow.start_sweep(duration, sweep_arc_radius, signf(heading.x))


func is_death_done() -> bool:
	return is_dead and _death_age >= death_time


func get_orb_position() -> Vector2:
	return lure.get_orb_position()


# --- Per frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var velocity: Vector2 = _get_velocity()
	var speed_ratio: float = clampf(velocity.length() / full_speed, 0.0, 1.0)
	_update_blends(delta)
	_update_heading(delta, velocity)
	_advance_one_shots(delta)

	var bite_jaw: float = _bite_jaw()
	var jaw: float = idle_jaw + jaw_breath * (0.5 + 0.5 * sin(_time * TAU * jaw_breath_speed))
	jaw = lerpf(jaw, telegraph_jaw, _telegraph * (1.0 - _charge))
	jaw = lerpf(jaw, charge_jaw, _charge)
	jaw = lerpf(jaw, stunned_jaw, _stun)
	if _roar_age >= 0.0:
		jaw = lerpf(jaw, 1.0, _envelope(_roar_age, 0.12, roar_time - 0.35, 0.3))
	if bite_jaw >= 0.0:
		jaw = bite_jaw
	if is_dead:
		jaw = lerpf(jaw, 0.55, minf(_death_age / 1.0, 1.0))

	var wave_speed: float = lerpf(idle_wave_speed, swim_wave_speed, speed_ratio)
	wave_speed = lerpf(wave_speed, charge_wave_speed, _charge)
	wave_speed = lerpf(wave_speed, stunned_wave_speed, _stun)
	var wave_scale: float = lerpf(1.0, charge_wave_scale, _charge) * lerpf(1.0, stunned_wave_scale, _stun) * (1.0 + 0.6 * _telegraph)
	if is_dead:
		wave_scale *= maxf(1.0 - _death_age / 1.5, 0.0)

	body.heading = _shown
	body.jaw_open = jaw
	body.coil = maxf(_telegraph * (1.0 - _charge), _sweep_wind * 0.9)
	body.fin_flare = maxf(_sweep_wind, 1.0 if _sweep_age >= 0.0 else 0.0)
	body.sweep_curl = _sweep_curl()
	body.lunge = _bite_lunge() - _hit_flinch()
	body.roll = maxf(_stun, minf(_death_age / 2.0, 1.0) * 0.6 if is_dead else 0.0)
	body.fin_tuck = _charge
	body.kink = _hit_kink()
	var gill_rate: float = lerpf(gill_speed, gill_fast_speed, maxf(_telegraph, _charge))
	body.gill_open = 0.5 + 0.5 * sin(_time * TAU * gill_rate) if not is_dead else 0.0
	body.update_pose(_head_position(), delta, wave_speed, wave_scale)

	lure.update_pose(_lure_base(), _shown, maxf(_stun, _death_sag()), delta)
	_update_lure_glow(delta)
	_update_glow(delta)
	_update_presence(delta)
	_update_sediment()


func _get_velocity() -> Vector2:
	var parent_body := get_parent() as CharacterBody2D
	return parent_body.velocity if parent_body else motion_velocity


func _update_blends(delta: float) -> void:
	var step: float = blend_speed * delta
	var telegraph_step: float = delta / maxf(telegraph_ramp_time, 0.01)
	_telegraph = move_toward(_telegraph, 1.0 if state == State.TELEGRAPH else 0.0, telegraph_step if state == State.TELEGRAPH else step * 2.0)
	_charge = move_toward(_charge, 1.0 if state == State.CHARGE else 0.0, step * 2.0)
	_stun = move_toward(_stun, 1.0 if state == State.STUNNED else 0.0, step)
	_exposed = move_toward(_exposed, _exposed_target, step * 2.0)


func _update_heading(delta: float, velocity: Vector2) -> void:
	_flip_left = maxf(_flip_left - delta, 0.0)
	if not is_dead and state != State.STUNNED:
		var target: Vector2 = Vector2.ZERO
		if _face != Vector2.ZERO:
			target = _face
		elif velocity.length() > 12.0:
			target = velocity.normalized()
		if target != Vector2.ZERO:
			var wanted: Vector2 = _profile_direction(target)
			# A turn to the other side is a flip (never through a view from above).
			if signf(wanted.x) != signf(heading.x) and state != State.CHARGE and _flip_left <= 0.0:
				_flip()
			if signf(wanted.x) == signf(heading.x):
				var rate: float = turn_speed
				if state == State.TELEGRAPH:
					rate = telegraph_turn_speed
				elif state == State.CHARGE:
					rate = charge_turn_speed
				var angle: float = heading.angle_to(wanted)
				var turn: float = deg_to_rad(rate) * delta
				heading = heading.rotated(clampf(angle, -turn, turn)).normalized()
	# Stunned / dying: the nose dips (rolled onto its side).
	var dip: float = deg_to_rad(stun_tilt_degrees) * maxf(_stun, minf(_death_age / 2.0, 1.0) if is_dead else 0.0)
	_shown = heading.rotated(dip * signf(heading.x))


## direction as a side view: left or right (kept when it points almost straight
## up / down), tilted at most max_tilt_degrees.
func _profile_direction(direction: Vector2) -> Vector2:
	var d: Vector2 = direction.normalized()
	var side: float = signf(heading.x) if heading.x != 0.0 else 1.0
	if absf(d.x) > flip_threshold:
		side = signf(d.x)
	var limit: float = deg_to_rad(max_tilt_degrees)
	var tilt: float = clampf(atan2(d.y, absf(d.x)), -limit, limit)
	return Vector2(side * cos(tilt), sin(tilt))


## Turns to face the other way at once: the body and the lure are mirrored
## round this node (a sprite-like flip; the tail and the orb then settle).
func _flip() -> void:
	_flip_left = flip_cooldown
	heading.x = -heading.x
	_shown.x = -_shown.x
	body.mirror_x(global_position.x)
	lure.mirror_x(global_position.x)


func _advance_one_shots(delta: float) -> void:
	if _bite_age >= 0.0:
		_bite_age += delta
		if _bite_age >= bite_time + teeth_flash_time:
			_bite_age = -1.0
	if _hit_age >= 0.0:
		_hit_age += delta
		if _hit_age >= hit_time:
			_hit_age = -1.0
	if _roar_age >= 0.0:
		_roar_age += delta
		if _roar_age >= roar_time:
			_roar_age = -1.0
	if _reveal_age >= 0.0:
		_reveal_age += delta
		if _reveal_age >= reveal_time:
			_reveal_age = -1.0
	if _death_age >= 0.0:
		_death_age += delta
	if _sweep_age >= 0.0:
		_sweep_age += delta
		# Halfway round it faces the other way (it spun).
		if not _sweep_flipped and _sweep_age >= _sweep_time * 0.5:
			_sweep_flipped = true
			_flip()
		if _sweep_age >= _sweep_time:
			_sweep_age = -1.0
	_flash = maxf(_flash - flash_decay * delta, 0.0)


## The jaw during a bite (-1 = no bite): opens wide, then snaps shut.
func _bite_jaw() -> float:
	if _bite_age < 0.0:
		return -1.0
	if _bite_age < bite_snap_at * 0.7:
		return smoothstep(0.0, bite_snap_at * 0.7, _bite_age)
	if _bite_age < bite_snap_at:
		return 1.0 - smoothstep(bite_snap_at * 0.7, bite_snap_at, _bite_age)
	return 0.0


func _bite_lunge() -> float:
	if _bite_age < 0.0:
		return 0.0
	var t: float = (_bite_age - bite_snap_at * 0.6) / maxf(bite_time - bite_snap_at * 0.6, 0.01)
	return bite_lunge * sin(clampf(t, 0.0, 1.0) * PI)


func _hit_flinch() -> float:
	return flinch_distance * _hit_curve() if _hit_dir.dot(heading) < 0.0 else -flinch_distance * 0.5 * _hit_curve()


func _hit_kink() -> float:
	return flinch_kink * _hit_curve() * signf(_hit_dir.dot(heading.orthogonal()) + 0.001)


func _hit_curve() -> float:
	if _hit_age < 0.0:
		return 0.0
	var t: float = _hit_age / hit_time
	return sin(minf(t * 3.0, 1.0) * PI * 0.5) * (1.0 - t)


## The tail's sideways bend: curled back while it winds up, then a whip that
## swings it across and back during the sweep.
func _sweep_curl() -> float:
	if _sweep_age >= 0.0:
		return sweep_curl_amount * 1.6 * sin(_sweep_age / _sweep_time * TAU)
	return -sweep_curl_amount * _sweep_wind


func _death_sag() -> float:
	return clampf((_death_age - 1.0) / 2.0, 0.0, 1.0) if is_dead else 0.0


func _head_position() -> Vector2:
	var position_now: Vector2 = global_position + _shown * (head_offset - coil_pullback * _telegraph * (1.0 - _charge))
	if _roar_age >= 0.0:
		var shudder: float = shudder_amount * _envelope(_roar_age, 0.08, roar_time - 0.4, 0.3)
		position_now += Vector2(sin(_time * shudder_speed), cos(_time * shudder_speed * 1.3)) * shudder
	return position_now


func _lure_base() -> Vector2:
	if body == null or body.shape.is_empty():
		return global_position + _shown * (head_offset + 20.0)
	return body.point_at(0.0, 0.0) + _shown * (body.head_front * 0.55 + body.lunge) + Vector2(0.0, -8.0)


func _update_lure_glow(_delta: float) -> void:
	var color: Color = calm_color
	var energy: float = calm_energy
	var light: float = calm_light
	var hot: float = _telegraph * (1.0 - _charge * 0.5)
	if hot > 0.0:
		var flicker: float = 1.0 - telegraph_flicker * hot * (0.5 + 0.5 * sin(_time * TAU * telegraph_flicker_speed))
		color = color.lerp(telegraph_color, hot)
		energy = lerpf(energy, telegraph_energy, hot) * flicker
		light = lerpf(light, telegraph_light, hot) * flicker
	if _stun > 0.0:
		# A dim, uneven flicker (two waves that drift apart).
		var falter: float = 0.65 + 0.35 * sin(_time * 7.3) * sin(_time * 2.9 + 1.0)
		color = color.lerp(stunned_color, _stun)
		energy = lerpf(energy, stunned_energy * falter, _stun)
		light = lerpf(light, stunned_light * falter, _stun)
	light += flash_light * _flash
	energy += flash_light * 0.5 * _flash
	if is_dead:
		var fade: float = 1.0 - clampf((_death_age - lure_hold_until) / maxf(death_time - lure_hold_until, 0.01), 0.0, 1.0)
		var dying_flicker: float = 1.0 if _death_age < lure_hold_until else (0.5 + 0.5 * sin(_death_age * 23.0)) * 0.6 + 0.4
		energy *= fade * dying_flicker
		light *= fade * dying_flicker
	lure.light_offset = _fake_offset * _fake
	lure.set_glow(color, light)
	glow.orb_color = color
	glow.orb_energy = energy
	glow.fake_offset = _fake_offset
	glow.fake = _fake


func _update_glow(delta: float) -> void:
	glow.exposed = _exposed
	glow.stun = _stun
	glow.fin_flare = maxf(_sweep_wind, 1.0 if _sweep_age >= 0.0 else 0.0)
	glow.rim_flash = 1.0 - clampf(_hit_age / rim_flash_time, 0.0, 1.0) if _hit_age >= 0.0 else 0.0
	glow.teeth_flash = 0.0
	if _bite_age >= bite_snap_at:
		glow.teeth_flash = 1.0 - clampf((_bite_age - bite_snap_at) / teeth_flash_time, 0.0, 1.0)
	var eyes: float = lerpf(1.0, 0.35, _stun) * (1.0 + 0.6 * _telegraph)
	if is_dead:
		eyes *= 1.0 - clampf(_death_age / eyes_out_at, 0.0, 1.0)
	glow.eye_level = eyes
	if _charge > 0.3 and not is_dead:
		_trail_left -= delta
		if _trail_left <= 0.0:
			_trail_left = trail_interval
			glow.add_trail_snapshot(body.get_silhouette())
	if is_dead and _death_age < death_time - 1.2:
		_bubble_left -= delta
		while _bubble_left <= 0.0:
			_bubble_left += 1.0 / bubbles_per_second
			var at: Vector2 = body.point_at(_rng.randf_range(0.0, 0.9), _rng.randf_range(-0.8, 0.8))
			glow.add_bubble(at, _rng.randf_range(1.5, 4.5))
	glow.step(delta)


## Intro hiding, the reveal fade-in and the death fade.
func _update_presence(_delta: float) -> void:
	var alpha: float = 1.0
	if is_hidden_for_intro:
		alpha = 0.0
	elif _reveal_age >= 0.0:
		alpha = smoothstep(0.0, reveal_time, _reveal_age)
	var dark: float = 0.0
	var sink: float = 0.0
	var scale_now: float = 1.0
	if is_dead:
		var t: float = clampf(_death_age / (death_time - 1.0), 0.0, 1.0)
		dark = t
		sink = death_sink * t * t
		scale_now = lerpf(1.0, death_scale, t)
	var shade: float = 1.0 - dark
	# Opaque while it darkens (no layers showing through), gone at the very end.
	var fade_out: float = 1.0 - smoothstep(0.85, 1.0, dark)
	body.modulate = Color(shade, shade, shade, alpha * fade_out)
	lure.stalk_visible = not is_hidden_for_intro
	lure.modulate = Color(shade, shade, shade, alpha * fade_out)
	body.position = Vector2(0.0, sink)
	body.scale = Vector2(scale_now, scale_now)
	glow.body_glow = alpha * (1.0 - dark)


func _update_sediment() -> void:
	_sediment.emitting = _charge > 0.4 and not is_dead
	if body.shape.size() > 2:
		_sediment.global_position = body.point_at(0.65, 0.0) + Vector2(0.0, body.flank_depth + 6.0)
		_sediment.direction = -_shown


func _make_sediment() -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.amount = sediment_amount
	particles.lifetime = 0.9
	particles.emitting = false
	particles.local_coords = false
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 34.0
	particles.spread = 55.0
	particles.initial_velocity_min = 30.0
	particles.initial_velocity_max = 110.0
	particles.damping_min = 60.0
	particles.damping_max = 120.0
	particles.gravity = Vector2(0.0, 18.0)
	particles.scale_amount_min = 1.5
	particles.scale_amount_max = 3.5
	particles.color = sediment_color
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.8))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	particles.color_ramp = fade
	return particles


## 0 -> 1 over attack, holds, then 1 -> 0 over release (time t, hold ends at hold_end).
static func _envelope(t: float, attack: float, hold_end: float, release: float) -> float:
	if t < attack:
		return t / attack
	if t < hold_end:
		return 1.0
	return clampf(1.0 - (t - hold_end) / release, 0.0, 1.0)
