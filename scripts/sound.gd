extends Node
## Audio local, sin servicios externos. M silencia; preferencia compartida con T.

signal settings_changed

var muted := false
var _ambience: AudioStreamPlayer
var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _next := 0


func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.load(T.SETTINGS_PATH)
	muted = bool(cfg.get_value("audio", "muted", false))
	for cue in ["click", "scan", "jump", "signal", "supply", "trade", "warning", "step"]:
		_streams[cue] = load("res://audio/%s.wav" % cue)
	for i in 6:
		var player := AudioStreamPlayer.new()
		player.volume_db = -10.0
		add_child(player)
		_players.append(player)
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = load("res://audio/ambience.wav")
	_ambience.volume_db = -14.0
	add_child(_ambience)
	_ambience.finished.connect(func():
		if not muted:
			_ambience.play())
	if not muted and DisplayServer.get_name() != "headless":
		_ambience.play()


func play(cue: String) -> void:
	if muted or DisplayServer.get_name() == "headless" or not _streams.has(cue) or _players.is_empty():
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _streams[cue]
	player.play()


func set_muted(value: bool, save := true) -> void:
	muted = value
	settings_changed.emit()
	if muted:
		_ambience.stop()
		for player in _players:
			player.stop()
	elif not _ambience.playing and DisplayServer.get_name() != "headless":
		_ambience.play()
	if save:
		var cfg := ConfigFile.new()
		cfg.load(T.SETTINGS_PATH)
		cfg.set_value("audio", "muted", muted)
		cfg.save(T.SETTINGS_PATH)
