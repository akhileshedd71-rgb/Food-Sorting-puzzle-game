class_name GameAudio
extends Node
## Small pooled original effects plus a quiet, independently controlled loop.

const CUE_NAMES := ["select", "move", "invalid", "match", "reveal", "serve", "win", "click"]
const EFFECT_POOL_SIZE := 6

var _sound_enabled: bool = true
var _music_enabled: bool = true
var _music_active: bool = true
var _music: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _cues: Dictionary = {}
var _next_voice: int = 0
# A headless server has no output device; keep its tests free of audio voices.
var _audio_available: bool = DisplayServer.get_name() != "headless"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for cue in CUE_NAMES:
		_cues[cue] = load("res://assets/audio/" + cue + ".wav")
	for index in range(EFFECT_POOL_SIZE):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -5.0
		add_child(voice)
		_voices.append(voice)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -15.0
	var stream := load("res://assets/audio/garden_afternoon.wav") as AudioStreamWAV
	if stream != null:
		stream = stream.duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
		_music.stream = stream
	add_child(_music)
	_update_music()

func configure(settings: Dictionary) -> void:
	_sound_enabled = bool(settings.get("sound", true))
	_music_enabled = bool(settings.get("music", true))
	if not _sound_enabled:
		for voice in _voices:
			voice.stop()
	_update_music()

func play_cue(cue_name: String) -> void:
	if not _audio_available or not _sound_enabled or _voices.is_empty() or not _cues.has(cue_name):
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = _cues[cue_name]
	voice.play()

func set_music_active(active: bool) -> void:
	_music_active = active
	_update_music()

func _update_music() -> void:
	if not is_instance_valid(_music) or _music.stream == null:
		return
	if _music_enabled and _music_active:
		if _audio_available and not _music.playing:
			_music.play()
		_music.stream_paused = false
	else:
		_music.stream_paused = true

func _exit_tree() -> void:
	for voice in _voices:
		voice.stop()
	if is_instance_valid(_music):
		_music.stop()
