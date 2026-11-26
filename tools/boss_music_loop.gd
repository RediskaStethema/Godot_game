extends SceneTree
# Музыка боя с главным боссом: самый энергичный кусок «Doom Incoming — Epic Boss Theme #2» бесшовной петлёй
# (решение пользователя 26.11.2026). Финальная кульминация трека — 95.0–125.0 с (12 тактов, такт 2.5 с, 96 BPM;
# громче и плотнее всего). Последние FADE с плавно переходят в то, что звучало перед началом куска, — стык без щелчка.
# Запуск (потом импорт — открыть редактор или `--headless --import`):
#   godot --headless --path . -s tools/boss_music_loop.gd
const SOURCE := "res://assets/sounds_for_gWHKINGS/Music/02 Doom Incoming _ Epic Boss Theme #2.mp3"
const OUT := "res://assets/audio/music/boss.wav"
const START := 95.015   # с — сразу перед сильной долей (95.023)
const LENGTH := 30.0    # с — ровно 12 тактов
const FADE := 0.02

func _init() -> void:
	var mp3 := AudioStreamMP3.new()
	mp3.data = FileAccess.get_file_as_bytes(SOURCE)
	if mp3.data.is_empty():
		push_error("нет исходника: " + SOURCE)
		quit(1)
		return
	var rate := int(AudioServer.get_mix_rate())
	var first := int(round(START * rate))
	var count := int(round(LENGTH * rate))
	var playback = mp3.instantiate_playback()
	playback.start(0.0)
	var frames := PackedVector2Array()
	while frames.size() < first + count:
		var chunk: PackedVector2Array = playback.mix_audio(1.0, 4096)
		if chunk.is_empty():
			break
		frames.append_array(chunk)
	if frames.size() < first + count:
		push_error("трек короче куска")
		quit(1)
		return
	var fade := int(FADE * rate)
	var pcm := PackedByteArray()
	pcm.resize(count * 4)
	for i in count:
		var v := frames[first + i]
		var tail := i - (count - fade)
		if tail >= 0:
			v = v.lerp(frames[first - fade + tail], float(tail + 1) / fade)
		pcm.encode_s16(i * 4, int(clampf(v.x, -1.0, 1.0) * 32767.0))
		pcm.encode_s16(i * 4 + 2, int(clampf(v.y, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = true
	wav.data = pcm
	var err := wav.save_to_wav(OUT)
	print("boss.wav: %.3f с, %d Гц, байт %d, ошибка %d" % [LENGTH, rate, pcm.size(), err])
	quit(1 if err != OK else 0)
