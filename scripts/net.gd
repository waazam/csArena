extends Node
## Autoload "Net" — session state and multiplayer plumbing.
## PvE runs fully offline (the default OfflineMultiplayerPeer makes every
## call_local RPC execute locally, so gameplay code is shared between modes).

const PORT := 7777
const MAX_PLAYERS := 8

enum { MODE_PVE, MODE_PVP }

var mode := MODE_PVE
var online := false

signal join_failed(reason: String)

func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func start_pve() -> void:
	_reset_peer()
	mode = MODE_PVE
	online = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")

## Returns "" on success, otherwise a human-readable error.
func host_pvp() -> String:
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS) != OK:
		return "Could not start server — is port %d already in use?" % PORT
	multiplayer.multiplayer_peer = peer
	mode = MODE_PVP
	online = true
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	return ""

## Returns "" on success (connection continues in the background).
func join_pvp(ip: String) -> String:
	if ip.is_empty():
		return "Enter the host's IP address first."
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		return "Invalid address: %s" % ip
	multiplayer.multiplayer_peer = peer
	mode = MODE_PVP
	online = true
	return ""

func leave_to_menu() -> void:
	_reset_peer()
	mode = MODE_PVE
	online = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_connected_to_server() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_connection_failed() -> void:
	_reset_peer()
	online = false
	join_failed.emit("Connection failed — check the IP and that the host is running.")

func _on_server_disconnected() -> void:
	leave_to_menu()

func _reset_peer() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
