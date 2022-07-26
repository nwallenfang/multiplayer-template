extends Spatial

#onready var game = $Level
#onready var ui_layer: UILayer = $UILayer
onready var ready_screen = $ReadyScreen

var players := {}

var players_ready := {}
var players_score := {}

var game_started := false
var game_over := false
var players_setup := {}

signal game_started ()
signal game_over (player_id)

func _ready() -> void:
	# set Game.debug depending on cmd arguments (added by MultiRun addon)
	var args = Array(OS.get_cmdline_args())
	var is_player1 = (len(args) >= 2 and args[1] == 'player1')
	if len(args) >= 1:
		if args[0] == 'debug':
			Game.debug = true
	Game.viewport_sprite = $Sprite

	OnlineMatch.connect("error", self, "_on_OnlineMatch_error")
	OnlineMatch.connect("disconnected", self, "_on_OnlineMatch_disconnected")
	OnlineMatch.connect("player_status_changed", self, "_on_OnlineMatch_player_status_changed")
	OnlineMatch.connect("player_left", self, "_on_OnlineMatch_player_left")
	OnlineMatch.connect("matchmaker_matched", self, "_on_OnlineMatch_matchmaker_matched")
	
	if Game.debug:
		# other instance should wait a little because the first instance 
		# becomes the server
		if not is_player1:
			yield(get_tree().create_timer(0.34), "timeout")
		$MainMenu.visible = false
		Network.connect_to_matchmaking()


func _on_OnlineMatch_matchmaker_matched(_players: Dictionary):
#	ui_layer.show_screen("ReadyScreen", { players = _players })
	$ReadyScreen._show_screen({ players = _players })

#####
# OnlineMatch callbacks
#####

func _on_OnlineMatch_error(message: String):
	print("Match error ", message)
	Game.log("Match error: " + message)

func _on_OnlineMatch_disconnected():
	_on_OnlineMatch_error("Disconnected from host")

func _on_OnlineMatch_player_left(player) -> void:
	Game.log(player.username + " has left")
	
	players.erase(player.peer_id)
	players_ready.erase(player.peer_id)

func _on_OnlineMatch_player_status_changed(player, status) -> void:
	if status == OnlineMatch.PlayerStatus.CONNECTED:
		if get_tree().is_network_server():
			# Tell this new player about all the other players that are already ready.
			for session_id in players_ready:
				rpc_id(player.peer_id, "player_ready", session_id)

#####
# Gameplay methods and callbacks
#####
remotesync func player_ready(session_id: String) -> void:
	ready_screen.set_status(session_id, "READY!")
	if get_tree().is_network_server() and not players_ready.has(session_id):
		players_ready[session_id] = true
		if players_ready.size() == OnlineMatch.players.size():
			if OnlineMatch.match_state != OnlineMatch.MatchState.PLAYING:
				OnlineMatch.start_playing()
			start_game()

func start_game() -> void:
	if Game.online_play:
		players = OnlineMatch.get_player_names_by_peer_id()

	if Game.online_play:
		rpc("_do_game_setup", players)
	else:
		_do_game_setup(players)

func stop_game() -> void:
	OnlineMatch.leave()
	
	players.clear()
	players_ready.clear()
	players_score.clear()
	game_started = false

func restart_game() -> void:
	stop_game()
	start_game()


# Initializes the game so that it is ready to really start.
const LEVEL_SCENE = preload("res://Prototyping/Level.tscn")
remotesync func _do_game_setup(playerss: Dictionary) -> void:
	if game_started:
		stop_game()
	
	game_started = true
	game_over = false
	
	var level = LEVEL_SCENE.instance()
	add_child(level)
	$Level.do_game_setup(playerss)

	if Game.online_play:
		var my_id := get_tree().get_network_unique_id()
		# Tell the host that we've finished setup.
		rpc_id(1, "_finished_game_setup", my_id)

# Records when each player has finished setup so we know when all players are ready.
mastersync func _finished_game_setup(player_id: int) -> void:
	players_setup[player_id] = true
	if players_setup.size() == 2:
		# Once all clients have finished setup, tell them to start the game.
		rpc("_do_game_start")

# Actually start the game on this client.
remotesync func _do_game_start() -> void:
#	emit_signal("game_started")
	$ReadyScreen.visible = false
	Game.game_started = true
	get_tree().set_pause(false)

func _on_ReadyScreen_ready_pressed() -> void:
	rpc("player_ready", OnlineMatch.get_my_session_id())
