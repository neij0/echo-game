class_name RunManager
extends Node
## The run's core loop: registers players (spawn, signals), counts run stats,
## alerts creatures and awareness on every pulse, and ends the run on death or
## when the ancient light is activated. Never holds a single fixed player, so a
## second player only needs to be spawned and passed to register_player().

signal player_registered(player: Player)

@export var level: DescentLevel
@export var awareness: DepthAwareness
@export var ancient_light: AncientLight
@export var end_screen: EndScreen
## Seconds between activating the ancient light and showing the summary.
@export var victory_delay: float = 3.0

var players: Array[Player] = []
var run_time: float = 0.0
var pulses_used: int = 0
var hits_taken: int = 0
var is_over: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ancient_light:
		ancient_light.activated.connect(_on_ancient_light_activated)
	if end_screen:
		end_screen.restart_requested.connect(restart)
	# Deferred so every Player in the scene has run _ready and joined its group.
	_register_scene_players.call_deferred()


func _process(delta: float) -> void:
	if not is_over and not get_tree().paused:
		run_time += delta


func _register_scene_players() -> void:
	for player: Player in Players.all(get_tree()):
		register_player(player)


func register_player(player: Player) -> void:
	if player in players:
		return
	players.append(player)
	if level:
		player.global_position = level.get_spawn_position(player.player_number)
	player.pulse_emitted.connect(_on_pulse_emitted.bind(player))
	player.health.hit_taken.connect(_on_hit_taken)
	player.health.died.connect(_on_player_died)
	player_registered.emit(player)


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_pulse_emitted(origin: Vector2, player: Player) -> void:
	pulses_used += 1
	if awareness:
		awareness.add_pulse()
	get_tree().call_group("creatures", "hear_pulse", origin, player)


func _on_hit_taken() -> void:
	hits_taken += 1


func _on_player_died(cause: PlayerHealth.Cause) -> void:
	# Single player: any death ends the run. (Co-op later: only when all are down.)
	if is_over:
		return
	is_over = true
	get_tree().paused = true
	if end_screen:
		end_screen.show_death(cause)


func _on_ancient_light_activated() -> void:
	if is_over:
		return
	is_over = true
	await get_tree().create_timer(victory_delay).timeout
	get_tree().paused = true
	if end_screen:
		end_screen.show_victory(run_time, pulses_used, hits_taken, _best_oxygen_ratio())


func _best_oxygen_ratio() -> float:
	var best: float = 0.0
	for player: Player in players:
		best = maxf(best, player.oxygen.get_ratio())
	return best
