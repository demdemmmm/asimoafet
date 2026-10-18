extends CanvasLayer

# Enkaz bölümü: salon çöktükten sonra karanlık bir boşlukta Osman ile uyanış.
# Adımlar (hepsi oyuncu girdisiyle): çantayı aç (E) → ←/→ ile eşya seç (E) →
# sargı bezi: A/D sırayla basarak yaralı bacağı sar → konserve → su → E ile itip sürünmeye çalış →
# kurtarma ekibi "Kimse var mı?" → düdük: E basılı tut / hızlı bas, ses yükselir → kazı + makine
# sesleri, ekran yavaşça aydınlanır → kurtuluş. R: yeniden oyna.

const VoiceSynth = preload("res://scripts/voice_synth.gd")
const Sfx = preload("res://scripts/sfx.gd")
const CatSprite = preload("res://scripts/cat_sprite.gd")
const RUBBLE_AMBIENCE = preload("res://assets/rubble/horror_pulse.wav")
const PX := Vector2(360, 240)
const WRAPS_NEEDED := 10
# Sarılmamış yara: nabız 20'den saniyede bir düşer, 0'da kalp durur (20 sn).
const BLEED_TIME := 20.0
# Sarma kontrollü olsun: çok hızlı basışlar sayılmaz.
const WRAP_MIN_GAP := 0.16
const CRAWL_NEEDED := 8
const ITEMS := [
	{"id": "bandage", "name": "Sargı bezi", "tex": "res://assets/rubble/item_bandage.png"},
	{"id": "whistle", "name": "Düdük", "tex": "res://assets/rubble/item_whistle.png"},
	{"id": "food", "name": "Konserve", "tex": "res://assets/rubble/item_food.png"},
	{"id": "water", "name": "Su", "tex": "res://assets/rubble/item_water.png"},
]
# Dar boşluk: tavan döşemesi zemine çok yakın; adam yerde yatar, kedi yanında.
const FLOOR_Y := 200.0
const MAN_SCALE := 1.3
# Oyuncu karesinin dolu bölgesi (9,3)-(21,31): 90° dönünce gövde kalınlığı -5..+7 → zemine oturması için.
const MAN_POS := Vector2(150, FLOOR_Y - 7.0 * MAN_SCALE)
const CAT_POS := Vector2(196, FLOOR_Y)
const CAT_SCALE := 0.72
const POCKET := Vector2(180, 184)

signal chosen
signal step_done

var story: Node
# Çanta dolu değilse: kurtuluş yok, kan kaybından ölüm (döngü baştan).
var has_bag := true
# Evden gerçekten getirilen eşyalar (fener, düdük, konserve, su, sargı).
var items := {}
# Osman yanına alındıysa enkazda onunla; alınmadıysa kedi sesi/görseli yok.
var has_cat := true
# Daha önce de enkaza hazırlıksız gelindiyse kaçıncı kez (sinirli, tekrarsız replikler için).
var unprepared_repeat := 0
var shouting := false
var waiting_e := false
var picked := ""
# Düdük darbeleri: her üfleyiş enkazın içinden çatlağa doğru ilerleyen kesik bir dalga cephesi.
var pulses: Array = []
var motes: Array = []
var pulse_left := 0.0
var pulse_total := 1.0
var heart: AudioStreamPlayer
var rubble_ambience: AudioStreamPlayer
var consume_tween: Tween
# Uyarı çerçevesiz, yalnız metin olarak gösterilsin mi.
var prompt_plain := false
# Son ekran zamanlayıcısı: öğeler sırayla, yumuşakça belirir.
var end_t := -1.0
var beat_clock := 0.0
var throb := 0.0
var last_wrap := -1.0
var torch_on := false
# Fener: sahne yalnız koni ve elin çevresinde aydınlanır; dışı zifiri kalır.
var torch_k := 0.0
var torch_mask: Texture2D
const TORCH_ORIGIN := Vector2(166, FLOOR_Y - 16)
const TORCH_ANGLE := -0.22
const MASK_R := 420.0
const ANGRY_LINES := ["Yine aynı hatayı yaptım!", "Bunu biliyordum!", "Neden önceden hazırlanmadım?!",
	"Kaç kere daha?! Kaç kere daha buraya düşeceğim?!", "Aptal! Mutfak oradaydı, banyo oradaydı!",
	"Keşke çantayı hazırlasaydım... Keşke bir kere olsun önceden davransaydım...", "Keşke... keşke... hep keşke!"]
var red := 0.0
var canvas: Control
var time := 0.0
var fade := 0.0
var light := 0.0
var whiteout := 0.0
var caption := ""
var caption_alpha := 0.0
var sub_caption := ""
var prompt := ""
var bubbles: Array = []
var bag_visible := false
var bag_open := 0.0
var waiting_open := false
var selecting := false
var selected := 0
var wanted := ""
var used := {}
var hint := ""
var hint_time := 0.0
var leg_mode := false
var wraps := 0
var next_key := "A"
var strip_anim := 0.0
var bandaged := false
var bleeding_active := false
var bleed_dying := false
var bleed_left := 0.0
var bleed_bpm := 0.0
var bleed_warned := false
var bleed_regret := false
var crawl_mode := false
var crawl_count := 0
var man_offset := 0.0
var slab_jolt := 0.0
var whistle_mode := false
var whistle_pose := 0.0
var power := 0.0
var reach := 0.0
var rescued := false
var tex := {}
var sheet: Texture2D
var sounds := {}
var chunks: Array = []
var pebbles: Array = []


func _ready() -> void:
	layer = 40
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw.connect(_draw_ui)
	add_child(canvas)
	for path in ["bag_closed", "bag_open", "injured_leg"]:
		tex[path] = load("res://assets/rubble/%s.png" % path)
	for item in ITEMS:
		tex[item.id] = load(item.tex)
	sheet = load("res://assets/player_sheet.png")
	for i in 3:
		tex["cat_%d" % i] = load("res://assets/rubble/cat_%d.png" % i)
	_build_rubble()
	for entry in [["groan", VoiceSynth.groan(), 0.0], ["zipper", Sfx.zipper(), -2.0], ["growl", Sfx.growl(), 0.0],
			["eat", Sfx.eat(), 3.0], ["drink", Sfx.drink(), 3.0], ["cloth", Sfx.cloth(), -4.0],
			["whistle", Sfx.whistle(), -30.0], ["dig", Sfx.dig(), -30.0], ["machine", Sfx.machine(), -30.0],
			["grunt", Sfx.grunt(), -2.0], ["meow", VoiceSynth.meow(), -6.0]]:
		var p := AudioStreamPlayer.new()
		p.stream = entry[1]
		p.volume_db = entry[2]
		add_child(p)
		sounds[entry[0]] = p
	rubble_ambience = AudioStreamPlayer.new()
	var ambient_stream: AudioStreamWAV = RUBBLE_AMBIENCE.duplicate()
	ambient_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	ambient_stream.loop_end = roundi(ambient_stream.get_length() * ambient_stream.mix_rate)
	rubble_ambience.stream = ambient_stream
	rubble_ambience.volume_db = -40.0
	add_child(rubble_ambience)
	rubble_ambience.play()
	create_tween().tween_property(rubble_ambience, "volume_db", 20.0, 1.8)
	_run()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _tween(property: String, to: float, seconds: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, property, to, seconds)
	await tw.finished


# --- Senaryo ---------------------------------------------------------------------

func _has(id: String) -> bool:
	return bool(items.get("water_bottle" if id == "water" else id, false))


func _run() -> void:
	await _tween("fade", 1.0, 0.5)
	await _wait(1.0)
	light = 0.05
	await _tween("fade", 0.0, 2.0)
	sounds.groan.play()
	await say("man", "Ne... Ne oldu?", 2.0)
	await say("man", "Aman Tanrım...", 1.8)
	await say("man", "Hiçbir şey göremiyorum!", 2.0)
	if unprepared_repeat > 0:
		var start := (unprepared_repeat - 1) * 2
		await say("man", ANGRY_LINES[start % ANGRY_LINES.size()], 2.2)
		await say("man", ANGRY_LINES[(start + 1) % ANGRY_LINES.size()], 2.2)
	await say("man", "Kafa lambası... Lambayı açmalıyım.", 2.0)
	if _has("flashlight"):
		prompt = "[E] Kafa lambasını aç"
		await _press_e()
		prompt = ""
		sounds.cloth.play()
		torch_on = true
		# Tık: kısa titreşip yanar.
		for e in [0.6, 0.0, 0.85, 0.2, 1.0]:
			await _tween("torch_k", e, 0.07)
	else:
		await _wait(0.6)
		await say("man", "Kafa lambası... yanımda değil. Getirmemişim...", 2.4)
		await say("man", "Keşke kafa lambasını yanıma alsaydım... Banyoda duruyordu...", 2.6)
		await _tween("light", 0.1, 2.0)
		await say("man", "Gözlerim alışsın... el yordamıyla...", 2.2)
	_meow()
	await say("cat", "Miyav...", 1.4)
	await say("man", "Osman... yaşıyorsun...", 2.0)
	sounds.groan.play()
	_start_bleeding()
	await say("man", "Yaralanmışım...", 1.8)
	await say("man", "Bandaj bulmalıyım.", 1.8)
	if not _has("bandage"):
		await say("man", "Bandaj... yanımda yok! Kanamayı durduramıyorum...", 2.8)
		await _wait(1.2)
		_meow()
		await say("cat", "Miyav...", 1.4)
		await say("man", "Osman... yanımda kal...", 2.0)
		return
	await use_item("bandage", "Bacağın kanıyor! [E] Eşyalarına bak ve sargı bezini seç.")
	if bleed_dying:
		return
	await _leg_minigame()
	if bleed_dying:
		return
	await say("man", "Kanama durdu... galiba.", 2.2)
	# Yorgunluk: uyur; 2 gün geçer (analog saat de ileri sarar).
	await say("man", "Çok yoruldum... gözlerim... kapanıyor...", 2.6)
	await _tween("fade", 1.0, 2.0)
	if story != null:
		story.game.jump_clock(48.0)
	caption = "2 gün sonra..."
	await _tween("caption_alpha", 1.0, 1.0)
	await _wait(1.8)
	await _tween("caption_alpha", 0.0, 0.8)
	caption = ""
	await _tween("fade", 0.0, 1.6)
	sounds.groan.play()
	sounds.growl.play()
	await say("man", "Midem... deli gibi açım!", 2.0)
	await say("man", "Çok susadım... dudaklarım çatladı...", 2.2)
	# Kalp atışı hızlıdan yavaşa iner, sesi zayıflar. Hayatta tutan su: yalnız yemek yetmez.
	# Konserve yenebilir (rahatlatır ama nabzı kurtarmaz); su içilirse kurtulur.
	if not await _pulse_race("water|food", "Kalbin zayıflıyor! [E] Eşyalarına bak.", 22.0):
		var line := "Yemek yetmedi... Keşke suyu da alsaydım..." if used.has("food") \
			else "Su... Keşke bir şişe su alsaydım... sadece bir şişe..."
		await _starve(line, "thirst")
		return
	await say("man", "Ohh... su... Keşke daha fazlasını alsaydım...", 2.4)
	await _wait(1.2)
	await say("rescuer", "Kimse var mı?!", 2.2)
	await say("rescuer", "Sesimizi duyan var mı?!", 2.4)
	await say("man", "Buradayım! ...sesim... çıkmıyor...", 2.4)
	if not _has("whistle"):
		# Düdük yoksa sesi ekibe ulaşmaz: ekip uzaklaşır, kurtuluş yok.
		await say("man", "Düdük... düdük yok! BURADAYIM!", 2.2)
		await say("rescuer", "...bir şey duydun mu?", 1.8)
		await say("rescuer", "Hayır. Burada kimse yok, diğer binaya geçelim!", 2.6)
		await say("man", "Hayır... gitmeyin... GİTMEYİN!", 2.4)
		await _starve("Keşke o düdüğü alsaydım... Bir düdük... sadece bir düdük...", "unheard")
		return
	await use_item("whistle", "Kurtarma ekibi yakında! [E] Eşyalarına bak, düdüğü seç.")
	await _whistle_game()
	await _rescue()


# Nabız yarışı: kalp atışı hızlıdan yavaşa iner, ekran kızarır. Süre dolmadan eşya seçilirse true.
func _pulse_race(id: String, text: String, seconds: float) -> bool:
	# Atışlar tek tek, gerçek zamanla çalınır: ~125 BPM'den ~28 BPM'e iner, her vuruş biraz daha zayıf.
	heart = AudioStreamPlayer.new()
	heart.stream = Sfx.heart_thump()
	heart.max_polyphony = 2
	add_child(heart)
	beat_clock = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "red", 0.45, seconds)
	pulse_left = seconds
	pulse_total = seconds
	var ok := false
	var ids := id.split("|")
	var have_any := false
	for one in ids:
		if _has(one):
			have_any = true
	prompt_plain = true
	if have_any:
		wanted = id
		prompt = text
		waiting_open = true
		picked = ""
		while pulse_left > 0.0:
			await get_tree().process_frame
			if picked == ids[0]:
				ok = true
				break
			if picked != "":
				# Yemek: biraz güç verir ama nabzı kurtarmaz; su hâlâ gerekli.
				picked = ""
				prompt = text
				say("man", "Hmm... nom... Biraz kendime geldim ama... boğazım yanıyor.", 2.6)
				var any_left := false
				for one in ids:
					if _has(one) and not used.has(one):
						any_left = true
				if any_left:
					await _wait(0.6)
					waiting_open = true
	else:
		while pulse_left > 0.0:
			await get_tree().process_frame
	pulse_left = 0.0
	tw.kill()
	prompt = ""
	prompt_plain = false
	waiting_open = false
	if ok:
		# Toparlanma: birkaç sakin atış, sesi yavaşça söner.
		for i in 4:
			heart.volume_db = -8.0 - i * 5.0
			heart.play()
			throb = 0.5 - i * 0.1
			await _wait(0.85)
	else:
		# Son atışlar: aralar uzar, ses zayıflar... ve kalp durur.
		for gap in [2.2, 2.9, 3.8]:
			heart.volume_db -= 4.0
			heart.play()
			throb = 0.35
			await _wait(gap)
		await _wait(1.2)
	heart.stop()
	heart.queue_free()
	heart = null
	if selecting or bag_visible:
		await _close_bag()
	if ok:
		await _tween("red", 0.0, 1.0)
	return ok


# Açlık/susuzluk/duyulmama: nabız durur, ekran kararır, döngü başa döner.
func _starve(line: String, cause: String) -> void:
	create_tween().tween_property(rubble_ambience, "volume_db", -50.0, 3.0)
	await say("man", line, 2.6)
	_meow()
	await say("cat", "Miyav...", 1.4)
	await _tween("red", 0.6, 1.5)
	await _tween("fade", 1.0, 2.0)
	if story != null:
		story.die_from(cause)


func _press_e() -> void:
	waiting_e = true
	await chosen


# Bacak sarılmazsa nabız sürekli düşer; 0 olduğunda kalp durur: görüş kızarıp kararır, kan kaybından
# ölüm ve geri sarma.
func _bleed_out() -> void:
	if bleed_dying or bandaged:
		return
	create_tween().tween_property(rubble_ambience, "volume_db", -50.0, 2.5)
	bleed_dying = true
	bleeding_active = false
	bleed_bpm = 0.0
	leg_mode = false
	selecting = false
	bag_visible = false
	waiting_open = false
	prompt = ""
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "red", 0.62, 2.0)
	tw.tween_property(self, "light", 0.08, 2.0)
	_meow()
	await tw.finished
	if heart != null:
		heart.stop()
		heart.queue_free()
		heart = null
	await _tween("fade", 1.0, 1.5)
	if story != null:
		story.die_from("bleed")


func _start_bleeding() -> void:
	bleeding_active = true
	bleed_left = BLEED_TIME
	bleed_bpm = BLEED_TIME
	beat_clock = 0.0
	heart = AudioStreamPlayer.new()
	heart.stream = Sfx.heart_thump()
	heart.max_polyphony = 2
	add_child(heart)


# Çanta aç → ←/→ seç → E. İstenen eşya seçilene kadar sürer.
func use_item(id: String, text: String) -> void:
	wanted = id
	prompt = text
	waiting_open = true
	await chosen
	prompt = ""


func _open_bag() -> void:
	waiting_open = false
	bag_visible = true
	sounds.zipper.play()
	await _tween("bag_open", 1.0, 0.9)
	selecting = true
	prompt = "←/→ eşya seç   •   [E] / tıkla: kullan"


func _close_bag() -> void:
	selecting = false
	await _tween("bag_open", 0.0, 0.35)
	bag_visible = false


func _choose() -> void:
	var item: Dictionary = ITEMS[selected]
	if not _has(item.id):
		_show_hint(item.name + " yanımda yok...")
		return
	if used.has(item.id):
		_show_hint(item.name + " bitti.")
		return
	if not (item.id in wanted.split("|")):
		_show_hint("Şu an " + item.name.to_lower() + " değil...")
		return
	if item.id != "whistle":
		used[item.id] = true
	picked = item.id
	await _close_bag()
	if wanted == "water|food" and item.id in ["food", "water"]:
		_play_consumption(item.id)
	chosen.emit()


func _play_consumption(id: String) -> void:
	# Enkaz uğultusu yeme/içme sesini bastırmasın; sonraki eşya seçimi eski sesi keser.
	if consume_tween != null and consume_tween.is_running():
		consume_tween.kill()
	sounds.eat.stop()
	sounds.drink.stop()
	var player: AudioStreamPlayer = sounds["drink" if id == "water" else "eat"]
	player.play()
	consume_tween = create_tween()
	consume_tween.tween_property(rubble_ambience, "volume_db", 0.0, 0.15)
	consume_tween.tween_interval(maxf(0.0, player.stream.get_length() - 0.35))
	consume_tween.tween_property(rubble_ambience, "volume_db", 20.0, 0.5)


func _show_hint(text: String) -> void:
	hint = text
	hint_time = 1.6


func _leg_minigame() -> void:
	leg_mode = true
	wraps = 0
	next_key = "A"
	prompt = "A ve D tuşlarına SIRAYLA basarak bacağını sar!"
	await step_done
	if bleed_dying:
		return
	leg_mode = false
	bandaged = true
	bleeding_active = false
	bleed_left = 0.0
	if heart != null:
		heart.stop()
		heart.queue_free()
		heart = null
	create_tween().tween_property(self, "red", 0.0, 1.0)
	prompt = ""


func _crawl() -> void:
	crawl_mode = true
	crawl_count = 0
	prompt = "[E] tuşuna art arda bas: ittir ve sürünmeye çalış!"
	await step_done
	crawl_mode = false
	prompt = ""


func _whistle_game() -> void:
	whistle_mode = true
	power = 0.0
	reach = 0.0
	if not shouting:
		sounds.whistle.play()
	prompt = "[E]'ye art arda bas: düdük çal!" if not shouting else "[E]'ye art arda bas: var gücünle bağır!"
	await step_done
	whistle_mode = false
	prompt = ""
	await _tween("power", 0.0, 0.4)
	sounds.whistle.stop()


func _rescue() -> void:
	create_tween().tween_property(rubble_ambience, "volume_db", -50.0, 3.0)
	await say("rescuer", "Bir düdük sesi! Burada biri var!", 2.2)
	await say("rescuer", "Dayanın! Geliyoruz!", 2.0)
	sounds.dig.play()
	sounds.machine.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sounds.dig, "volume_db", -2.0, 6.0)
	tw.tween_property(sounds.machine, "volume_db", -6.0, 6.0)
	tw.tween_property(self, "light", 1.0, 8.0)
	await say("man", "Osman... duydun mu? Geliyorlar...", 2.6)
	_meow()
	await say("cat", "Miyav!", 1.4)
	await tw.finished
	await say("rescuer", "Seni görüyorum! Elini ver!", 2.4)
	await _tween("whiteout", 1.0, 2.5)
	sounds.dig.stop()
	sounds.machine.stop()
	# Kurtarıldı: son hikâye denetçisinde belirlenir (Osman/eş durumuna göre seçim ya da son ekranı).
	if story != null:
		story.after_rubble_rescue(has_cat)
		return
	rescued = true
	end_t = 0.0
	# Son ekran sade kalsın: köşedeki saat gizlenir.
	if story != null and story.game.has_node("clock"):
		story.game.get_node("clock").visible = false


# --- Girdi ---------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not click and (not (event is InputEventKey) or not event.pressed or event.echo):
		return
	get_viewport().set_input_as_handled()
	var key: int = KEY_E if click else event.physical_keycode
	if click and selecting:
		var view := canvas.size
		var origin := Vector2(view.x * 0.5 - 420, view.y - 420 + (1.0 - bag_open) * 80.0)
		var mouse: Vector2 = canvas.make_input_local(event).position
		for i in ITEMS.size():
			if Rect2(origin + Vector2(270 + i * 140, 70), Vector2(120, 150)).has_point(mouse):
				selected = i
				_choose()
				return
		return
	if rescued and key == KEY_R:
		story.reset_loop()
		get_tree().reload_current_scene()
		return
	if bleed_dying:
		return
	if leg_mode:
		var pressed := "A" if key == KEY_A else ("D" if key == KEY_D else "")
		if pressed == "":
			return
		if pressed != next_key:
			_show_hint("Sırayla: A, D, A, D...")
			return
		if time - last_wrap < WRAP_MIN_GAP:
			_show_hint("Yavaş... dikkatli sar.")
			return
		last_wrap = time
		next_key = "D" if pressed == "A" else "A"
		wraps += 1
		strip_anim = 1.0
		sounds.cloth.play()
		if wraps >= WRAPS_NEEDED:
			step_done.emit()
		return
	if crawl_mode and key == KEY_E:
		crawl_count += 1
		sounds.grunt.pitch_scale = randf_range(0.9, 1.1)
		sounds.grunt.play()
		slab_jolt = 1.0
		man_offset = minf(man_offset + 0.8, 5.0)
		if crawl_count >= CRAWL_NEEDED:
			step_done.emit()
		return
	if whistle_mode and key == KEY_E:
		power = minf(1.0, power + (0.08 if shouting else 0.16))
		pulses.append({"age": 0.0, "k": clampf(0.35 + power, 0.0, 1.0), "seed": randf() * TAU})
		if shouting:
			sounds.grunt.pitch_scale = randf_range(1.1, 1.3)
			sounds.grunt.play()
			say("man", ["BURADAYIM!", "YARDIM EDİN!", "BURADAYIZ!"][randi() % 3], 0.8)
		return
	if waiting_e and key == KEY_E:
		waiting_e = false
		chosen.emit()
		return
	if waiting_open and key == KEY_E:
		_open_bag()
		return
	if selecting:
		if key == KEY_LEFT or key == KEY_A:
			selected = (selected + ITEMS.size() - 1) % ITEMS.size()
			sounds.cloth.play()
		elif key == KEY_RIGHT or key == KEY_D:
			selected = (selected + 1) % ITEMS.size()
			sounds.cloth.play()
		elif key == KEY_E:
			_choose()


func _process(delta: float) -> void:
	time += delta
	whistle_pose = move_toward(whistle_pose, 1.0 if whistle_mode and not shouting else 0.0, delta * 3.5)
	if end_t >= 0.0:
		end_t += delta
	if bleeding_active:
		# Sarılmamış yara: nabız 118'den 0'a kadar sürekli düşer; 0'da kalp durur.
		bleed_left = maxf(0.0, bleed_left - delta)
		var bleed_k := 1.0 - bleed_left / BLEED_TIME
		# Ekrandaki nabız kalan süreyle aynı: 20'den 0'a, saniyede bir düşer.
		bleed_bpm = bleed_left
		red = maxf(red, lerpf(0.04, 0.55, bleed_k))
		if bleed_left < 8.0 and not bleed_warned:
			bleed_warned = true
			say("man", "Kanama durmuyor... nabzım düşüyor...", 2.4)
		if bleed_left < 4.2 and not bleed_regret and not _has("bandage"):
			bleed_regret = true
			say("man", "Keşke sargı bezini yanıma alsaydım...", 2.6)
		beat_clock -= delta
		# Kalp atışı sesi giderek yavaşlar ve zayıflar.
		if beat_clock <= 0.0 and heart != null and bleed_left > 0.4:
			beat_clock = 60.0 / lerpf(110.0, 30.0, bleed_k)
			heart.volume_db = lerpf(-3.0, -24.0, bleed_k)
			heart.play()
			throb = 1.0 - bleed_k * 0.7
		if bleed_left <= 0.0:
			_bleed_out()
	pulse_left = maxf(0.0, pulse_left - delta)
	throb = maxf(0.0, throb - delta * 3.0)
	if pulse_left > 0.0 and heart != null:
		beat_clock -= delta
		if beat_clock <= 0.0:
			var k := 1.0 - pulse_left / pulse_total
			var bpm := lerpf(125.0, 28.0, pow(k, 0.8))
			beat_clock = 60.0 / bpm
			heart.volume_db = lerpf(0.0, -20.0, k * k)
			heart.play()
			throb = 1.0 - k * 0.6
	for p in pulses:
		p.age += delta
	pulses = pulses.filter(func(p): return p.age < 1.4)
	# Güçlü düdükte tavan döşemesinden ince toz süzülür.
	if whistle_mode and power > 0.35 and randf() < power * 0.6:
		motes.append({"pos": Vector2(randf_range(150, 300), randf_range(140, 150)), "age": 0.0})
	for mo in motes:
		mo.age += delta
		mo.pos.y += delta * 26.0
	motes = motes.filter(func(mo): return mo.age < 1.6)
	hint_time = maxf(0.0, hint_time - delta)
	strip_anim = maxf(0.0, strip_anim - delta * 2.5)
	slab_jolt = maxf(0.0, slab_jolt - delta * 5.0)
	if not crawl_mode:
		man_offset = maxf(0.0, man_offset - delta * 1.5)
	if whistle_mode:
		# Basılı tutmak sesi yükseltir; bırakınca söner. Ses ekibe ulaştıkça "reach" dolar.
		# Basılı tutmak sesi ancak yarıya çıkarır; ekibe ulaşmak için E'ye hızlı hızlı basmak gerekir.
		if (Input.is_physical_key_pressed(KEY_E) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) and power < 0.4:
			power = minf(0.4, power + delta * 0.5)
		else:
			power = maxf(0.0, power - delta * 0.6)
		sounds.whistle.volume_db = (lerpf(-40.0, 2.0, sqrt(power)) if power > 0.02 else -60.0) if not shouting else -80.0
		sounds.whistle.pitch_scale = 0.9 + power * 0.2
		reach += delta * power * power * (0.11 if shouting else 0.22)
		if reach >= 1.0:
			reach = 1.0
			step_done.emit()
	for b in bubbles:
		b.age += delta
		var shown := mini(int(b.age * 40.0), b.text.length())
		if b.voice != "" and shown / 2 > b.spoken:
			b.spoken = shown / 2
			if b.text[shown - 1] != " ":
				story.blip(b.voice)
	bubbles = bubbles.filter(func(b): return b.age < b.life)
	canvas.queue_redraw()


func _meow() -> void:
	if has_cat:
		sounds.meow.play()


func say(voice: String, text: String, seconds: float) -> void:
	if not has_cat and (voice == "cat" or text.begins_with("Osman")):
		return
	bubbles = bubbles.filter(func(b): return b.voice != voice)
	bubbles.append({"voice": voice, "text": text, "age": 0.0, "life": seconds, "spoken": 0})
	await _wait(seconds)


# --- Çizim ---------------------------------------------------------------------

func _k() -> float:
	return canvas.size.x / PX.x


func _to_screen(p: Vector2) -> Vector2:
	var k := _k()
	return p * k + Vector2(0, (canvas.size.y - PX.y * k) * 0.5)


func _draw_ui() -> void:
	var view := canvas.size
	var font := ThemeDB.fallback_font
	canvas.draw_rect(Rect2(Vector2.ZERO, view), Color.BLACK)
	var k := _k()
	canvas.draw_set_transform(Vector2(0, (view.y - PX.y * k) * 0.5), 0.0, Vector2(k, k))
	_draw_scene()
	_draw_torch_mask(k, (view.y - PX.y * k) * 0.5)
	canvas.draw_set_transform(Vector2.ZERO)
	_draw_bubbles(font)
	if bag_visible:
		_draw_bag(font)
	if leg_mode:
		_draw_leg(font)
	if whistle_mode:
		_draw_whistle(font)
	if crawl_mode:
		var bar := Rect2(view.x * 0.5 - 200, view.y - 150, 400, 18)
		canvas.draw_rect(bar, Color(0.1, 0.1, 0.1, 0.8))
		canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(crawl_count) / CRAWL_NEEDED, bar.size.y)), Color("d9a03a"))
	if prompt != "":
		var box := Rect2(view.x * 0.5 - 520, view.y - 100, 1040, 56)
		# Yönergeler kutusuz: yalnız gölgeli metin, hafifçe nefes alır.
		var col := Color(1, 0.55, 0.5) if prompt_plain else Color("ffe7a8")
		col.a = 0.7 + 0.3 * sin(time * 3.0)
		canvas.draw_string(font, box.position + Vector2(2, 39), prompt, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 24, Color(0, 0, 0, col.a * 0.8))
		canvas.draw_string(font, box.position + Vector2(0, 37), prompt, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 24, col)
	if bleeding_active or bleed_dying:
		var vital_box := Rect2(28, 28, 226, 72)
		canvas.draw_rect(vital_box, Color(0.08, 0.05, 0.06, 0.78))
		canvas.draw_rect(vital_box, Color(0.75, 0.24, 0.22, 0.85), false, 2.0)
		canvas.draw_string(font, Vector2(44, 57), "KAN KAYBI", HORIZONTAL_ALIGNMENT_LEFT, 190, 18, Color(1.0, 0.64, 0.58))
		var low := clampf(1.0 - bleed_bpm / BLEED_TIME, 0.0, 1.0)
		var pulse_col := Color.WHITE.lerp(Color(1.0, 0.25, 0.22), low)
		if bleed_bpm < 8.0:
			pulse_col.a = 0.6 + 0.4 * sin(time * 8.0)
		canvas.draw_string(font, Vector2(44, 88), "NABIZ: %d" % maxi(0, ceili(bleed_bpm)), HORIZONTAL_ALIGNMENT_LEFT, 190, 27, pulse_col)
	if hint_time > 0.0:
		canvas.draw_string(font, Vector2(0, view.y - 170), hint, HORIZONTAL_ALIGNMENT_CENTER, view.x, 26, Color(1, 0.6, 0.5, minf(1.0, hint_time * 2.0)))
	if red > 0.0 or throb > 0.0:
		var rr := red + throb * 0.18
		for i in 20:
			canvas.draw_arc(view * 0.5, view.length() * (0.2 - throb * 0.02) + i * 22.0, 0, TAU, 96, Color(0.45, 0.0, 0.0, rr * 0.12), 24.0)
	if whiteout > 0.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(1.0, 0.97, 0.9, whiteout))
	if fade > 0.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, fade))
	if rescued:
		_draw_end_screen(view, font)
	if caption != "" and not rescued:
		var ink := Color(0.15, 0.12, 0.1, caption_alpha) if rescued else Color(0.9, 0.9, 0.9, caption_alpha)
		canvas.draw_string(font, Vector2(0, view.y * 0.5), caption, HORIZONTAL_ALIGNMENT_CENTER, view.x, 64, ink)
		if sub_caption != "":
			canvas.draw_string(font, Vector2(0, view.y * 0.5 + 60), sub_caption, HORIZONTAL_ALIGNMENT_CENTER, view.x, 26, ink)


# Son ekran: beyaz ışıktan sıcak krem bir zemine yumuşak geçiş; artı hafifçe büyüyerek, başlık
# aşağıdan süzülerek, ince çizgi ortadan açılarak ve en son küçük ipucu belirir. Sade kalır.
func _draw_end_screen(view: Vector2, font: Font) -> void:
	var ease_out := func(x: float) -> float: return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)
	# Zemin: üstte daha açık, altta biraz sıcak; ince yatay bantlarla yumuşak degrade.
	var bands := 32
	for i in bands:
		var t := float(i) / (bands - 1)
		var col := Color(0.99, 0.97, 0.92).lerp(Color(0.95, 0.9, 0.82), t)
		col.a = ease_out.call(end_t / 1.2)
		canvas.draw_rect(Rect2(0, view.y * i / bands, view.x, view.y / bands + 1), col)
	# Ortada çok hafif bir ışık halesi (nefes alır gibi).
	var breathe := 0.5 + 0.5 * sin(end_t * 0.8)
	for r in range(6):
		canvas.draw_circle(view * 0.5 + Vector2(0, -40), 380.0 - r * 55.0, Color(1, 1, 1, 0.035 + 0.015 * breathe))
	var cross_k: float = ease_out.call(end_t / 1.6)
	var center := Vector2(view.x * 0.5, view.y * 0.5 - 120 + (1.0 - cross_k) * 10.0)
	_draw_green_cross(center, cross_k, 0.8 + 0.2 * cross_k)
	var title_k: float = ease_out.call((end_t - 0.9) / 1.4)
	var ink := Color(0.22, 0.18, 0.14, title_k)
	canvas.draw_string(font, Vector2(0, view.y * 0.5 + 10 + (1.0 - title_k) * 18.0), "KURTARILDINIZ", HORIZONTAL_ALIGNMENT_CENTER, view.x, 58, ink)
	var line_k: float = ease_out.call((end_t - 1.8) / 1.0)
	var half := 120.0 * line_k
	canvas.draw_line(Vector2(view.x * 0.5 - half, view.y * 0.5 + 42), Vector2(view.x * 0.5 + half, view.y * 0.5 + 42), Color(0.35, 0.6, 0.4, 0.7 * line_k), 2.0)
	var hint_k: float = clampf((end_t - 2.8) / 1.2, 0.0, 1.0)
	var hint_a := hint_k * (0.55 + 0.25 * sin(end_t * 2.2))
	canvas.draw_string(font, Vector2(0, view.y * 0.5 + 84), "R  —  yeniden oyna", HORIZONTAL_ALIGNMENT_CENTER, view.x, 20, Color(0.3, 0.26, 0.22, hint_a))


# Kurtarma ekranı: sade piksel yeşil artı (yazının üstünde, onu örtmez).
func _draw_green_cross(c: Vector2, a: float, scale := 1.0) -> void:
	var P := 6.0 * scale
	var cells := []
	for y in range(-5, 6):
		for x in range(-5, 6):
			if (absi(x) <= 1) or (absi(y) <= 1):
				cells.append(Vector2(x, y))
	for cell in cells:
		canvas.draw_rect(Rect2(c + cell * P - Vector2(P, P) * 0.5 - Vector2(P, P) * 0.5, Vector2(P, P) * 2.0), Color(0.08, 0.3, 0.12, a))
	for cell in cells:
		var col := Color("3fae5a")
		if cell.x <= -1 and cell.y <= -1 or (cell.y == -5) or (cell.x == -5):
			col = Color("6fd486")
		canvas.draw_rect(Rect2(c + cell * P - Vector2(P, P) * 0.5, Vector2(P, P)), Color(col, a))


# Karanlık maskesi: koninin ve elin çevresi açık, gerisi neredeyse siyah. Kurtarma ışığı
# geldikçe (light → 1) maske kalkar. Hafif titreşim fenerin pil ışığını hissettirir.
func _draw_torch_mask(k: float, y_off: float) -> void:
	if torch_k <= 0.0:
		return
	if torch_mask == null:
		torch_mask = _build_torch_mask()
	var open := clampf((light - 0.24) / 0.76, 0.0, 1.0)
	var flicker := 1.0 + sin(time * 23.0) * 0.015 + sin(time * 7.0) * 0.02
	var dark := clampf(torch_k, 0.0, 1.0) * (1.0 - open)
	var origin := TORCH_ORIGIN + Vector2(man_offset, 0)
	canvas.draw_set_transform(Vector2(0, y_off) + origin * k, TORCH_ANGLE + sin(time * 0.9) * 0.03, Vector2(k, k) * flicker)
	canvas.draw_texture_rect(torch_mask, Rect2(-MASK_R, -MASK_R, MASK_R * 2.0, MASK_R * 2.0), false, Color(1, 1, 1, dark))
	canvas.draw_set_transform(Vector2(0, y_off), 0.0, Vector2(k, k))


func _build_torch_mask() -> Texture2D:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var half := deg_to_rad(30.0)
	var soft := deg_to_rad(16.0)
	for y in size:
		for x in size:
			var d := (Vector2(x, y) - c) / (size * 0.5)
			var r := d.length()
			var lit := 0.0
			# Koni: ~120 px menzil, kenarları yumuşak, uzaklaştıkça söner.
			var reach := r / 0.3
			if d.x > 0.0 and reach < 1.0:
				var off := absf(atan2(d.y, d.x))
				var edge := clampf((half - off) / soft, 0.0, 1.0)
				edge = edge * edge * (3.0 - 2.0 * edge)
				lit = edge * pow(1.0 - reach, 0.7)
			# Elin ve gövdenin çevresine sızan hafif hale.
			lit = maxf(lit, clampf(1.0 - r / 0.09, 0.0, 1.0) * 0.75)
			var a := 0.96 * (1.0 - clampf(lit, 0.0, 1.0))
			img.set_pixel(x, y, Color(0.01, 0.01, 0.015, a))
	# Sahne piksel (nearest) çizilir; maske ise yumuşak geçiş için doğrusal süzülür.
	var smooth := CanvasTexture.new()
	smooth.diffuse_texture = ImageTexture.create_from_image(img)
	smooth.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return smooth


func _poly(points: Array, color: Color, jolt := Vector2.ZERO) -> void:
	var pts := PackedVector2Array()
	for p in points:
		pts.append(p + jolt)
	canvas.draw_colored_polygon(pts, color)
	var outline := pts.duplicate()
	outline.append(pts[0])
	canvas.draw_polyline(outline, Color(0.08, 0.07, 0.07), 1.0)


# Moloz yığını: boşluğun dışını dolduran düzensiz beton, tuğla ve ahşap parçaları (bir kez üretilir).
func _build_rubble() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1999
	var palette := [Color(0.5, 0.48, 0.45), Color(0.42, 0.4, 0.38), Color(0.58, 0.55, 0.5), Color(0.5, 0.26, 0.18), Color(0.44, 0.3, 0.18), Color(0.35, 0.34, 0.33)]
	for i in 260:
		var c := Vector2(rng.randf_range(-10, 370), rng.randf_range(-10, 250))
		# Boşluğun (cep) içine düşen parçalar atlanır; cep: x 64-306, y 146-200 arası, kenarlara doğru daralır.
		var in_pocket := c.x > 72 and c.x < 298 and c.y > 150 + absf(c.x - 185) * 0.08 and c.y < FLOOR_Y + 2
		if in_pocket:
			continue
		var r := rng.randf_range(10, 30)
		var pts := []
		var n := rng.randi_range(4, 6)
		for k in n:
			var a := TAU * k / n + rng.randf_range(-0.3, 0.3)
			pts.append(c + Vector2(cos(a), sin(a) * 0.7) * r * rng.randf_range(0.6, 1.1))
		chunks.append({"pts": pts, "color": palette[rng.randi() % palette.size()] * rng.randf_range(0.75, 1.05)})
	chunks.sort_custom(func(a, b): return a.pts[0].y < b.pts[0].y)
	for i in 70:
		pebbles.append([Vector2(rng.randf_range(60, 310), FLOOR_Y - rng.randf_range(-1, 4)), rng.randf_range(1, 3.5), rng.randf_range(0.3, 0.55)])


func _scene_light() -> float:
	return maxf(light, 0.95 * torch_k)


func _draw_scene() -> void:
	var l := _scene_light()
	var shade := func(c: Color) -> Color: return Color(c.r * l, c.g * l, c.b * l, c.a)
	# Yoğun moloz kütlesi (parçaların arası boş kalmasın) ve cebin karanlık içi.
	canvas.draw_rect(Rect2(Vector2.ZERO, PX), shade.call(Color(0.26, 0.24, 0.23)))
	canvas.draw_rect(Rect2(70, 140, 232, 65), shade.call(Color(0.1, 0.095, 0.09)))
	for x in range(64, 306, 14):
		canvas.draw_rect(Rect2(x, FLOOR_Y - 1, 13, 6), shade.call(Color(0.46, 0.43, 0.4) if (x / 14) % 2 == 0 else Color(0.4, 0.37, 0.35)))
		canvas.draw_line(Vector2(x + 3, FLOOR_Y), Vector2(x + 8, FLOOR_Y + 4), shade.call(Color(0.15, 0.14, 0.13)), 0.6)
	for chunk in chunks:
		_poly(chunk.pts, shade.call(chunk.color))
	# Işık sızan çatlak: tavanda dar bir yarık; kurtarma yaklaştıkça genişler.
	var open := clampf((light - 0.24) / 0.76, 0.0, 1.0)
	var gap := 1.5 + 36.0 * open
	var beam := PackedVector2Array([Vector2(238 - gap * 0.3, 0), Vector2(242 + gap, 0), Vector2(214 + gap * 1.6, FLOOR_Y), Vector2(200 - gap * 0.6, FLOOR_Y)])
	canvas.draw_colored_polygon(beam, Color(1.0, 0.9, 0.65, 0.05 + 0.4 * open))
	# İnmiş tavan döşemesi: cebin tavanı, ortası sarkık; itince titrer.
	var jolt := Vector2(sin(time * 60.0), cos(time * 50.0)) * slab_jolt * 1.2
	_poly([Vector2(40, 124), Vector2(330, 114), Vector2(334, 152), Vector2(240, 163), Vector2(150, 166), Vector2(44, 158)], shade.call(Color(0.6, 0.58, 0.55)), jolt)
	for crack in [[Vector2(120, 128), Vector2(132, 146), Vector2(128, 162)], [Vector2(236, 118), Vector2(240, 140), Vector2(234, 160)], [Vector2(290, 122), Vector2(300, 136)]]:
		var c := PackedVector2Array()
		for p in crack:
			c.append(p + jolt)
		canvas.draw_polyline(c, Color(0.04, 0.04, 0.04), 1.0)
	for rebar in [[Vector2(96, 162), Vector2(92, 172)], [Vector2(104, 163), Vector2(108, 171)], [Vector2(276, 157), Vector2(284, 170)], [Vector2(178, 165), Vector2(176, 171)]]:
		canvas.draw_line(rebar[0] + jolt, rebar[1] + jolt, shade.call(Color(0.62, 0.32, 0.16)), 1.2)
	# Kırık tavan kirişi: sol üstten cebe çapraz iner.
	_poly([Vector2(30, 120), Vector2(38, 116), Vector2(98, FLOOR_Y - 2), Vector2(90, FLOOR_Y)], shade.call(Color(0.45, 0.3, 0.17)))
	canvas.draw_line(Vector2(36, 122), Vector2(92, FLOOR_Y - 4), shade.call(Color(0.3, 0.19, 0.1)), 0.8)
	# Devrilmiş sandalye parçaları (sağda).
	canvas.draw_line(Vector2(268, FLOOR_Y - 2), Vector2(290, FLOOR_Y - 18), shade.call(Color(0.5, 0.33, 0.18)), 2.0)
	canvas.draw_line(Vector2(276, FLOOR_Y - 1), Vector2(296, FLOOR_Y - 10), shade.call(Color(0.46, 0.3, 0.16)), 2.0)
	canvas.draw_rect(Rect2(282, FLOOR_Y - 20, 14, 4), shade.call(Color(0.52, 0.35, 0.2)))
	# Kırık çerçeveli fotoğraf (camı çatlak).
	canvas.draw_rect(Rect2(232, FLOOR_Y - 16, 14, 16), shade.call(Color(0.55, 0.42, 0.22)))
	canvas.draw_rect(Rect2(234, FLOOR_Y - 14, 10, 12), shade.call(Color(0.55, 0.62, 0.7)))
	canvas.draw_polyline(PackedVector2Array([Vector2(235, FLOOR_Y - 13), Vector2(239, FLOOR_Y - 8), Vector2(237, FLOOR_Y - 4), Vector2(243, FLOOR_Y - 3)]), shade.call(Color(0.95, 0.95, 0.95)), 0.6)
	# Sağ duvardan çıkan kırık boru ve damlayan su.
	canvas.draw_rect(Rect2(272, 168, 34, 5), shade.call(Color(0.55, 0.57, 0.6)))
	canvas.draw_rect(Rect2(270, 167, 4, 7), shade.call(Color(0.4, 0.42, 0.45)))
	var drop := fmod(time * 0.9, 1.0)
	canvas.draw_rect(Rect2(271, 174 + drop * (FLOOR_Y - 176), 1.2, 2.2), Color(0.6, 0.75, 0.9, 0.7 * l + 0.1))
	canvas.draw_set_transform(Vector2(0, (canvas.size.y - PX.y * _k()) * 0.5) + Vector2(271, FLOOR_Y) * _k(), 0.0, Vector2(_k(), _k() * 0.3))
	canvas.draw_circle(Vector2.ZERO, 6.0, shade.call(Color(0.25, 0.32, 0.4, 0.8)))
	canvas.draw_set_transform(Vector2(0, (canvas.size.y - PX.y * _k()) * 0.5), 0.0, Vector2.ONE * _k())
	# Tavandan sarkan kopuk kablo.
	var sway := sin(time * 1.3) * 1.5
	canvas.draw_polyline(PackedVector2Array([Vector2(214, 164), Vector2(216 + sway * 0.5, 170), Vector2(213 + sway, 176)]), shade.call(Color(0.1, 0.1, 0.1)), 1.2)
	canvas.draw_rect(Rect2(212 + sway, 176, 2, 2), shade.call(Color(0.85, 0.55, 0.25)))
	# Zemin döküntüsü.
	for p in pebbles:
		var g: float = p[2]
		canvas.draw_rect(Rect2(p[0], Vector2(p[1] * 1.5, p[1])), shade.call(Color(g, g * 0.95, g * 0.9)))
	# Yerde yatan adam (oyuncu görseli 90° döndürülmüş) — gövdenin alt kenarı zemine oturur.
	var man := MAN_POS + Vector2(man_offset, 0)
	canvas.draw_set_transform(_to_screen(man), -PI * 0.5, Vector2.ONE * _k() * MAN_SCALE)
	canvas.draw_texture_rect_region(sheet, Rect2(-16, -16, 32, 32), Rect2(0, 0, 32, 32), Color(l * 1.1, l * 1.05, l))
	canvas.draw_set_transform(Vector2(0, (canvas.size.y - PX.y * _k()) * 0.5), 0.0, Vector2.ONE * _k())
	if whistle_pose > 0.01:
		# Yatan karakter dirseğini büküp düdüğü ağzına kaldırır; üflerken eli hafifçe titreşir.
		var breath := sin(time * 12.0) * minf(power, 0.7) * whistle_pose
		var shoulder := man + Vector2(3, -5)
		var elbow := man + Vector2(8, -1).lerp(Vector2(-5, -11), whistle_pose)
		var hand := man + Vector2(12, 0).lerp(Vector2(-13, -6 + breath), whistle_pose)
		var arm := PackedVector2Array([shoulder.round(), elbow.round(), hand.round()])
		canvas.draw_polyline(arm, shade.call(Color(0.22, 0.17, 0.15)), 5.0)
		canvas.draw_polyline(arm, shade.call(Color(0.79, 0.59, 0.48)), 3.0)
		if whistle_pose > 0.75:
			canvas.draw_texture_rect(tex.whistle, Rect2(hand + Vector2(-5, -4), Vector2(10, 10)), false, Color(maxf(l, 0.35), maxf(l, 0.35), maxf(l, 0.35)))
	var leg := man + Vector2(12, 3)
	if bandaged:
		canvas.draw_rect(Rect2(leg, Vector2(5, 4)), shade.call(Color(0.95, 0.95, 0.9)))
	else:
		canvas.draw_rect(Rect2(leg, Vector2(5, 4)), shade.call(Color(0.65, 0.04, 0.04)))
		canvas.draw_rect(Rect2(leg + Vector2(-3, 5), Vector2(11, 1.5)), shade.call(Color(0.45, 0.02, 0.02)))
	_draw_cat()
	# Işık hüzmesindeki toz.
	var dust := RandomNumberGenerator.new()
	dust.seed = 5
	for i in 30:
		var t := fmod(time * 0.05 + i * 0.137, 1.0)
		var p := Vector2(lerpf(240.0, 207.0, t) + dust.randf_range(-5, 5 + gap), t * FLOOR_Y) + Vector2(sin(time + i) * 2.0, 0)
		canvas.draw_rect(Rect2(p, Vector2(0.8, 0.8)), Color(1, 0.95, 0.8, 0.35 * (0.3 + open)))
	# Daraltıcı karanlık: cepten uzaklaştıkça kararan halkalar.
	var press := 1.0 - open * 0.85
	for i in 34:
		var r := 44.0 + i * 6.0
		canvas.draw_arc(POCKET, r, 0, TAU, 96, Color(0, 0, 0, 0.055 * press), 7.0)


func _draw_cat() -> void:
	if not has_cat:
		return
	# Kedi: tekir pikseller; ara ara göz kırpar, kuyruğunu oynatır.
	# Osman adamın yanında uzanmış; ara ara kıpırdar.
	var l := _scene_light()
	var lay_frame := 7 if fmod(time, 5.0) > 0.6 else 5
	CatSprite.draw(canvas, "lay", CatSprite.LEFT, float(lay_frame), 1.0, CAT_POS + Vector2(0, 2), 0.95, Color(l * 1.15, l * 1.1, l * 1.05))


func _draw_bubbles(font: Font) -> void:
	for b in bubbles:
		var anchor := Vector2.ZERO
		match b.voice:
			"man": anchor = _to_screen(MAN_POS + Vector2(man_offset - 14, -10))
			"cat": anchor = _to_screen(CAT_POS + Vector2(-8, -16))
			_: anchor = Vector2(canvas.size.x * 0.72, 70)
		var shown: String = b.text.substr(0, int(b.age * 40.0))
		var size := font.get_multiline_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, 380, 22) + Vector2(28, 20)
		var rect := Rect2(anchor - Vector2(size.x * 0.5, size.y + 18), size)
		rect.position.x = clampf(rect.position.x, 10, canvas.size.x - size.x - 10)
		rect.position.y = maxf(rect.position.y, 10)
		var style := StyleBoxFlat.new()
		var far: bool = b.voice == "rescuer"
		style.bg_color = Color(1, 1, 1, 0.9 if not far else 0.75)
		style.border_color = Color("2b6cb0") if far else Color("27272b")
		style.set_border_width_all(3)
		style.set_corner_radius_all(12)
		style.draw(canvas.get_canvas_item(), rect)
		if not far:
			canvas.draw_colored_polygon(PackedVector2Array([anchor + Vector2(-9, -20), anchor + Vector2(9, -20), anchor + Vector2(0, -4)]), style.border_color)
		else:
			canvas.draw_string(font, rect.position + Vector2(14, -6), "(uzaktan)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.8, 1.0))
		canvas.draw_multiline_string(font, rect.position + Vector2(14, 10 + font.get_ascent(22)), shown, HORIZONTAL_ALIGNMENT_LEFT, 380, 22, -1, Color("1b1b1f") if not far else Color("1d3f6e"))


func _draw_bag(font: Font) -> void:
	var view := canvas.size
	var panel := Rect2(view.x * 0.5 - 420, view.y - 420, 840, 300)
	var slide := (1.0 - bag_open) * 80.0
	panel.position.y += slide
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.92 * bag_open + 0.05)
	style.border_color = Color("d9661f")
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.draw(canvas.get_canvas_item(), panel)
	# Çanta: fermuar açılırken kapalı → açık geçişi ve hafif zıplama.
	var bag_tex: Texture2D = tex.bag_open if bag_open > 0.5 else tex.bag_closed
	var squash := 1.0 + sin(bag_open * PI) * 0.12
	var bag_size := Vector2(200, 200 / squash)
	canvas.draw_texture_rect(bag_tex, Rect2(panel.position + Vector2(30, 280 - bag_size.y - 30), bag_size), false)
	canvas.draw_string(font, panel.position + Vector2(30, 34), "DEPREM ÇANTASI" if has_bag else "YANIMDAKİLER", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("ffb070"))
	for i in ITEMS.size():
		var item: Dictionary = ITEMS[i]
		var pop := clampf((bag_open - 0.35 - i * 0.12) / 0.3, 0.0, 1.0)
		if pop <= 0.0:
			continue
		var slot := Rect2(panel.position + Vector2(270 + i * 140, 70), Vector2(120, 150))
		var is_sel := selecting and i == selected
		canvas.draw_rect(slot, Color(1, 1, 1, 0.06))
		canvas.draw_rect(slot, Color(1, 0.85, 0.3, 0.6 + 0.4 * sin(time * 6.0)) if is_sel else Color(1, 1, 1, 0.2), false, 4.0 if is_sel else 2.0)
		var s := 96.0 * (0.4 + 0.6 * pop) * (1.08 if is_sel else 1.0)
		var tint := Color(0.4, 0.4, 0.4, pop) if used.has(item.id) else Color(1, 1, 1, pop)
		if not _has(item.id):
			tint = Color(0.15, 0.15, 0.15, 0.5 * pop)
		canvas.draw_texture_rect(tex[item.id], Rect2(slot.get_center() - Vector2(s, s) * 0.5 - Vector2(0, 14), Vector2(s, s)), false, tint)
		canvas.draw_string(font, Vector2(slot.position.x, slot.end.y - 12), item.name + (" (yok)" if not _has(item.id) else (" (bitti)" if used.has(item.id) else "")), HORIZONTAL_ALIGNMENT_CENTER, slot.size.x, 18, Color(1, 1, 1, pop))
	if selecting:
		canvas.draw_string(font, panel.position + Vector2(270, 262), "◀  ←/→  ▶      [E] / tıkla: kullan", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.9, 0.6))


func _draw_leg(font: Font) -> void:
	var view := canvas.size
	canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.82))
	canvas.draw_string(font, Vector2(0, 110), "YARALI BACAĞINI SAR", HORIZONTAL_ALIGNMENT_CENTER, view.x, 36, Color("ffd9a8"))
	var leg_tex: Texture2D = tex.injured_leg
	var scale := 8.0
	var size := Vector2(leg_tex.get_size()) * scale
	var origin := (view - size) * 0.5 + Vector2(0, -20)
	canvas.draw_texture_rect(leg_tex, Rect2(origin, size), false)
	# Sargı katmanları: her A/D basışında baldırı saran yeni bir bant (yara alanı 40-72 px).
	canvas.draw_set_transform(origin, 0.0, Vector2(scale, scale))
	for i in wraps:
		var x := 40.0 + (i % 6) * 5.6 + floorf(i / 6.0) * 2.5
		var anim := strip_anim if i == wraps - 1 else 0.0
		var top := 11.0 - anim * 6.0
		var tilt := 2.0 if i % 2 == 0 else -2.0
		var strip := PackedVector2Array([Vector2(x, top), Vector2(x + 6, top), Vector2(x + 6 + tilt, 33), Vector2(x + tilt, 33)])
		canvas.draw_colored_polygon(strip, Color(0.96, 0.95, 0.9))
		canvas.draw_line(Vector2(x, top + 1), Vector2(x + tilt, 32), Color(0.8, 0.8, 0.75), 0.5)
		# İlk katmanlardan kan sızar, sonrakiler temiz.
		if i < 4:
			canvas.draw_rect(Rect2(x + 1, 18, 4, 4), Color(0.75, 0.1, 0.1, 0.55 - i * 0.12))
	canvas.draw_set_transform(Vector2.ZERO)
	# A / D tuşları: sıradaki parlar.
	for j in 2:
		var label := "A" if j == 0 else "D"
		var key := Rect2(view.x * 0.5 - 140 + j * 180, origin.y + size.y + 30, 100, 100)
		var active := label == next_key
		canvas.draw_rect(key, Color(1, 0.85, 0.3, 0.35 + 0.35 * sin(time * 10.0)) if active else Color(1, 1, 1, 0.1))
		canvas.draw_rect(key, Color(1, 0.85, 0.3) if active else Color(1, 1, 1, 0.4), false, 4.0)
		canvas.draw_string(font, key.position + Vector2(0, 70), label, HORIZONTAL_ALIGNMENT_CENTER, key.size.x, 56, Color.WHITE)
	var bar := Rect2(view.x * 0.5 - 250, origin.y + size.y + 150, 500, 16)
	canvas.draw_rect(bar, Color(0.2, 0.2, 0.2))
	canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(wraps) / WRAPS_NEEDED, bar.size.y)), Color("e8e8e0"))
	canvas.draw_string(font, Vector2(0, bar.end.y + 30), "Sarma: %d / %d" % [wraps, WRAPS_NEEDED], HORIZONTAL_ALIGNMENT_CENTER, view.x, 20, Color.WHITE)


func _draw_whistle(font: Font) -> void:
	var view := canvas.size
	# Ses dalgaları: ağızdan tavandaki çatlağa doğru, piksel ızgarasına oturan kesik cepheler.
	# Moloza çarpan kısımlar kırılır/söner; dalga ilerledikçe incelir ve soğuk beyaza döner.
	var k := _k()
	var mouth := MAN_POS + Vector2(-14, -6)
	var toward := (Vector2(236, 0) - mouth).angle()
	for p in pulses:
		var t: float = p.age / 1.4
		var r := 8.0 + t * 230.0
		var alpha: float = p.k * (1.0 - t) * (1.0 - t)
		var col := Color(1.0, 0.93, 0.7).lerp(Color(0.8, 0.9, 1.0), t)
		var steps := 22
		for i in steps:
			var a0 := toward - 0.9 + 1.8 * float(i) / steps
			# Kesikli cephe: her iki parçadan biri ve rastgele kırılan parçalar boş.
			if i % 2 == 1 or sin(p.seed + i * 2.3 + t * 9.0) > 0.55:
				continue
			var wob := sin(a0 * 7.0 + p.seed + t * 12.0) * 2.0
			var q := mouth + Vector2.from_angle(a0) * (r + wob)
			var q2 := mouth + Vector2.from_angle(a0 + 1.8 / steps * 0.8) * (r + wob)
			if q.y < -4.0 or q.y > FLOOR_Y + 4.0:
				continue
			var a_px := (q * k / 3.0).floor() * 3.0
			var b_px := (q2 * k / 3.0).floor() * 3.0
			var off := Vector2(0, (canvas.size.y - PX.y * k) * 0.5)
			canvas.draw_line(a_px + off, b_px + off, Color(col, alpha), maxf(2.0, 4.0 * p.k * (1.0 - t)))
	for mo in motes:
		var sp := _to_screen(mo.pos)
		canvas.draw_rect(Rect2(sp, Vector2(3, 3)), Color(0.75, 0.7, 0.62, 0.7 * (1.0 - mo.age / 1.6)))
	var meter := Rect2(view.x - 120, 160, 40, 400)
	canvas.draw_rect(meter, Color(0.1, 0.1, 0.1, 0.85))
	var fill := meter.size.y * power
	canvas.draw_rect(Rect2(meter.position.x, meter.end.y - fill, meter.size.x, fill), Color(1.0, 0.85 - power * 0.5, 0.2))
	canvas.draw_rect(meter, Color.WHITE, false, 2.0)
	canvas.draw_string(font, Vector2(meter.position.x - 30, meter.position.y - 14), "SES", HORIZONTAL_ALIGNMENT_CENTER, 100, 22, Color.WHITE)
	var bar := Rect2(view.x * 0.5 - 300, 120, 600, 22)
	canvas.draw_rect(bar, Color(0.1, 0.1, 0.1, 0.85))
	canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * reach, bar.size.y)), Color("4fb3ff"))
	canvas.draw_rect(bar, Color.WHITE, false, 2.0)
	canvas.draw_string(font, Vector2(bar.position.x, bar.position.y - 10), "Kurtarma ekibi sesini duyuyor...", HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 20, Color(0.8, 0.9, 1.0))
