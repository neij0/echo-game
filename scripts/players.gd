class_name Players
extends RefCounted
## Helpers to find players without holding a fixed reference, so creatures and
## systems keep working when a second player is added. Every Player joins the
## "players" group in its _ready.


static func all(tree: SceneTree) -> Array[Player]:
	var result: Array[Player] = []
	for node: Node in tree.get_nodes_in_group("players"):
		var player := node as Player
		if player:
			result.append(player)
	return result


## The player closest to [param from], or null if there are no players.
static func nearest(tree: SceneTree, from: Vector2) -> Player:
	var best: Player = null
	var best_distance: float = INF
	for player: Player in all(tree):
		var distance: float = from.distance_squared_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best
