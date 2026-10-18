extends Node

# ONE MORE TIME (ASIMO AFET) fragmanı (60 sn). Tek merkezi zaman çizelgesi: _cue(t, işlev)
# kayıtları saniye sırasıyla _process içinde tetiklenir; hareketler ve geçişler Tween ile yumuşar.
# Görüntüler gerçek oyundur: main.tscn fragman hikâyesiyle (TrailerStory) örneklenir, oyuncu girdisi
# kapalıdır, olaylar buradan tetiklenir. Zaman döngüsü için ikinci döngü, oyunun yepyeni bir örneğidir
# (ev başlangıç hâlinde); üçlü karar bölümünde üç örnek SubViewport'larda aynı anda oynar.
# Karısı ekranda görünmez; sesi yalnız telefondan gelir. Fragman bitince kapanır ("loop" argümanıyla
# başa döner); R ile yeniden başlar. Sahneler oynarken sol alt köşede küçük açıklamalar görünür.

const MainScene = preload("res://main.tscn")
const StoryScript = preload("res://scripts/story.gd")
const TrailerStory = preload("res://trailer/scripts/trailer_story.gd")
const TrailerCamera = preload("res://trailer/scripts/trailer_camera.gd")
const TrailerAudio = preload("res://trailer/scripts/trailer_audio.gd")
const TrailerTransitions = preload("res://trailer/scripts/trailer_transitions.gd")
const TitlesScene = preload("res://trailer/ui/trailer_titles.tscn")
const Actors = preload("res://trailer/scripts/trailer_actors.gd")
# Zaman çizelgesi 82.5 sn'lik ana kurguya göre yazılıdır. 60 sn'ye indirmek için önce boş/yinelenen
# anlar çıkarılır (CUTS: o aralıktaki kayıtlar atılır, sonrakiler öne kayar), kalan kurgu ise bütün
# bölümlerde aynı oranda hızlandırılır (Engine.time_scale): bölümlerin birbirine oranı değişmez.
const FULL_LENGTH := 82.5
# [başlangıç, bitiş] (ana kurgu, artçı kaydırması sonrası mutlak saniye):
# açılıştaki fazla siyah, 2. bölümde tekrar eden TV uyarısı, son bölümde tekrar eden geri sarma saati.
const CUTS := [[0.4, 1.4], [59.38, 60.4], [65.8, 66.8]]
# Logodan sonraki fazla siyah.
const TAIL_TRIM := 0.9
const TARGET_LENGTH := 60.0
var DURATION := FULL_LENGTH - TAIL_TRIM
# Artçı sarsıntı sahnesi (Osman'la yatak odasından çıkış, kapıya düşen enkaz, soyulmuş duvarlar)
# 61.4'e eklenir; o andan sonraki bütün kayıtlar AFTERSHOCK_LEN kadar kayar.
const AFTERSHOCK_AT := 61.4
const AFTERSHOCK_LEN := 3.2
const W := "Karım (telefonda)"

var audio: Node
var fx: CanvasLayer
var titles: CanvasLayer
var game: Node2D
var cam: Camera2D
var old_game: Node2D
var old_cam: Camera2D
var next_game: Node2D
var next_cam: Camera2D
var next_cast: Array = []
var clock := -1.0
var cues: Array = []
var next_cue := 0
var finished := false
var cat_actor: Node2D
var tv_noise: Node2D
var split_layer: CanvasLayer
var splits: Array = []
var split_shades: Array = []
var rubble: CanvasLayer
var rubble_zoom := 1.6


func _ready() -> void:
	for c in CUTS:
		DURATION -= c[1] - c[0]
	# Kalan kurgu her yerde aynı oranda hızlanır: oyun saatinde DURATION, videoda TARGET_LENGTH sn.
	Engine.time_scale = DURATION / TARGET_LENGTH
	# Fragman her zaman ilk döngüden, başlık ve eğitim olmadan başlar (yalnız bu süreçte geçerli).
	Engine.set_meta(&"asimo_story_loop", 0)
	Engine.set_meta(&"asimo_tutorial_done", true)
	Engine.set_meta(&"asimo_title_shown", true)
	Engine.set_meta(&"asimo_learned", {})
	Engine.set_meta(&"asimo_last_death", "")
	audio = TrailerAudio.new()
	add_child(audio)
	fx = TrailerTransitions.new()
	add_child(fx)
	titles = TitlesScene.instantiate()
	titles.audio = audio
	add_child(titles)
	game = _spawn_game(self)
	# Oyunun ertelenmiş kurulumları (yangın alanı, deprem güvenliği) bir kare sonra hazır olur.
	await get_tree().process_frame
	await get_tree().process_frame
	cam = _prepare(game)
	var cast := _setup_cast(game, cam)
	cat_actor = cast[0]
	tv_noise = cast[1]
	_build_timeline()
	clock = 0.0


func _spawn_game(parent: Node) -> Node2D:
	var g: Node2D = MainScene.instantiate()
	g.story_script = TrailerStory
	parent.add_child(g)
	return g


# Oyun arayüzü gizlenir, oyuncu yönetmene geçer; ana oyunun düzeni değişmez.
func _prepare(g: Node2D) -> Camera2D:
	g.get_node("HUD").visible = false
	g.objects.inventory_ui.visible = false
	g.transitioning = true
	g.player.input_locked = true
	g.player.invulnerable = true
	g.story.has_tool = true
	g.quake.music.volume_db = -80.0
	_route_audio(g, "AMBIENCE")
	for c in g.story.get_children():
		if c.get_script() == StoryScript.TaskPath:
			c.process_mode = Node.PROCESS_MODE_DISABLED
			c.visible = false
	for c in g.story.overlay.get_children():
		if c.get_script() == StoryScript.HazardSign or c == g.story.guide or c == g.story.mind:
			c.process_mode = Node.PROCESS_MODE_DISABLED
			c.visible = false
	var c2 := TrailerCamera.new()
	g.add_child(c2)
	c2.setup(g)
	c2.make_current()
	return c2


# Oyun örneğinin kendi sesleri bir kanala; konuşma sesleri her zaman DIALOGUE'da kalır.
func _route_audio(g: Node2D, bus: String) -> void:
	for ap in g.find_children("*", "AudioStreamPlayer", true, false):
		ap.bus = bus
	g.story.blip_player.bus = "DIALOGUE"


func _item(g: Node2D, kind: String) -> Area2D:
	return g.objects.find_item(kind)


func _style(g: Node2D, style: String) -> Area2D:
	for it in g.objects.get_children():
		if it is Area2D and it.get("style") == style:
			return it
	return null


func _door(g: Node2D, from: StringName, to: StringName) -> Vector2:
	for row in g.DOOR_TRANSITIONS:
		if row[0] == from and row[1] == to:
			return row[2]
	return g.ROOM_CENTERS[from]


# Başlangıç noktası: telefon masasının önü (iki döngüde de aynı). Osman masanın yanında oturur.
func _setup_cast(g: Node2D, c: Camera2D) -> Array:
	var phone: Area2D = g.story.phone
	var p: Node2D = g.player
	p.global_position = phone.global_position + Vector2(104, 4)
	p.facing = Vector2.LEFT
	var cat := Actors.Cat.new()
	g.add_child(cat)
	cat.global_position = phone.global_position + Vector2(150, 12)
	var tv := _item(g, "tv")
	var noise := Actors.TvNoise.new()
	noise.area = Rect2(Vector2(-tv.size.x / 2.0, -tv.size.y) + tv.draw_offset, tv.size).grow(-7)
	tv.add_child(noise)
	c.cut_to(&"salon", phone.global_position + Vector2(70, -20), 1.25)
	return [cat, noise]


func _cue(t: float, f: Callable) -> void:
	_add_cue(t + (AFTERSHOCK_LEN if t >= AFTERSHOCK_AT else 0.0), f)


# Kesilen aralıktaki kayıt atılır; sonrakiler kesilen süre kadar öne alınır.
func _add_cue(t: float, f: Callable) -> void:
	var shift := 0.0
	for c in CUTS:
		if t >= c[0] and t < c[1]:
			return
		if t >= c[1]:
			shift += c[1] - c[0]
	cues.append([t - shift, f])


# Kaydırmasız (mutlak zamanlı) kayıt: yalnız artçı sarsıntı sahnesi kullanır.
func _cue_at(t: float, f: Callable) -> void:
	_add_cue(t, f)


func _caption(t: float, head: String, text: String, seconds: float) -> void:
	_cue(t, func(): titles.caption(head, text, seconds))


func _process(delta: float) -> void:
	if clock < 0.0 or finished:
		return
	clock += delta
	while next_cue < cues.size() and cues[next_cue][0] <= clock:
		cues[next_cue][1].call()
		next_cue += 1
	audio.update(delta)
	if rubble != null and is_instance_valid(rubble):
		rubble.time += delta
		var k: float = rubble._k()
		var view: Vector2 = rubble.canvas.size
		var pocket: Vector2 = Vector2(178, 178) * k + Vector2(0, (view.y - rubble.PX.y * k) * 0.5)
		rubble.scale = Vector2.ONE * rubble_zoom
		rubble.offset = view * 0.5 - pocket * rubble_zoom
		rubble.canvas.queue_redraw()
	if clock >= DURATION:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		get_tree().reload_current_scene()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _finish() -> void:
	finished = true
	if "loop" in OS.get_cmdline_user_args():
		get_tree().reload_current_scene()
	else:
		get_tree().quit()


func _say(target: Node2D, text: String, seconds: float, speaker := "") -> void:
	game.story.show_bubble(target, text, false, speaker, seconds)


func _phone_say(text: String, seconds: float) -> void:
	game.story.show_bubble(game.story.phone, text, false, W, seconds)


func _ring(on: bool) -> void:
	var phone: Area2D = game.story.phone
	phone.ringing = on
	phone.queue_redraw()
	if on:
		audio.sfx("ring", -6.0)


func _walk(p: Node2D, to: Vector2, seconds: float) -> void:
	p.facing = (to - p.global_position).normalized()
	p.scripted_walk = true
	var tw := p.create_tween()
	tw.tween_property(p, "global_position", to, seconds)
	tw.tween_callback(func(): p.scripted_walk = false)


func _lights(g: Node2D, on: bool) -> void:
	if on:
		g.lights_out = false
		g.pitch_dark = false
		for it in g.objects.get_children():
			if it is Area2D and not it.lamp_lights.is_empty():
				it.set_light(true)
		g.apply_ambient()
	else:
		g.story._blackout()


# Kısa döngü işareti: siyah ekranda bir anlık "00:00".
func _loop_flash(at: float) -> void:
	_cue(at, func():
		fx.black = 1.0
		titles.flash_title("00:00", 0.18, 54))
	_cue(at + 0.2, func(): fx.black = 0.0)


func _build_timeline() -> void:
	_part1()
	_part2()
	_part3()
	_part4()
	_part5()
	_part6()
	_aftershock()
	_captions()
	cues.sort_custom(func(a, b): return a[0] < b[0])


# --- 1. Sıradan bir gece (0-10.6): telefon, karısının sesi, Osman -------------------------

func _part1() -> void:
	_cue(0.0, func(): audio.set_ticking(true))
	_cue(1.4, func():
		fx.fade_in(1.8)
		cam.zoom_to(1.45, 9.0))
	_cue(2.3, func(): audio.play_music("calm", 2.0, -2.0))
	_cue(2.8, func(): _ring(true))
	_cue(4.2, func():
		_ring(false)
		audio.set_duck(true)
		game.player.facing = Vector2.LEFT)
	_cue(4.4, func(): _phone_say("Osman'ın mamasını verdin mi?", 2.4))
	_cue(7.0, func(): _say(game.player, "Verdim, merak etme.", 1.9))
	_cue(9.0, func():
		game.player.facing = Vector2.RIGHT
		_say(game.player, "Her şey yolunda.", 1.7))
	_cue(9.6, func(): audio.sfx("meow2", -8.0))


# --- 2. İlk sarsıntı (10.6-19.3): döngünün ilk sonu, grafik şiddet yok --------------------

func _part2() -> void:
	_cue(10.6, func():
		var tv := _item(game, "tv")
		audio.set_duck(false)
		cam.focus_on_target(tv.global_position + Vector2(0, -70), 1.6, 1.4)
		game.player.facing = Vector2.UP)
	_cue(11.3, func():
		audio.sfx("static", -6.0)
		create_tween().tween_property(tv_noise, "strength", 1.0, 0.5))
	_cue(11.9, func():
		_item(game, "tv").set_alarm(true)
		create_tween().tween_property(tv_noise, "strength", 0.0, 0.6))
	_cue(12.1, func(): audio.set_ticking(false))
	_cue(12.4, func(): cam.focus_on_target(game.story.phone.global_position + Vector2(70, -20), 1.25, 0.8))
	_cue(12.7, func():
		audio.set_duck(true)
		_say(game.player, "Bu da ne?", 1.2))
	_cue(13.2, func():
		_item(game, "floor_lamp").flicker(6.0)
		var rt := _style(game, "round_table")
		if rt != null:
			rt.flicker(6.0)
		audio.sfx("rumble", -3.0, 1.0, "SFX", 4.5)
		audio.play_music("tension", 0.6, -1.0))
	_cue(13.7, func():
		game.quake._on_tick()
		cam.shake(7.0, 3.0)
		audio.sfx("crash", -7.0))
	_cue(14.6, func():
		game.player.facing = Vector2.LEFT
		_say(game.player, "Hayatım?!", 1.3))
	_cue(15.8, func(): _phone_say("Buradayım!", 1.2))
	_cue(16.4, func():
		audio.sfx("meow", -2.0)
		cat_actor.run_to(_door(game, &"salon", &"yatak_odasi") + Vector2(40, 0), 1.2))
	_cue(16.8, func():
		game.quake._on_tick()
		cam.shake(10.0, 2.0)
		audio.sfx("crash", -4.0, 0.8))
	_cue(17.6, func(): fx.fade_out(0.45))
	_cue(18.05, func():
		_lights(game, false)
		tv_noise.strength = 0.0
		audio.stop_music(0.0)
		audio.set_duck(false)
		# Döngünün sonu: bütün sesler kesilir, yalnız karakterin sesi kalır.
		_route_audio(game, audio.SILENT_BUS)
		titles.say("Hayır! İkiniz de...", "man", 1.0))


# --- 3. Zaman döngüsü (19.3-37.3): saat geri sarar, ev başa döner, adam hatırlar ----------

func _part3() -> void:
	# Duvar saati: tik tak, akrep ve yelkovan hızla geri döner. Yeni döngünün evi arkada hazırlanır.
	_cue(19.4, func():
		var rc = game.story.RewindClock.new()
		rc.name = "trailer_clock"
		rc.deaths = 2
		game.story.add_child(rc)
		rc.tick_player.volume_db = -80.0
		rc.chime_player.volume_db = -80.0
		fx.fade_in(0.3)
		audio.set_ticking(true)
		_spawn_next_loop())
	# Ters sırayla kısa görüntüler (geri sarma efektiyle).
	_cue(21.2, func():
		var rc: Node = game.story.get_node_or_null("trailer_clock")
		if rc != null:
			rc.queue_free()
		fx.set_rewind(true)
		fx.quick_cut()
		game.lights_out = false
		game.apply_ambient()
		var far: Area2D = null
		for it in game.objects.get_children():
			if it is Area2D and it.kind == "wardrobe" and it.room == &"yatak_odasi":
				it.wobbling = true
				far = it
		cam.cut_to(&"yatak_odasi", far.global_position + Vector2(-60, -40), 1.4)
		cam.shake(5.0, 0.6))
	_cue(21.85, func():
		fx.quick_cut()
		for it in game.objects.get_children():
			if it is Area2D and it.kind == "wardrobe":
				it.wobbling = false
		var tv := _item(game, "tv")
		game.lights_out = false
		game.apply_ambient()
		tv.set_alarm(true)
		cam.cut_to(&"salon", tv.global_position + Vector2(0, -70), 1.9))
	_cue(22.2, func():
		_item(game, "tv").set_alarm(false)
		tv_noise.strength = 0.8
		create_tween().tween_property(tv_noise, "strength", 0.0, 0.3))
	_cue(22.5, func():
		fx.quick_cut()
		game.lights_out = true
		game.apply_ambient()
		cam.cut_to(&"salon", _item(game, "floor_lamp"), 1.6))
	_cue(22.75, func():
		_lights(game, true)
		_item(game, "floor_lamp").flicker(0.4))
	# Ev başlangıç hâline döner: yeni döngü örneği öne geçer, eskisi silinir.
	_cue(23.15, func():
		fx.quick_cut()
		old_game = game
		old_cam = cam
		game = next_game
		cam = next_cam
		cat_actor = next_cast[0]
		tv_noise = next_cast[1]
		game.visible = true
		old_game.visible = false
		cam.cut_to(&"salon", _item(game, "coffee_table"), 1.0)
		cam.make_current()
		old_game.queue_free())
	_cue(23.8, func():
		fx.set_rewind(false)
		fx.black = 1.0
		var rc = game.story.RewindClock.new()
		rc.name = "trailer_clock"
		rc.deaths = 2
		game.story.add_child(rc)
		rc.time = 2.3
		rc.tick_player.volume_db = -80.0
		rc.chime_player.volume_db = -80.0
		fx.fade_in(0.15)
		titles.show_title("00:00", 0.2, 1.0, 0.2, 54, 0.16))
	_cue(25.1, func():
		var rc: Node = game.story.get_node_or_null("trailer_clock")
		if rc != null:
			rc.queue_free()
		fx.black = 1.0
		audio.set_ticking(false))
	# Bir an sessizlik; aynı başlangıç noktasında gözlerini açar.
	_cue(25.4, func():
		cam.cut_to(&"salon", game.player, 1.6)
		fx.eyes_open(1.0))
	_cue(25.9, func():
		audio.set_duck(true)
		_say(game.player, "Ne...?", 0.9))
	_cue(26.5, func(): game.player.facing = Vector2.LEFT)
	_cue(26.85, func(): game.player.facing = Vector2.RIGHT)
	_cue(27.2, func(): game.player.facing = Vector2.DOWN)
	_cue(27.4, func():
		cam.focus_on_target(game.story.phone.global_position + Vector2(70, -20), 1.35, 1.2)
		_say(game.player, "Yine aynı gece...", 1.5))
	# Hatırlama: karısı aynı cümleyi tekrar eder, o hatırlamaz; adam hatırlar.
	_cue(28.9, func(): _ring(true))
	_cue(29.8, func():
		_ring(false)
		audio.play_music("calm", 0.8, -9.0)
		game.player.facing = Vector2.LEFT
		_phone_say("Osman'ın mamasını verdin mi?", 2.0))
	_cue(31.8, func(): _say(game.player, "Sen... Bunu daha önce söyledin.", 1.7))
	_cue(33.5, func(): _phone_say("Ne?", 0.7))
	_cue(34.2, func(): _say(game.player, "Birazdan deprem olacak.", 1.3))
	_cue(35.5, func():
		var tv := _item(game, "tv")
		game.player.facing = (tv.global_position - game.player.global_position).normalized()
		_say(game.player, "Bu sefer ne olacağını biliyorum.", 1.8)
		cam.zoom_to(1.9, 1.8))


# Yeni döngünün evi (başlangıç durumu): görünmez hazırlanır, sırası gelince öne geçer.
func _spawn_next_loop() -> void:
	next_game = _spawn_game(self)
	next_game.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	next_cam = _prepare(next_game)
	next_cast = _setup_cast(next_game, next_cam)
	# Eski döngü geri sarma görüntülerinde hâlâ ekranda: onun kamerası öne geri alınır.
	cam.make_current()


# --- 4. Hatırlıyorsun (37.3-57): yazılar, farklı döngüler, üçlü karar ----------------------

func _part4() -> void:
	_cue(37.3, func():
		fx.black = 1.0
		audio.set_duck(false)
		audio.play_music("loop", 0.05, -1.0)
		cat_actor.visible = false
		_route_audio(game, audio.SILENT_BUS)
		game.quake._on_tick())
	_cue(37.4, func(): titles.show_title("AYNI GECE.", 0.3, 0.7, 0.3, 64))
	_cue(38.8, func(): titles.show_title("AYNI FELAKET.", 0.3, 0.7, 0.3, 64))
	_cue(40.2, func(): titles.show_title("AMA ARTIK HATIRLIYORSUN.", 0.35, 0.9, 0.3, 64))
	var p := func() -> Node2D: return game.player
	# Döngü 1: dolap tehlikesi.
	_loop_flash(41.9)
	_cue(42.1, func():
		var pl: Node2D = p.call()
		var far: Area2D = null
		for it in game.objects.get_children():
			if it is Area2D and it.kind == "wardrobe" and it.room == &"yatak_odasi" and not it.trap:
				far = it
		pl.global_position = far.global_position + Vector2(0, 70)
		pl.facing = Vector2.UP
		far.wobbling = true
		cam.cut_to(&"yatak_odasi", far.global_position + Vector2(0, -20), 1.45)
		audio.sfx("creak", -2.0))
	_cue(42.6, func():
		var pl: Node2D = p.call()
		for it in game.objects.get_children():
			if it is Area2D and it.kind == "wardrobe" and it.room == &"yatak_odasi" and not it.trap:
				it.topple(false)
		audio.sfx("crash", -5.0)
		cam.shake(6.0, 0.6)
		_walk(pl, pl.global_position + Vector2(0, 70), 0.4))
	# Döngü 2: matkap ve vidalar, dolap önceden duvara.
	_loop_flash(43.25)
	_cue(43.45, func():
		var pl: Node2D = p.call()
		var wr: Area2D = null
		for it in game.story._trap_wardrobes():
			wr = it
		game.objects.add_item("drill")
		game.objects.add_item("nails", 2)
		if game.objects.equipped != "drill":
			game.objects.equip("drill", true)
		pl.global_position = wr.global_position + Vector2(10, 64)
		pl.facing = Vector2.UP
		wr.anchored = true
		wr.screws_shown = 0
		cam.cut_to(&"yatak_odasi", wr.global_position + Vector2(10, -10), 1.55)
		audio.sfx("drill", -4.0)
		create_tween().tween_method(func(v: float):
			wr.screws_shown = int(v)
			wr.queue_redraw(), 0.0, 4.99, 0.9))
	# Döngü 3: elektrikli suyu hatırlar, sigorta kutusuna yönelir.
	_loop_flash(44.6)
	_cue(44.8, func():
		var pl: Node2D = p.call()
		_lights(game, false)
		var pud: Area2D = game.story.puddle
		pud.flood = 1.0
		pud.outlet_tear = 1.0
		game.objects.add_item("flashlight")
		if game.objects.equipped != "flashlight":
			game.objects.equip("flashlight", true)
		if game.story.torch == null:
			game.story._enable_torch()
		pl.global_position = pud.global_position + Vector2(110, 20)
		pl.facing = Vector2.LEFT
		cam.cut_to(&"banyo", pud.global_position + Vector2(40, -30), 1.3)
		audio.sfx("zap", -4.0))
	_cue(45.35, func():
		fx.quick_cut()
		var pl: Node2D = p.call()
		var box := _item(game, "electrical_box")
		pl.global_position = box.global_position + Vector2(-170, 160)
		cam.cut_to(&"salon", box.global_position + Vector2(-40, 10), 1.45)
		_walk(pl, box.global_position + Vector2(-60, 110), 0.6))
	# Döngü 4: deprem çantası hazırlanır.
	_loop_flash(45.95)
	_cue(46.15, func():
		var inv = game.objects.inventory_ui
		var view := get_viewport().get_visible_rect().size
		inv.scale = Vector2.ONE * 1.7
		inv.offset = view * 0.5 - Vector2(12.0 + 316.0, 10.0 + 105.0) * 1.7
		var dim := CanvasLayer.new()
		dim.name = "trailer_dim"
		dim.layer = 25
		var cr := ColorRect.new()
		cr.color = Color(0, 0, 0, 0.6)
		cr.size = view
		dim.add_child(cr)
		add_child(dim)
		inv.visible = true
		inv.open = true
		game.objects.add_item("quake_bag")
		inv.cursor = game.objects.slot_order.find("quake_bag")
		audio.sfx("zipper", -2.0))
	for k in 4:
		var kind: String = ["food", "water_bottle", "whistle", "bandage"][k]
		_cue(46.4 + k * 0.2, func():
			game.objects.add_item(kind)
			audio.sfx("cloth", -6.0, 1.0 + k * 0.08))
	# Döngü 5: Osman'ı çağırır (yatak altı görünümü).
	_loop_flash(47.3)
	_cue(47.5, func():
		var inv = game.objects.inventory_ui
		inv.open = false
		inv.anim = 0.0
		inv.visible = false
		inv.scale = Vector2.ONE
		inv.offset = Vector2.ZERO
		var dim := get_node_or_null("trailer_dim")
		if dim != null:
			dim.queue_free()
		var ub = game.story.UnderBedView.new()
		ub.name = "trailer_underbed"
		game.story.add_child(ub)
		ub.appear = 1.0
		ub.reveal = 1.0
		ub.cat_forward = 0.15
		ub.say("Pisi pisi! Gel Osman...")
		audio.sfx("meow2", -4.0)
		create_tween().tween_property(ub, "cat_forward", 0.5, 1.1))
	_cue(47.0, func(): _build_splits())
	# Üçlü karar: elektrikli sudan kaçmak, Osman'a koşmak, çantayı almak.
	_cue(48.65, func():
		var ub: Node = game.story.get_node_or_null("trailer_underbed")
		if ub != null:
			ub.queue_free()
		game.visible = false
		split_layer.visible = true
		fx.black = 1.0
		fx.fade_in(0.4)
		audio.play_music("choices", 0.2, 1.0)
		for s in splits:
			s.game.quake._on_tick()
			s.cam.shake(5.0, 2.0))
	_cue(48.9, func():
		var a: Dictionary = splits[0]
		_walk(a.game.player, a.puddle.global_position + Vector2(78, 10), 1.8)
		var b: Dictionary = splits[1]
		var cat := _item(b.game, "cat")
		_walk(b.game.player, cat.global_position + Vector2(96, 18), 1.7)
		var c: Dictionary = splits[2]
		_walk(c.game.player, c.wardrobe.global_position + Vector2(10, 70), 1.9))
	_cue(50.6, func():
		var a: Dictionary = splits[0]
		a.game.player.facing = Vector2.LEFT
		audio.sfx("zap", -8.0)
		a.cam.shake(4.0, 0.5))
	_cue(50.7, func():
		var b: Dictionary = splits[1]
		b.game.player.facing = Vector2.LEFT
		b.game.player.scripted_walk = false
		b.game.player.crouching = true
		var cat := _item(b.game, "cat")
		b.cam.focus_on_target(cat.global_position + Vector2(60, -20), 1.45, 2.2)
		create_tween().tween_property(cat, "approach", 0.65, 2.0))
	_cue(50.9, func():
		var c: Dictionary = splits[2]
		c.game.player.facing = Vector2.UP
		c.wardrobe.toggle_open()
		audio.sfx("squeak", -8.0))
	_cue(51.6, func():
		var a: Dictionary = splits[0]
		_walk(a.game.player, a.puddle.global_position + Vector2(150, 10), 1.1)
		var c: Dictionary = splits[2]
		c.wardrobe.holds_bag = false
		c.game.player.carry_bag = true
		audio.sfx("zipper", -8.0))
	_cue(52.2, func():
		var c: Dictionary = splits[2]
		_walk(c.game.player, c.wardrobe.global_position + Vector2(70, 100), 1.2)
		c.cam.zoom_to(1.4, 1.8))
	_cue(52.6, func(): audio.sfx("meow", -6.0))
	for i in 3:
		_cue(53.4 + i * 0.4, func():
			create_tween().tween_property(split_shades[i], "color:a", 1.0, 0.4))
	_cue(54.6, func():
		fx.black = 1.0
		split_layer.visible = false
		for s in splits:
			s.vp.queue_free()
		splits.clear()
		game.visible = true)
	_cue(54.8, func(): titles.show_title("BU SEFER NEYİ DEĞİŞTİRECEKSİN?", 0.45, 1.2, 0.4, 60))


func _build_splits() -> void:
	var px: Vector2i = get_window().size
	var view := get_viewport().get_visible_rect().size
	split_layer = CanvasLayer.new()
	split_layer.layer = 70
	split_layer.visible = false
	add_child(split_layer)
	for i in 3:
		var vp := SubViewport.new()
		vp.size = Vector2i(px.x / 3, px.y)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		add_child(vp)
		var g := _spawn_game(vp)
		var rect := TextureRect.new()
		rect.texture = vp.get_texture()
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.position = Vector2(view.x / 3.0 * i, 0)
		rect.size = Vector2(view.x / 3.0, view.y)
		split_layer.add_child(rect)
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0)
		shade.position = rect.position
		shade.size = rect.size
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		split_layer.add_child(shade)
		split_shades.append(shade)
		splits.append({"vp": vp, "game": g})
	for i in 2:
		var line := ColorRect.new()
		line.color = Color(0.02, 0.02, 0.02)
		line.position = Vector2(view.x / 3.0 * (i + 1) - 2, 0)
		line.size = Vector2(4, view.y)
		split_layer.add_child(line)
	_setup_splits.call_deferred()


func _setup_splits() -> void:
	await get_tree().process_frame
	for i in splits.size():
		var s: Dictionary = splits[i]
		var g: Node2D = s.game
		s.cam = _prepare(g)
		_route_audio(g, audio.SILENT_BUS)
		var p: Node2D = g.player
		match i:
			0:
				# Sol: elektrikli suya doğru (karanlık banyo, kopmuş priz, kıvılcımlar; fener elde).
				var pud: Area2D = g.story.puddle
				pud.flood = 1.0
				pud.outlet_tear = 1.0
				g.lights_out = true
				p.global_position = g.ROOM_CENTERS[&"banyo"] + Vector2(70, 10)
				p.facing = Vector2.LEFT
				g.objects.add_item("flashlight")
				if g.objects.equipped != "flashlight":
					g.objects.equip("flashlight", true)
				g.story._enable_torch()
				s.puddle = pud
				s.cam.cut_to(&"banyo", pud.global_position + Vector2(70, -20), 1.15)
				g.apply_ambient()
			1:
				# Orta: Osman'a doğru (yangın arkada).
				g.quake._on_tick()
				g.story.fire_field.age = 9.0
				var cat := _item(g, "cat")
				p.global_position = cat.global_position + Vector2(230, 60)
				s.cam.cut_to(&"yatak_odasi", cat.global_position + Vector2(110, -20), 1.1)
			2:
				# Sağ: deprem çantası (dolabın içinde).
				g.quake._on_tick()
				g.story.fire_field.age = 9.0
				var wr: Area2D = null
				for it in g.story._trap_wardrobes():
					if it.holds_bag:
						wr = it
				s.wardrobe = wr
				p.global_position = wr.global_position + Vector2(150, 120)
				s.cam.cut_to(&"yatak_odasi", wr.global_position + Vector2(40, 10), 1.25)


# --- 5. Son umut (57-71.4, artçı sarsıntı dahil) ---------------------------------------------------------------

func _part5() -> void:
	var p := func() -> Node2D: return game.player
	_cue(57.0, func():
		var pl: Node2D = p.call()
		audio.play_music("emotional", 0.2, 7.0)
		fx.fade_in(0.3)
		var cat := _item(game, "cat")
		pl.global_position = cat.global_position + Vector2(96, 18)
		pl.facing = Vector2.LEFT
		pl.crouching = true
		game.objects.equip("", true)
		cam.cut_to(&"yatak_odasi", cat.global_position + Vector2(60, -24), 1.75)
		cam.zoom_to(1.95, 1.2)
		create_tween().tween_property(cat, "approach", 0.75, 1.1))
	# Yangın tüpüyle söndürme: oyunun gerçek püskürtme mekaniği (E basılı tutuluyormuş gibi).
	_cue(58.2, func():
		fx.quick_cut()
		var pl: Node2D = p.call()
		pl.crouching = false
		var ff = game.story.fire_field
		var flame: Vector2 = ff.nearest_burning(game.ROOM_CENTERS[&"yatak_odasi"])
		pl.global_position = flame + Vector2(-110, 12)
		pl.facing = Vector2.RIGHT
		game.objects.add_item("fire_extinguisher")
		if game.objects.equipped != "fire_extinguisher":
			game.objects.equip("fire_extinguisher", true)
		cam.cut_to(&"yatak_odasi", flame + Vector2(-50, -30), 1.6)
		pl.input_locked = false
		Input.action_press("interact"))
	_cue(59.35, func():
		Input.action_release("interact")
		var pl: Node2D = p.call()
		pl.input_locked = true)
	# Televizyondaki uyarı.
	_cue(59.4, func():
		fx.quick_cut()
		var tv := _item(game, "tv")
		game.lights_out = false
		game.apply_ambient()
		tv.set_alarm(true)
		cam.cut_to(&"salon", tv.global_position + Vector2(0, -70), 2.1)
		audio.sfx("static", -14.0))
	# Sarsılan dolaplar.
	_cue(60.4, func():
		fx.quick_cut()
		game.lights_out = true
		game.apply_ambient()
		var wr: Area2D = null
		for it in game.objects.get_children():
			if it is Area2D and it.kind == "wardrobe" and it.room == &"yatak_odasi" and not it.fallen:
				it.wobbling = true
				wr = it
		cam.cut_to(&"yatak_odasi", wr.global_position + Vector2(-20, -50), 1.6)
		cam.shake(6.0, 1.0)
		audio.sfx("creak", -2.0, 0.9))
	# Fener karanlığı aydınlatıyor.
	_cue(61.4, func():
		fx.quick_cut()
		for it in game.objects.get_children():
			if it is Area2D and it.kind == "wardrobe":
				it.wobbling = false
		var pl: Node2D = p.call()
		var bath: Vector2 = game.ROOM_CENTERS[&"banyo"]
		pl.global_position = bath + Vector2(40, 40)
		pl.facing = Vector2.LEFT
		game.objects.equip("flashlight", true)
		game.pitch_dark = true
		cam.cut_to(&"banyo", pl, 1.0)
		game.apply_ambient()
		audio.sfx("click", -4.0))
	_cue(61.9, func(): game.player.facing = Vector2(-0.7, -0.7).normalized())
	_cue(62.3, func(): game.player.facing = Vector2.UP)
	# Analog saat.
	_cue(62.6, func():
		fx.quick_cut()
		var rc = game.story.RewindClock.new()
		rc.name = "trailer_clock2"
		rc.deaths = 3
		game.story.add_child(rc)
		rc.time = 0.6
		rc.tick_player.volume_db = -80.0
		rc.chime_player.volume_db = -80.0)
	# Enkazda küçük bir ışık.
	_cue(63.6, func():
		fx.quick_cut()
		var rc: Node = game.story.get_node_or_null("trailer_clock2")
		if rc != null:
			rc.queue_free()
		rubble = game.story.RubbleEnding.new()
		rubble.story = game.story
		rubble.items = {"flashlight": true, "whistle": true, "food": true, "water_bottle": true, "bandage": true}
		game.story.add_child(rubble)
		rubble.process_mode = Node.PROCESS_MODE_DISABLED
		rubble.rubble_ambience.stop()
		rubble.fade = 0.0
		rubble.light = 0.06
		rubble.torch_on = true
		rubble.torch_k = 1.0
		rubble_zoom = 1.6
		create_tween().tween_property(self, "rubble_zoom", 2.1, 2.4).set_trans(Tween.TRANS_SINE))
	# Düdüğü eline alır.
	_cue(64.9, func():
		var tw := create_tween()
		tw.tween_property(rubble, "whistle_pose", 1.0, 0.6).set_trans(Tween.TRANS_SINE))
	_cue(65.45, func(): audio.sfx("whistle", -6.0, 1.0, "SFX", 0.55))
	_cue(66.1, func():
		audio.stop_music(0.0)
		game.process_mode = Node.PROCESS_MODE_DISABLED
		create_tween().tween_property(rubble, "torch_k", 0.35, 1.6))
	_cue(66.2, func():
		titles.say("Bu sefer farklı olacak...", "man", 1.5)
		fx.fade_out(2.0))
	_cue(68.2, func():
		if rubble != null and is_instance_valid(rubble):
			rubble.queue_free()
		rubble = null)


# --- 6. Final (71.4-82.5) ------------------------------------------------------------------

func _part6() -> void:
	_cue(68.8, func(): titles.show_title("HER KARARIN BİR SONUCU VAR.", 0.8, 0.9, 0.6))
	_cue(71.5, func(): titles.show_title("HER DÖNGÜ YENİ BİR ŞANS.", 0.8, 0.9, 0.6))
	_cue(74.6, func():
		titles.show_logo(1.2)
		audio.sfx("boom", -2.0))
	_cue(75.3, func(): titles.show_tagline(0.9))
	_cue(76.4, func(): titles.show_ready(0.8))
	_cue(77.2, func(): audio.tick_once())
	_cue(77.7, func(): titles.clear_all(0.7))


# --- Artçı sarsıntı (61.4-64.6): Osman'la yatak odasından çıkarken kapının önüne enkaz düşer --

func _aftershock() -> void:
	var a := AFTERSHOCK_AT
	var door := Vector2(650, 650.7)
	_cue_at(a, func():
		fx.quick_cut()
		for it in game.objects.get_children():
			if it is Area2D and it.kind == "wardrobe":
				it.wobbling = false
		var pl: Node2D = game.player
		pl.crouching = false
		game.objects.equip("", true)
		var cat := _item(game, "cat")
		if cat != null:
			cat.collect()
		pl.global_position = door
		pl.carry_cat = true
		game.story._spawn_osman_follower(door + Vector2(-34, 8))
		game.story.osman_follower.room = &"salon"
		game.lights_out = false
		game.pitch_dark = false
		cam.cut_to(&"salon", door + Vector2(120, -70), 1.5)
		game.apply_ambient()
		_walk(pl, door + Vector2(105, 4), 0.95))
	_cue_at(a + 0.2, func():
		game.story._aftershock_debris()
		cam.shake(8.0, 1.1)
		audio.sfx("rumble", -4.0, 1.1, "SFX", 1.4)
		audio.sfx("crash", -3.0, 0.85))
	_cue_at(a + 0.6, func(): audio.sfx("crash", -7.0, 1.15))
	_cue_at(a + 1.1, func(): game.player.facing = Vector2.LEFT)
	# Evin geri kalanı: mutfakta soyulmuş sıva, çatlaklar ve yığılmış enkaz.
	_cue_at(a + 1.8, func():
		fx.quick_cut()
		game.story.clear_bubble(game.player)
		var k: Rect2 = game.ROOMS[&"mutfak"]
		cam.cut_to(&"mutfak", k.position + Vector2(400, 40), 1.12)
		cam.move_to(k.position + Vector2(190, 50), 1.4)
		audio.sfx("creak", -8.0, 0.8))


# --- Köşe açıklamaları: sahne oynarken sol altta kısa bilgi (siyah ekran yazılarına ek) -------

func _captions() -> void:
	_caption(2.0, "BİR GECE", "Sıradan bir gece, sıradan bir telefon", 4.0)
	_caption(11.0, "UYARI", "Televizyonda deprem alarmı", 1.6)
	_caption(13.7, "DEPREM", "Ev sarsılmaya başladı", 3.5)
	_caption(21.25, "GERİ SARMA", "Zaman geriye akıyor", 1.8)
	_caption(25.7, "YENİ DÖNGÜ", "Aynı gece, aynı yer", 1.9)
	_caption(29.9, "HATIRLIYOR", "Her şey tekrar ediyor, ama o unutmadı", 3.4)
	_caption(35.5, "SÜRE", "30 sn sonra deprem · 70 sn içinde dışarı çık", 1.7)
	_caption(42.1, "DÖNGÜ 1", "Sabitlenmemiş dolap devrilir", 1.05)
	_caption(43.45, "DÖNGÜ 2", "Dolabı matkapla duvara sabitle", 1.05)
	_caption(44.8, "DÖNGÜ 3", "Su + kopmuş priz = elektrik çarpması", 0.5)
	_caption(45.35, "DÖNGÜ 3", "Önce sigortayı kapat", 0.55)
	_caption(46.15, "DÖNGÜ 4", "Deprem çantası: su, düdük, konserve, sargı bezi", 1.05)
	_caption(47.5, "DÖNGÜ 5", "Osman yatağın altında saklanıyor", 1.1)
	_cue(48.9, func(): titles.panel_labels(["SU VE ELEKTRİK", "OSMAN", "DEPREM ÇANTASI"], 4.4))
	_caption(57.1, "OSMAN", "Onu yanına al", 1.0)
	_caption(58.25, "YANGIN", "Yangın tüpüyle söndür", 1.05)
	_caption(59.45, "RESMÎ UYARI", "Televizyonu dinle", 0.9)
	_caption(60.45, "TEHLİKE", "Sabitlenmemiş dolaplar sallanıyor", 0.9)
	_cue_at(AFTERSHOCK_AT + 0.1, func(): titles.caption("ARTÇI SARSINTI", "Enkaz kapının önüne yığılıyor", 1.6))
	_cue_at(AFTERSHOCK_AT + 1.85, func(): titles.caption("HASAR", "Evin her yerinde duvarlar soyuldu", 1.3))
	_caption(61.45, "KARANLIK", "Elektrik kesik · kafa lambası şart", 1.1)
	_caption(62.65, "SÜRE", "Her saniye önemli", 0.9)
	_caption(63.65, "ENKAZ ALTINDA", "Düdükle yerini bildir", 2.4)
