extends Node

signal phone_advance
var phone_waiting := false


# Açılış senaryosu (zaman döngüsü):
# telefon çalar → karısıyla konuşma → deprem → ışıklar gider → fener düşüncesi + oklar banyoya →
# elektrikli su cızırtısı → (suya basarsa ölür, döngü baştan: "Aman tanrım...") →
# kablolarla kaçağı gider → zifiri karanlık → feneri alır → fener yürüdüğü yöne ışık tutar.
# Döngü sayısı sahne yeniden yüklense de Engine meta'da kalır.

const LOOP_KEY := &"asimo_story_loop"
# Son ölüm sebebi: bir sonraki döngüde adam ona göre hatırlar (water / fire / wardrobe).
const DEATH_KEY := &"asimo_last_death"
# Öğrenilenler (ölüm sebepleri kümesi): döngüler boyunca kalır; konuşma ve ipuçları buna göre değişir.
const LEARN_KEY := &"asimo_learned"
const Sfx = preload("res://scripts/sfx.gd")
const RubbleEnding = preload("res://scripts/rubble_ending.gd")
const DrillGame = preload("res://scripts/drill_game.gd")
const UnderBedView = preload("res://scripts/under_bed_view.gd")
const RewindClock = preload("res://scripts/rewind_clock.gd")
const QuakeSafety = preload("res://scripts/quake_safety.gd")
const Tutorial = preload("res://scripts/tutorial.gd")
const TUTORIAL_KEY := &"asimo_tutorial_done"
const TITLE_KEY := &"asimo_title_shown"
const Outside = preload("res://scripts/outside_scene.gd")
const TaskPath = preload("res://scripts/task_path.gd")
# Merkezi sayaç: 30 sn hazırlık → ilk deprem; ardından 70 sn → evde kalınmışsa enkaz.
# Bir kez ölündükten sonra hazırlık 10 sn: oyuncu evi gezmez, bildiklerine odaklanır.
# Yalnız oyuncu evde serbestçe hareket ederken akar; konuşma ve mini oyunlarda durur.
const PHASE1 := 30.0
const PHASE1_AFTER_DEATH := 10.0
const PHASE2 := 70.0
const TitleScreen = preload("res://scripts/title_screen.gd")
const UNPREPARED_KEY := &"asimo_unprepared"
# Fenerin saklanabileceği yerler ve yanlış yerde çıkan komik şeyler.
const SEARCH_FINDS := {
	"çekmece": ["Diş macunu, tarak... kafa lambası yok.", "Bir kutu yara bandı. Kafa lambası değil."],
	"lavabo altı": ["Çamaşır suyu ve bir örümcek. Iyy!", "Islak bir sünger... kafa lambası yok."],
	"çamaşır sepeti": ["Kirli çorap... Osman'ınki mi bu?!", "Islak havlu. Kafa lambası yok."],
	"rezervuar": ["Lastik ördek?! Burada ne işin var?", "Sadece su. Kafa lambası yok."],
}
const FLASH_KEY := &"asimo_flash_spot"
const MIX_RATE := 22050
const PLAYER_HEAD := Vector2(0, -96)

var game: Node2D
var world: Node2D
var loop := 0
var state := &"intro"
var last_room: StringName = &""
var announced_bath := false

var overlay: CanvasLayer
var guide: Guide
var bubbles := {}
var flash: ColorRect
var phone: Area2D
var puddle: Area2D
var ring_player: AudioStreamPlayer
var buzz_player: AudioStreamPlayer
var zap_player: AudioStreamPlayer
var spark_light: PointLight2D
var torch: PointLight2D
var torch_angle := PI * 0.5
var torch_wide: PointLight2D
var torch_flicker: Tween
const ExtinguisherGame = preload("res://scripts/extinguisher_game.gd")
const FireField = preload("res://scripts/fire_field.gd")
const VoiceSynth = preload("res://scripts/voice_synth.gd")
# Püskürtme hedef yardımı: bakış yönüne AIM_ASSIST_ANGLE içinde, menzildeki en yakın alevi hedefler.
const AIM_ASSIST_ANGLE := deg_to_rad(70.0)
const AIM_ASSIST_RANGE := 260.0
# Aleve basınca: yanma süresi (çıktıktan sonra da sürer), hasar aralığı ve miktarı.
const BURN_AFTER := 1.2
const BURN_TICK := 0.35
const BURN_DAMAGE := 7
var burn_left := 0.0
var burn_tick := 0.0
var scream_cooldown := 0.0
var scream_player: AudioStreamPlayer
var body_fire: CPUParticles2D
# Kediyi alınca artçı sarsıntı: yatağın yanındaki dolap (trap) vidalı değilse başına yıkılır.
var trap_done := false
var crushed_player := false
var shock_killed := false
var phase := 0
var phase_left := 0.0
var left_house := false
# Eşin hayatta kalması yalnız bu döngüdeki telefon konuşmasına bağlı.
var wife_safe := false
var call_done := false
# Deprem sonrası çıkış ancak fener bulununca ya da Osman'ın durumu öğrenilince açılır.
var osman_informed := false
var osman_calls := 0
var under_view: CanvasLayer
var fire_trap := false
var pin_game := false
# Kırık bira şişeleri: sehpanın önünde dar bir cam kırığı + bira birikintisi alanı.
var glass_rect := Rect2()
var glass_cd := 0.0
var glass_hurt_at := -10.0
var osman_rescued := false
var call_cooldown := 0.0
var exit_line := 0
var exit_cooldown := 0.0
# Deprem başladıktan sonra Osman için yatak odasına giden oyuncunun arkasından ön kapı enkazla
# tamamen kapanır (seçimin bedeli): o andan sonra evden çıkılamaz, süre bitince enkaz altında kalınır.
var front_blocked := false
const OSMAN_CALLS_NEEDED := 4
const CALL_LINES := ["Pisi pisi!", "Gel Osman!", "Hadi oğlum!", "Gel buraya!", "Korkma, benim!"]
const EXIT_LINES := ["Osman'ı geride bırakamam!", "Hayır, Osman hâlâ içeride!", "Önce Osman'ı bulmalıyım!"]
var drilling := false
var looking := false
# Döngüler: her ölümde zihin biraz daha kötüleşir (giriş repliği, kenar kararması).
var deaths := 0
var searched := {}
var flash_spot := ""
var searching := false
var crack_player: AudioStreamPlayer
var water_player: AudioStreamPlayer
var squeak_player: AudioStreamPlayer
var heart_player: AudioStreamPlayer
var meow_players: Array = []
var meow_timer := 12.0
var dim_light: PointLight2D
var mind: Node2D
var fade_rect: ColorRect
var collapsing := false
# Osman kurtarıldıktan sonraki 20 saniyelik bölüm (hasar öldürmez).
var rescue_phase := false
# Merkezi deprem zamanlaması: iki yol da (telefon / 30 sn hazırlık sayacı) start_quake() ile depremi başlatır.
const PREP_COUNTDOWN := 10.0
var quake_begun := false
var countdown_left := -1.0
var countdown_used := false
var call_cut := false
var safety: Node2D
var blip_player: AudioStreamPlayer
var wife_scream_player: AudioStreamPlayer
var crash_player: AudioStreamPlayer
var pain_player: AudioStreamPlayer
var thud_player: AudioStreamPlayer
const EXIT_POINT := Vector2(927.6, 470)
const CAT_TRIGGER_RADIUS := 260.0
var fire_field: Node2D
var cat: Area2D
var has_tool := false
var meow_clock := 0.0
var meow_player: AudioStreamPlayer
var hiss_player: AudioStreamPlayer
var spray_fx: CPUParticles2D


static func reset_loop() -> void:
	Engine.set_meta(LOOP_KEY, 0)
	Engine.set_meta(DEATH_KEY, "")
	Engine.set_meta(LEARN_KEY, {})


func _ready() -> void:
	world = game.objects
	loop = int(Engine.get_meta(LOOP_KEY, 0)) if Engine.has_meta(LOOP_KEY) else 0
	phone = world.find_item("phone")
	puddle = world.find_item("puddle")
	# Ekran uzayı katmanı: konuşma baloncukları ve oklar karartmadan etkilenmez, keskin çizilir.
	overlay = CanvasLayer.new()
	overlay.name = "story_overlay"
	overlay.layer = 3
	add_child(overlay)
	guide = Guide.new()
	guide.story = self
	overlay.add_child(guide)
	# Sigorta kutusunun üstünde yanıp sönen yıldırım işareti (karanlıkta da görünür).
	var hazard_sign := HazardSign.new()
	hazard_sign.story = self
	overlay.add_child(hazard_sign)
	var flash_layer := CanvasLayer.new()
	flash_layer.layer = 25
	add_child(flash_layer)
	flash = ColorRect.new()
	flash.color = Color(0.85, 0.92, 1.0, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_layer.add_child(flash)
	ring_player = _audio(_build_ring(), -6.0)
	buzz_player = _audio(_build_buzz(), -30.0)
	zap_player = _audio(_build_zap(), -2.0)
	_build_spark_light()
	meow_player = _audio(VoiceSynth.meow(), -2.0)
	scream_player = _audio(VoiceSynth.scream(), 0.0)
	pain_player = _audio(VoiceSynth.pain_scream(), 1.0)
	thud_player = _audio(_build_thud(), 0.0)
	blip_player = _audio(Sfx.blip(), -12.0)
	blip_player.max_polyphony = 4
	wife_scream_player = _audio(VoiceSynth.female_scream(), -2.0)
	crash_player = _audio(Sfx.crash(), 2.0)
	hiss_player = _audio(_build_hiss(), -10.0)
	fire_field = FireField.new()
	fire_field.name = "fire_field"
	fire_field.game = game
	fire_field.all_out.connect(_on_all_out)
	world.add_child.call_deferred(fire_field)
	_build_spray()
	_build_body_fire()
	var tasks := TaskPath.new()
	tasks.story = self
	add_child(tasks)
	# Hazırlık sayacı: ekranın üst ortasında, büyük ve okunur.
	var cd: Label = game.countdown
	cd.text = ""
	cd.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	cd.offset_left = -190.0
	cd.offset_right = -20.0
	cd.offset_top = 14.0
	cd.offset_bottom = 64.0
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cd.add_theme_color_override("font_color", Color("ff3b2f"))
	cd.add_theme_font_size_override("font_size", 40)
	cd.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.03))
	cd.add_theme_constant_override("outline_size", 8)
	world.leak_fixed.connect(_on_leak_fixed)
	world.item_collected.connect(_on_item_collected)
	game.player.died.connect(_on_player_died)
	deaths = loop
	crack_player = _audio(Sfx.sink_crack(), 0.0)
	water_player = _audio(Sfx.water_rush(), -40.0)
	squeak_player = _audio(Sfx.squeak(), -2.0)
	heart_player = _audio(Sfx.heartbeat(), -6.0)
	for v in 3:
		meow_players.append(_audio(VoiceSynth.meow(v), -3.0))
	# Banyo kuru başlar: lavabo ilk sarsıntıda çatlar, su o zaman yayılır.
	if puddle != null:
		puddle.flood = 0.0
	game.quake.quake_started.connect(_on_quake_started)
	# Sarsıntıda hareket = yaralanma; Çök-Kapan-Tutun ile korunma.
	safety = QuakeSafety.new()
	safety.name = "quake_safety"
	safety.game = game
	safety.story = self
	game.add_child.call_deferred(safety)
	# Karanlıkta gözün alışması: fener yokken oyuncunun çevresinde çok soluk bir ışık.
	dim_light = PointLight2D.new()
	dim_light.texture = _radial_texture()
	dim_light.texture_scale = 1.4
	dim_light.energy = 0.35
	dim_light.color = Color(0.6, 0.65, 0.85)
	dim_light.enabled = false
	dim_light.position = Vector2(0, -30)
	game.player.add_child.call_deferred(dim_light)
	# Zihin: ölüm sayısı arttıkça ekran kenarları kararır.
	mind = MindVignette.new()
	mind.strength = minf(0.55, deaths * 0.09)
	overlay.add_child(mind)
	# Geri sarılmış döngünün başı: karanlıktan açılış.
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 1.0 if loop > 0 else 0.0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.get_parent().add_child(fade_rect)
	if loop > 0:
		create_tween().tween_property(fade_rect, "color:a", 0.0, 1.4)
	# Fener her zaman çekmeceli dolabın çekmecesinde; karanlıkta kulpu parıldar.
	flash_spot = ""
	_intro.call_deferred()


func _audio(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


# --- Senaryo adımları -------------------------------------------------------

func _intro() -> void:
	game.status.text = ""
	var p: Node2D = game.player
	p.input_locked = true
	# Oyun açılışında bir kez: giriş ekranı (döngü yeniden başlarken gösterilmez).
	if not Engine.has_meta(TITLE_KEY) and not Engine.has_meta(TUTORIAL_KEY):
		var title := TitleScreen.new()
		add_child(title)
		await title.closed
		Engine.set_meta(TITLE_KEY, true)
	await _door_entry()
	if loop > 0:
		# Önceki döngüleri hatırlar; her ölümde zihni biraz daha kötü.
		await get_tree().create_timer(0.4).timeout
		var tier := [
			"Aman tanrım... az önce ne oldu?!",
			"Yine mi... Bu bir rüya olmalı. Uyan... UYAN!",
			"Kaçıncı kez bu? Başım... başım çatlıyor...",
			"Hah... haha... yine buradayım. Hep buradayım.",
			"Ölmek bile kurtarmıyor... Ne istiyorsun benden?!",
		]
		if deaths >= 3:
			heart_player.play()
			game.camera.shake(1.2, 4.0 + deaths)
		await say(p, tier[mini(deaths, tier.size()) - 1], 2.6, true)
		heart_player.stop()
		var memory := {
			"water": "Elektrik akımı varken suya girmem yanlıştı. Önce sigorta kutusunda kabloları eşleştirip kaçağı gidermeliyim.",
			"fire": "Yangın tüpü olmadan alevlerin arasına dalmam yanlıştı. Önce tüpü alıp pimini çekmeliyim.",
			"wardrobe": "Yatağın yanındaki dolabı sabitlemeden Osman'a seslenmem yanlıştı. Önce matkap ve vidalarla onu duvara sabitlemeliyim.",
			"bleed": "Sargı bezi olmadan enkazda kalmam yanlıştı. Çantaya mutlaka sargı bezi koymalıyım.",
			"quake": "Sarsıntı sürerken koşmam yanlıştı. Bir eşyanın yanında çömelip beklemeliyim.",
			"brick": "Sarsıntı başlarken açıkta durmam yanlıştı. Bir eşyanın yanına geçip C ile çömelmeliyim.",
			"glass": "Kırık camların üstüne basmam yanlıştı. Sehpanın yanından dolaşmalıyım.",
			"starve": "Yiyecek olmadan enkazda kalmam yanlıştı. Mutfaktaki konserveyi almalıyım.",
			"thirst": "Su olmadan enkazda kalmam yanlıştı. Mutfaktaki su şişesini çantaya koymalıyım.",
			"unheard": "Düdüğüm olmadığı için kurtarma ekibi beni duymadı. Düdüğü yanıma almalıyım.",
			"shock": "Akım varken kabloları yanlış eşleştirmem yanlıştı. Renklere dikkat etmeli ya da önce şalteri indirmeliyim.",
			"sacrifice": "Kendi seçimimle geri döndüm... Bu sefer hepsini kurtaracağım.",
		}
		await think(p, memory.get(_last_death(), "Sanki bunu daha önce yaşadım..."), 3.0, true)
	if not Engine.has_meta(TUTORIAL_KEY):
		p.input_locked = false
		var tutorial := Tutorial.new()
		tutorial.story = self
		tutorial.game = game
		add_child(tutorial)
		await tutorial.finished
		Engine.set_meta(TUTORIAL_KEY, true)
	p.input_locked = false
	phase = 1
	phase_left = PHASE1 if deaths == 0 else PHASE1_AFTER_DEATH
	_start_ringing()


# Gece 00:00 eve giriş: kapı gıcırdayarak açılır, karakter dışarının karanlığından eşiğe çıkıp içeri
# yürür, dönüp kapıyı kapatır (tok bir gümleme), sonra odaya döner.
func _door_entry() -> void:
	var p: Node2D = game.player
	var entry: Vector2 = p.global_position
	var threshold := Vector2(entry.x, 438.0)
	p.visible = false
	game.door_open = 0.0
	await get_tree().create_timer(0.5).timeout
	var open := create_tween()
	open.tween_method(func(v: float): game.door_open = v; game.queue_redraw(), 0.0, 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	await open.finished
	p.global_position = threshold
	p.facing = Vector2.DOWN
	p.modulate = Color(0.25, 0.27, 0.4)
	p.visible = true
	p.scripted_walk = true
	# Eşikten içeri bir adım: kapının hemen önünde durur.
	var inside := Vector2(entry.x, threshold.y + 34.0)
	var step := create_tween().set_parallel(true)
	step.tween_property(p, "global_position", inside, 0.55)
	step.tween_property(p, "modulate", Color.WHITE, 0.55)
	await step.finished
	p.scripted_walk = false
	# Kapının yanında arkasını dönüp kapıyı kapatır.
	p.facing = Vector2.UP
	await get_tree().create_timer(0.25).timeout
	var close := create_tween()
	close.tween_method(func(v: float): game.door_open = v; game.queue_redraw(), 1.0, 0.0, 0.3).set_ease(Tween.EASE_IN)
	await close.finished
	thud_player.pitch_scale = 1.2
	thud_player.play()
	game.camera.shake(0.2, 3.0)
	await get_tree().create_timer(0.3).timeout
	# Sonra salonun ortasına yürür.
	p.facing = Vector2.DOWN
	p.scripted_walk = true
	var walk := create_tween()
	walk.tween_property(p, "global_position", entry, 0.9)
	await walk.finished
	p.scripted_walk = false
	if loop == 0:
		think(p, "Oh be... eve geldim. Gece yarısı olmuş.", 2.2)


func _start_ringing() -> void:
	if game.finished:
		return
	state = &"ringing"
	phone.ringing = true
	phone.queue_redraw()
	ring_player.play()
	game.status.text = "Telefon çalıyor! Masadaki telefona git ve [E] ile aç."
	show_bubble(phone, "Rrriiing! Rrriiing!\nArayan: Karım", false, "", -1.0)
	guide.target_room = &"salon"
	guide.target_node = phone
	guide.target_offset = Vector2(0, -60)
	# Açılmazsa zil 25 sn sonra susar (cevapsız arama); telefon yine de açılabilir.
	await get_tree().create_timer(25.0).timeout
	if state == &"ringing" and ring_player.playing:
		ring_player.stop()
		clear_bubble(phone)
		show_bubble(phone, "Cevapsız arama: Karım", false, "", 3.0)


func answer_phone() -> void:
	if state != &"ringing":
		world.message("Hat kesik. Sadece cızırtı geliyor." if state != &"intro" else "Telefon sessiz.")
		return
	state = &"call"
	phone.ringing = false
	phone.queue_redraw()
	ring_player.stop()
	guide.clear()
	clear_bubble(phone)
	game.player.input_locked = true
	game.player.velocity = Vector2.ZERO
	game.status.text = "Karınla konuşuyorsun..."
	_call()


func _call() -> void:
	if loop == 0:
		await _call_love()
	else:
		await _call_warn()
	call_done = true
	if game.finished or call_cut:
		return
	game.player.input_locked = false
	state = &"after_call"
	game.status.text = ""


# İlk tur: akşam için yapılan plan hakkında sevgi dolu bir konuşma (karakter geleceği bilmiyor).
func _call_love() -> void:
	await _phone_line(game.player, "Alo?")
	await _phone_line(phone, "Canım, eve vardın mı? Bu akşam için bir planım var...", W)
	await _phone_line(game.player, "Vardım. Neymiş bakalım bu plan?")
	await _phone_line(phone, "Yarın akşam ilk tanıştığımız o küçük balıkçıya gidelim. Masayı ayırttım bile.", W)
	await _phone_line(game.player, "Sahildeki mi? Hâlâ hatırlıyorsun demek...")
	await _phone_line(phone, "Unutur muyum hiç? Sen de o lacivert ceketini giy.", W)
	await _phone_line(game.player, "Giyerim. Sana da çiçek alacağım, kızma ama.")
	await _phone_line(phone, "Kızmam... Seni çok seviyorum. Osman'a benden bir öpücük ver.", W)
	await _phone_line(game.player, "Ben de seni seviyorum. Annene selam söyle, yarın görüşürüz.")
	await _phone_line(phone, "Düt... düt... düt...", W)


# Sonraki turlar: depremden bahseder; karısı inanmaz. Karşılıklı 3 cümle, her birine iki cevap.
# Üçü de doğruysa karısı güvenli açık alana çıkar ve hayatta kalır.
func _call_warn() -> void:
	var exchanges := [
		["Deprem mi? Canım, depremi kimse önceden bilemez ki!",
			"Biliyorum, kulağa saçma geliyor. Ama bu gece bana güvenmeni istiyorum.",
			"Haklısın... Boş ver, yorgunum galiba."],
		["Peki ne yapmamı istiyorsun? Annemlerdeyim, gece yarısı.",
			"Hemen binadan çık; parka ya da meydana, açık ve güvenli bir alana git.",
			"Asansörle aşağı in, arabaya bin ve beni bekle."],
		["Ya hiçbir şey olmazsa? Sokakta boşuna beklerim.",
			"Olmazsa sabah birlikte güleriz. Ama olursa... seni kaybedemem.",
			"Haklısın, olmazsa boşuna yorulma. Yat uyu."],
	]
	await _phone_line(game.player, "Alo! Dinle beni, birazdan büyük bir deprem olacak!")
	var correct := 0
	for i in exchanges.size():
		if call_cut or game.finished:
			return
		var ex: Array = exchanges[i]
		show_bubble(phone, ex[0], false, W, -1.0)
		var flip := (loop + i) % 2 == 1
		var opts := [ex[2], ex[1]] if flip else [ex[1], ex[2]]
		var pick := await choose("Karına ne diyeceksin?", opts)
		clear_bubble(phone)
		if (pick == 1) == flip:
			correct += 1
		await _phone_line(game.player, opts[pick])
	if correct == exchanges.size():
		wife_safe = true
		await _phone_line(phone, "Tamam... Sesin beni korkutuyor ama seni dinleyeceğim. Annemle hemen parka çıkıyoruz.", W)
		await _phone_line(game.player, "Teşekkür ederim. Seni seviyorum.")
	else:
		await _phone_line(phone, "Bak canım, saçmalıyorsun. Yat uyu, yarın konuşuruz.", W)
		await _phone_line(phone, "Düt... düt... düt...", W)
		think(game.player, "Bana inanmadı...", 2.2)


# İki seçenekli karar paneli; seçilen sırayı döndürür.
func choose(title: String, options: Array) -> int:
	var panel := Outside.ChoicePanel.new()
	panel.title = title
	panel.options = options
	add_child(panel)
	var r: int = await panel.picked
	return r


# Merkezi sayaç. Faz 1: 30 sn → ilk deprem. Faz 2: 70 sn → evde kalınmışsa enkaz.
func _update_phases(delta: float) -> void:
	if phase != 1 and phase != 2:
		return
	var running: bool = not game.finished and not game.player.input_locked and not minigame_active() \
		and not phone_waiting and under_view == null and state != &"call"
	if running:
		phase_left = maxf(0.0, phase_left - delta)
	var secs := ceili(phase_left)
	game.countdown.text = "%02d:%02d" % [secs / 60, secs % 60]
	game.countdown.modulate = Color(1, 1, 1, 1.0 if running else 0.55)
	if phase_left > 0.0 or not running:
		return
	if phase == 1:
		phase = 2
		phase_left = PHASE2
		start_quake()
	else:
		phase = 3
		game.countdown.text = ""
		if not left_house:
			_collapse()


# Tek giriş noktası: bir döngüde deprem yalnız bir kez başlar. Telefon çalıyorsa susar,
# konuşma sürüyorsa hat kesilir.
func start_quake() -> void:
	if quake_begun or game.finished:
		return
	quake_begun = true
	countdown_left = -1.0
	game.countdown.text = ""
	if state == &"ringing":
		phone.ringing = false
		phone.queue_redraw()
		ring_player.stop()
		clear_bubble(phone)
		guide.clear()
	elif state == &"call":
		call_cut = true
		if phone_waiting:
			phone_waiting = false
			phone_advance.emit()
		clear_bubble(phone)
		clear_bubble(game.player)
	_quake_sequence()


func _quake_sequence() -> void:
	game.player.input_locked = false
	state = &"quake"
	# TV yalnız bu anda uyarı yayınına geçer.
	for item in get_tree().get_nodes_in_group("world_items"):
		if item.kind == "tv" and not game.power_dead():
			item.set_alarm(true)
	if call_cut:
		say(game.player, "Alo?! Hat kesildi... Yer sallanıyor!", 2.0)
	game.status.text = "Öncü titreme! Bir eşyanın yanına geç ve [C] ile çömel."
	game.quake.begin(true)
	await game.quake.quake_started
	await get_tree().create_timer(2.6).timeout
	if game.finished:
		return
	_blackout()
	await get_tree().create_timer(0.9).timeout
	if game.finished:
		return
	await say(game.player, "Işıklar gitti!", 1.6)
	await think(game.player, "Banyodan bir çatırtı geldi... su mu akıyor?", 2.6)
	if world.has_item("flashlight"):
		_torch_escape("Neyse ki kafa lambam takılı!")
		return
	await think(game.player, "Banyoda bir kafa lambası vardı... bir yerlerde.", 2.6)
	state = &"to_bath"
	game.status.text = "Karanlık! Banyodaki kafa lambasını bul."
	_point_at_flashlight()


func _start_prep_countdown() -> void:
	if countdown_used or quake_begun:
		return
	countdown_used = true
	countdown_left = PREP_COUNTDOWN


# Mini oyunlar (kablo, matkap, tüp pimi) sırasında deprem yaşanmaz; sayaçlar da bekler.
func minigame_active() -> bool:
	return drilling or pin_game or (world != null and world.panel != null and world.panel.visible)


func _update_countdown(delta: float) -> void:
	if countdown_left <= 0.0 or quake_begun or game.finished or minigame_active():
		return
	countdown_left -= delta
	var secs := ceili(maxf(countdown_left, 0.0))
	game.countdown.text = "DEPREM: %d" % secs
	game.countdown.modulate = Color(1, 0.35, 0.3) if secs <= 10 else Color.WHITE
	if countdown_left <= 0.0:
		start_quake()


# Döngüyü bilen adam karısını uyarmaya çalışır; karısı sözünü keser ve yardım için çığlık atar.
func _call_panic() -> void:
	await _phone_line(game.player, "Alo! Hayatım dinle, birazdan büyük bir dep—")
	await _phone_line(phone, "Canım?! Burada yer sallanıyor! Duvarlar çatlıyor!", "Karım (telefonda)")
	wife_scream_player.play()
	await _phone_line(phone, "İMDAAAT! Kimse yok mu?! YARDIM EDİN!", "Karım (telefonda)")
	await _phone_line(game.player, "Hayatım! Masanın altına gir! Alo?!")
	await _phone_line(phone, "Aaaah—", "Karım (telefonda)")
	await _phone_line(phone, "Düt... düt... düt...", "Karım (telefonda)")


const W := "Karım (telefonda)"


# Konuşma bilgiye göre kurulur: ilk döngü sıradan; sonrakilerde hatırladıkları, ölüm sayısı
# ve öğrendiği tehlikeler satırları belirler, böylece aynı konuşma iki kez birebir tekrarlanmaz.
func _call_story() -> void:
	var rushing := countdown_left > 0.0
	if loop == 0:
		await _phone_line(game.player, "Alo?")
		await _phone_line(phone, "Canım, eve geldin mi?", W)
		await _phone_line(game.player, "Geldim, şimdi girdim kapıdan. Sen neredesin?")
		await _phone_line(phone, "Annemlerdeyim, yarın dönerim. Osman mamasını yedi mi?", W)
		if rushing:
			await _phone_line(game.player, "Bakarım birazdan... Şu an elim dolu.")
		else:
			await _phone_line(game.player, "Bakmadım daha... Yatağın üstünde uyuyordur herhalde.")
		await _phone_line(phone, "Onu çok özledim. Bir de banyodaki priz gevşekti, kıvılcım çıkarıyordu; bir bak olur mu?", W)
		await _phone_line(game.player, "Tamam tamam, bakarım. İyi geceler.")
		await _phone_line(phone, "İyi geceler canım, öptüm.", W)
		await _phone_line(phone, "Düt... düt... düt...", W)
		return
	var mood := mini(deaths, 4)
	var openers := [
		"Alo... hayatım? Sesini duymak... iyi geldi.",
		"Alo! Dinle beni, lütfen kapatma!",
		"Hayatım, bu gece... bu gece bir şey olacak.",
		"Yine sen... yine aynı telefon. Dinle beni!",
	]
	await _phone_line(game.player, openers[(mood - 1 + loop) % openers.size()] if mood >= 3 else openers[mood - 1])
	await _phone_line(phone, "Canım? Eve geldin mi? Sesin bir tuhaf...", W)
	if rushing:
		await _phone_line(phone, "Neden nefes nefesesin? Koşuyor musun?", W)
		await _phone_line(game.player, "Vakit yok! Birazdan her şey sallanacak!")
	else:
		await _phone_line(game.player, "Geldim, geldim... Sözümü kesme, dinle—")
	# Öğrenilenlerden döngüye göre değişen en fazla iki konu.
	var topics: Array = []
	if _learned("water") or _learned("shock"):
		topics.append(["Banyodaki priz... Sarsıntıda kopup suya düşecek. Kaçağı gidermeliyim.", "Ne diyorsun sen? Prize bak demiştim zaten!"])
	if _learned("wardrobe"):
		topics.append(["Yatak odasındaki dolap... Duvara vidalamam lazım. Matkap nerede?", "Matkap telefonun yanında, vidalar da. Ne oldu ki?"])
	if _learned("brick") or _learned("quake"):
		topics.append(["Deprem olacak. Nasıl bildiğimi sorma, sadece inan bana.", "Deprem mi? Korkutma beni..."])
	if _learned("fire"):
		topics.append(["Yatak odasında yangın çıkacak... Tüp nerede bizde?", "Tüp mutfakta. Sen iyi misin gerçekten?"])
	if _learned("osman_saved"):
		topics.append(["Osman'ı yine kurtaracağım. Söz veriyorum.", "Osman'a ne olacak ki?! Beni korkutuyorsun!"])
	if _learned("bag_incomplete") or _learned("bleed"):
		topics.append(["Çanta... Su, konserve, bandaj, düdük. Hepsi içinde olmalı.", "Deprem çantası mı? Dolabın üstünde duruyor ya."])
	if _learned("rubble"):
		topics.append(["Enkazın altında saatlerce kaldım... Karanlıktı, kimse duymadı.", "Ne enkazı?! Rüya mı gördün?"])
	if topics.is_empty():
		topics.append(["Bu konuşmayı daha önce yaptık. Biliyorum, saçma geliyor...", "Ne demek istiyorsun? İçtin mi sen?"])
	var shown := 0
	var start := loop % topics.size()
	for k in topics.size():
		if shown >= (1 if rushing else 2):
			break
		var t: Array = topics[(start + k) % topics.size()]
		await _phone_line(game.player, t[0])
		await _phone_line(phone, t[1], W)
		shown += 1
	var closers := [
		["Sen de dikkatli ol. Seni seviyorum.", "Ben de seni... Beni ara, olur mu?"],
		["Kapatmam lazım. Hazırlanmalıyım.", "Hazırlanmak mı? Neye?! Alo?"],
		["Bu sefer başaracağım. Başarmak zorundayım.", "Çok korkuyorum... Lütfen kendine dikkat et."],
		["Yeter... Yeter artık! Bitmesi lazım bunun!", "Bağırma! Ne oluyor sana?!"],
	]
	var c: Array = closers[(mood - 1 + loop) % closers.size()]
	await _phone_line(game.player, c[0])
	await _phone_line(phone, c[1], W)
	await _phone_line(phone, "Düt... düt... düt...", W)


func _blackout() -> void:
	game.lights_out = true
	for item in get_tree().get_nodes_in_group("world_items"):
		if not item.lamp_lights.is_empty():
			item.set_light(false)
		if item.kind == "tv":
			item.set_alarm(false)
		item.queue_redraw()
	game.apply_ambient()


func _on_enter_bath() -> void:
	if announced_bath or not _water_live() or state != &"to_bath":
		return
	announced_bath = true
	if not _learned("water"):
		# İlk döngü: ders alınacak hata. Adam cızırtıyı umursamaz, ıslak zeminde kayıp elektrikli suya düşer.
		game.player.input_locked = true
		game.player.velocity = Vector2.ZERO
		await think(game.player, "Bu cızırtı da ne? Neyse... kafa lambası tam karşıda.", 2.2)
		if game.finished:
			return
		await say(game.player, "Ayy— kayıyorum!", 0.7)
		var target: Vector2 = puddle.global_position + Vector2(0, -20)
		var tw := create_tween()
		tw.tween_property(game.player, "global_position", target, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		await tw.finished
		game.player.input_locked = false
		# Su hâlâ elektrikliyse puddle hasarı adamı çarpar; garanti olsun diye doğrudan öldürülür.
		if game.player.active:
			world.message("Elektrikli suya düştün!")
			game.player.die()
	else:
		game.player.input_locked = true
		await say(game.player, "Bu su beni çarpmıştı! Lavabo çatlamış, kopan prizin kabloları suyun içinde...", 2.6)
		await think(game.player, "Önce sigortadan elektriği kesmeliyim. Sigorta kutusu salondaydı.", 3.0)
		game.player.input_locked = false
		# Bu arada kaçak giderildiyse eski ipucunu yazma.
		if state != &"to_bath":
			return
		game.status.text = "Su elektrikli! Önce elektrik kaçağını bul ve gider."
		var box: Area2D = world.find_item("electrical_box")
		if box != null:
			guide.target_room = &"salon"
			guide.target_node = box
			guide.target_offset = Vector2(0, -60)


# Sigorta kutusunda akım varken yanlış bağlantı: "Ah!", çarpılma ve ölüm.
func shock_death() -> void:
	if game.finished or rescue_phase:
		return
	shock_killed = true
	var p: Node2D = game.player
	p.input_locked = true
	p.velocity = Vector2.ZERO
	p.shock = 1.8
	zap_player.play()
	pain_player.play()
	show_bubble(p, "Ah!", false, "", 1.2)
	flash.color = Color(0.85, 0.92, 1.0, 0.7)
	create_tween().tween_property(flash, "color:a", 0.0, 0.8)
	game.camera.shake(0.8, 9.0)
	await get_tree().create_timer(1.0).timeout
	p.die()


func _on_leak_fixed() -> void:
	buzz_player.stop()
	spark_light.enabled = false
	if state != &"to_bath" or world.has_item("flashlight"):
		# Depremden önce onarıldı (ışıklar açık kalır) ya da fener zaten elde.
		say(game.player, "Kaçak giderildi. Banyo artık güvenli.", 2.0)
		return
	state = &"pitch_dark"
	game.pitch_dark = true
	game.apply_ambient()
	buzz_player.stop()
	spark_light.enabled = false
	game.status.text = "Zifiri karanlık. Banyoda el yordamıyla kafa lambasını ara (E)."
	_point_at_flashlight()
	await get_tree().create_timer(0.4).timeout
	await say(game.player, "Tamam... kaçak giderildi.", 1.8)
	if state == &"pitch_dark":
		await think(game.player, "Hiçbir şey göremiyorum. Kafa lambası banyoda bir yerdeydi... ama nerede?", 3.0)


func _on_item_collected(kind: String) -> void:
	# Telefon açılmadan alınan ilk eşya 30 sn hazırlık sayacını başlatır (döngüde bir kez).
	match kind:
		"cat":
			_on_cat_taken()
			return
		"drill":
			game.player.held_tex = null
			game.player.hand_drill = true
			say(game.player, "Matkap tamam." + ("" if world.has_item("nails") else " Vidalar da lazım!"), 1.8)
			return
		"nails":
			game.player.held_tex = null
			game.player.hand_screws = true
			say(game.player, "Vidalar tamam." + ("" if world.has_item("drill") else " Matkap da lazım!"), 1.8)
			return
		"quake_bag":
			game.player.carry_bag = true
			say(game.player, "Deprem çantası! Hemen çıkalım.", 1.8)
			return
	if kind != "flashlight":
		return
	if torch == null:
		_enable_torch()
	# Hikâye yalnız depremden sonraki karanlık aramada ilerler; önceden alınan fener sadece
	# envantere girer (telefon, sayaç ve diğer akış bozulmaz).
	if state in [&"to_bath", &"pitch_dark"]:
		_torch_escape("Kafa lambasını taktım, yandı!")
	elif not quake_begun:
		say(game.player, "Bir kafa lambası! Taktım; nereye baksam önümü aydınlatır.", 2.4)


# Fener eldeyken karanlık arama atlanır: oklar üst kapıyı gösterir, kapıya yaklaşınca Osman'ın sesi gelir.
func _torch_escape(line: String) -> void:
	state = &"escape"
	game.pitch_dark = false
	game.apply_ambient()
	game.status.text = "Kafa lambası takılı: baktığın yeri aydınlatır. Üst kapıya git!"
	guide.target_room = &"salon"
	guide.target_node = null
	guide.target_point = EXIT_POINT
	say(game.player, line, 2.0)


# --- Kedi ve yatak odası yangını --------------------------------------------

func _cat_call() -> void:
	osman_informed = true
	state = &"cat_call"
	meow_player.play()
	meow_clock = 3.2
	cat = world.find_item("cat")
	guide.target_room = &"yatak_odasi"
	guide.target_node = cat
	guide.target_offset = Vector2(0, -70)
	game.status.text = "Bu ses... Osman! Yatak odasına koş."
	_take_control()
	await say(game.player, "Miyav?!", 1.2)
	game.player.input_locked = false
	await think(game.player, "Osman! Kedim yatak odasında kaldı!", 2.6)


func _enter_osman_room() -> void:
	osman_informed = true
	state = &"find_osman"
	game.status.text = "Osman yatağın altında. Yanına git ve [E] ile seslen."
	if is_instance_valid(cat):
		guide.target_room = &"yatak_odasi"
		guide.target_node = cat
		guide.target_offset = Vector2(0, -40)
	await think(game.player, "Osman? Neredesin... Yatağın altında mısın?", 2.4)


# Depremden önce Osman yatakta uyur; depremden sonra yatağın altına saklanır. E ile her seslenişte
# biraz yaklaşır; yeterince çağrılınca dışarı çıkar ve alınabilir.
func interact_osman(item: Area2D) -> void:
	if quake_begun:
		osman_informed = true
	cat = item
	if game.finished or looking or item.collected:
		return
	if not item.under_bed:
		var lines := ["Osman uyuyor... Uyu bakalım oğlum.", "Mışıl mışıl. Keşke ben de uyuyabilsem.", "Mamasını yemiş mi acaba?"]
		say(game.player, lines[randi() % lines.size()], 1.8)
		return
	if osman_calls >= OSMAN_CALLS_NEEDED:
		_take_osman(item)
		return
	if under_view != null:
		return
	_open_under_bed(item)


# Eski birinci şahıs sahne: köşeye geçip çömelir, yatağın altına bakar; her E'de seslenir,
# Osman biraz daha yaklaşır. Yeterince çağrılınca sahne kapanır ve Osman omza atlar.
func _open_under_bed(item: Area2D) -> void:
	looking = true
	var p: Node2D = game.player
	p.input_locked = true
	p.velocity = Vector2.ZERO
	guide.clear()
	var corner: Vector2 = game.ROOMS[&"yatak_odasi"].position + Vector2(140, 164)
	var walk := create_tween()
	walk.tween_property(p, "global_position", corner, 0.45)
	await walk.finished
	p.facing = Vector2.LEFT
	await say(p, "Osman? Yatağın altında mısın?", 1.4)
	p.crouching = true
	await get_tree().create_timer(0.45).timeout
	under_view = UnderBedView.new()
	add_child(under_view)
	under_view.reveal = 1.0 if torch != null and torch.enabled else 0.4
	under_view.cat_forward = 0.0
	await get_tree().create_timer(0.6).timeout
	if under_view == null:
		return
	under_view.say("Osman... orada mısın?")
	blip("man")
	await get_tree().create_timer(1.0).timeout
	if under_view == null:
		return
	meow_player.pitch_scale = 1.15
	meow_player.play()
	under_view.say("Mıyaav... (titriyor)", Color(1, 0.8, 0.5))
	under_view.hint = "[E] Seslen  (0/%d)" % OSMAN_CALLS_NEEDED
	looking = false


func _osman_call_step() -> void:
	if under_view == null or looking or call_cooldown > 0.0 or osman_calls >= OSMAN_CALLS_NEEDED:
		return
	call_cooldown = 0.9
	osman_calls += 1
	under_view.say(CALL_LINES[(osman_calls - 1) % CALL_LINES.size()])
	under_view.hint = "[E] Seslen  (%d/%d)" % [osman_calls, OSMAN_CALLS_NEEDED]
	blip("man")
	var item: Area2D = cat
	await get_tree().create_timer(0.4).timeout
	if under_view == null:
		return
	meow_player.pitch_scale = randf_range(1.0, 1.25)
	meow_player.play()
	var tw := create_tween().set_parallel(true)
	var target_k := minf(1.0, float(osman_calls) / OSMAN_CALLS_NEEDED)
	# Her çağrıda Osman birkaç adım yürür (yürüme animasyonu bu süre boyunca ilerleyerek oynar).
	tw.tween_property(under_view, "cat_forward", target_k, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(item, "approach", target_k, 1.3).set_trans(Tween.TRANS_SINE)
	# Etkileşim alanı da kediyle birlikte yataktan dışarı kayar.
	for child in item.get_children():
		if child is CollisionShape2D:
			tw.tween_property(child, "position:x", target_k * 78.0, 1.3)
	item.hop = 1.0
	tw.tween_property(item, "hop", 0.0, 0.45).set_ease(Tween.EASE_IN)
	if osman_calls >= OSMAN_CALLS_NEEDED:
		if under_view == null:
			return
		looking = true
		under_view.hint = ""
		await get_tree().create_timer(0.8).timeout
		if under_view == null:
			return
		under_view.say("Gel buraya, korkma... gel oğlum...")
		blip("man")
		await get_tree().create_timer(1.1).timeout
		if under_view == null:
			return
		# Yatağın yanındaki dolap sabitlenmemişse konuşma biterken üstüne devrilir.
		var bw := _bed_wardrobe()
		if bw != null and not bw.anchored and not bw.fallen:
			bw.wobbling = true
			game.quake._on_tick()
			under_view.say("Bu gıcırtı... DOLAP!", Color(1, 0.4, 0.3))
			create_tween().tween_property(under_view, "shake", 1.0, 0.5)
			await get_tree().create_timer(0.7).timeout
			thud_player.play()
			pain_player.play()
			under_view.flash = 0.9
			create_tween().tween_property(under_view, "flash", 0.0, 0.5)
			await _tween_prop(under_view, "dark", 1.0, 0.25)
			if under_view != null:
				under_view.queue_free()
				under_view = null
			game.player.crouching = false
			looking = false
			_crush_player(bw)
			return
		await _tween_prop(under_view, "dark", 1.0, 0.4)
		if under_view == null:
			return
		under_view.queue_free()
		under_view = null
		looking = false
		_take_osman(item)


# Osman yatağın altından tamamen çıkar, kısa bir hazırlanıştan sonra yay çizerek omza atlar.
# Çağrılara önce çekingen (bakınıp yavaş yürüyerek), sonra acele ederek gelir: yatağın altından
# koşarak oyuncunun yanına varır ve birlikte kaçmaya başlarlar (Osman yürüyerek peşinden gelir).
func _take_osman(item: Area2D) -> void:
	looking = true
	guide.clear()
	var p: Node2D = game.player
	p.input_locked = true
	p.velocity = Vector2.ZERO
	var cat_pos: Vector2 = item.global_position + Vector2(item.approach * 78.0, 0)
	p.facing = Vector2.LEFT if cat_pos.x < p.global_position.x else Vector2.RIGHT
	p.crouching = true
	show_bubble(p, "Gel oğlum, gel... Hadi!", false, "", 1.2)
	meow_player.pitch_scale = 1.3
	meow_player.play()
	item.z_index = 3
	var side := -1.0 if p.facing.x > 0 else 1.0
	item.jump_to = p.global_position - item.global_position + Vector2(28.0 * side, 10)
	var tw := create_tween()
	tw.tween_property(item, "jump", 1.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	var spot: Vector2 = item.global_position + item.jump_to
	item.under_bed = false
	item.collect()
	_spawn_osman_follower(spot)
	world.add_item("cat")
	world.item_collected.emit("cat")
	p.crouching = false
	p.input_locked = false
	looking = false
	say(p, "Buradasın! Ön kapı kapandı ama seni bırakmam Osman..." if front_blocked else "Buradasın! Hadi Osman, kaçıyoruz!", 2.2 if front_blocked else 1.8)


var osman_follower: Node2D


func _spawn_osman_follower(at: Vector2) -> void:
	game.player.cat_follower = true
	if osman_follower != null:
		return
	osman_follower = OsmanFollower.new()
	osman_follower.story = self
	osman_follower.game = game
	osman_follower.global_position = at
	osman_follower.room = game.current_room
	game.add_child(osman_follower)


func take_extinguisher(item: Area2D) -> void:
	if game.finished:
		return
	if not world.can_add("fire_extinguisher"):
		world.message("Envanter dolu! [F] envanteri aç, [Q] ile bir şey bırak.")
		return
	item.collect()
	world.add_item("fire_extinguisher")
	if has_tool:
		return
	game.player.held_tex = load(ExtinguisherGame.TEX_PIN)
	game.player.input_locked = true
	game.player.velocity = Vector2.ZERO
	guide.clear()
	var minigame := ExtinguisherGame.new()
	pin_game = true
	add_child(minigame)
	await minigame.finished
	pin_game = false
	game.player.held_tex = load(ExtinguisherGame.TEX_NOPIN)
	has_tool = true
	# E'nin aynı karede etkileşime dönüşmemesi için kısa gecikme.
	await get_tree().create_timer(0.25).timeout
	game.player.input_locked = false
	if fire_field.burning_count() > 0:
		_start_spraying()


func _start_spraying() -> void:
	game.player.tool_ready = true


func _on_all_out() -> void:
	game.player.tool_ready = false
	spray_fx.emitting = false
	hiss_player.stop()
	say(game.player, "Söndü... hepsi söndü!", 2.0)
	if not game.finished:
		var osman: Area2D = world.find_item("cat")
		game.status.text = "Yangın söndü!" + ("  Osman yatağın altında, yanına git." if osman != null and osman.under_bed else "")


# Yangından sonraki hedef: (öğrendiyse) matkap → vidalar → vidasız dolaplar → kedi → çanta → salon.
func _after_fire_target() -> Dictionary:
	if _learned("wardrobe") and not _trap_secured():
		if not world.has_item("drill"):
			var d: Area2D = world.find_item("drill")
			if d != null:
				return {"room": &"salon", "node": d, "offset": Vector2(0, -70)}
		if not world.has_item("nails"):
			var n: Area2D = world.find_item("nails")
			if n != null:
				return {"room": &"salon", "node": n, "offset": Vector2(0, -70)}
		if world.has_item("drill") and world.has_item("nails"):
			for w in _trap_wardrobes():
				if not w.anchored:
					return {"room": &"yatak_odasi", "node": w, "offset": Vector2(0, -160)}
	if is_instance_valid(cat) and not cat.collected:
		return {"room": &"yatak_odasi", "node": cat, "offset": Vector2(0, -14) if cat.under_bed else Vector2(0, -70)}
	if _learned("bleed"):
		if not world.has_item("quake_bag"):
			return {"room": &"yatak_odasi", "point": game.ROOM_CENTERS[&"yatak_odasi"], "text": "Deprem çantasını bul."}
		for k in ["food", "water_bottle", "whistle"]:
			if not world.has_item(k):
				return {"room": &"mutfak", "point": game.ROOM_CENTERS[&"mutfak"], "text": "Çantaya yiyecek, su ve düdük koy."}
		if not world.has_item("bandage"):
			return {"room": &"banyo", "point": game.ROOM_CENTERS[&"banyo"], "text": "Çantaya sargı bezi koy."}
		return {"room": game.current_room, "point": game.player.global_position, "text": "Çanta hazır. Hemen çık!"}
	return {"room": &"salon", "point": game.ROOM_CENTERS[&"salon"], "text": "Osman'ı al ve buradan çık!"}


func _update_after_fire_guide() -> void:
	var t := _after_fire_target()
	guide.target_room = t.room
	guide.target_node = t.get("node", null)
	guide.target_offset = t.get("offset", Vector2.ZERO)
	if t.has("point"):
		guide.target_point = t.point
	var text := "Kediyi bul."
	if guide.target_node != null:
		match guide.target_node.kind:
			"drill": text = "Matkap ve vida bul."
			"nails": text = "Matkap ve vida bul."
			"wardrobe": text = "Dolabın önünde E: duvara vidala."
			"quake_bag": text = "Deprem çantasını bul."
	elif t.has("text"):
		text = t.text
	game.status.text = "Yangın söndü!  " + text


func _trap_wardrobes() -> Array:
	var list := []
	for item in world.get_children():
		if item is Area2D and item.kind == "wardrobe" and item.trap:
			list.append(item)
	return list


func _trap_secured() -> bool:
	for w in _trap_wardrobes():
		if not w.anchored:
			return false
	return true


# E ile dolap: matkap+vida varsa vidalar (animasyon + ses); yalnız biri varsa uyarır.
func try_anchor(item: Area2D) -> bool:
	if item.kind != "wardrobe" or not item.trap or item.anchored or item.fallen or drilling:
		return false
	var has_drill: bool = world.has_item("drill")
	var has_screws: bool = world.has_item("nails")
	if not has_drill and not has_screws:
		return false
	if not has_screws:
		say(game.player, "Vidalar olmadan matkap işe yaramaz... Vidalar telefon masasındaydı.", 2.4)
		return true
	if not has_drill:
		say(game.player, "Vidalar tamam ama matkap lazım.", 2.0)
		return true
	if world.equipped != "drill":
		world.equip("drill")
	_drill_wardrobe(item)
	return true


func _drill_wardrobe(item: Area2D) -> void:
	drilling = true
	game.player.input_locked = true
	game.player.velocity = Vector2.ZERO
	world.message("Dolap duvara vidalanıyor...")
	# Mini oyun: her vida için ucu hizala (E) ve basılı tutarak sık; vidalar dolapta tek tek belirir.
	var minigame := DrillGame.new()
	minigame.screw_done.connect(func(n: int):
		item.screws_shown = n
		item.queue_redraw())
	add_child(minigame)
	await minigame.finished
	await get_tree().create_timer(0.25).timeout
	item.screws_shown = 4
	item.anchored = true
	world.consume("nails")
	drilling = false
	game.player.input_locked = false
	if _trap_secured():
		game.player.hand_drill = false
		game.player.hand_screws = false
		await say(game.player, "Tamam! Dolap duvara vidalı.", 2.0)
	else:
		await say(game.player, "Biri tamam. Şimdi diğer dolap.", 1.6)


# Kedi yatağın altında: köşeye geçip çömelir, birinci şahıs görünümde kediyi görür; o anda sarsıntı
# sertleşir. Dolaplar vidalı değilse biri başına yıkılır (oyuncu köşede, dolabın düşme alanındadır).
func look_under_bed(item: Area2D) -> void:
	if looking or game.finished:
		return
	looking = true
	cat = item
	var p: Node2D = game.player
	p.input_locked = true
	p.velocity = Vector2.ZERO
	guide.clear()
	var corner: Vector2 = game.ROOMS[&"yatak_odasi"].position + Vector2(140, 164)
	var walk := create_tween()
	walk.tween_property(p, "global_position", corner, 0.45)
	await walk.finished
	p.facing = Vector2.LEFT
	await say(p, "Osman? Yatağın altında mısın?", 1.6)
	# Çömelme animasyonu.
	p.crouching = true
	p.queue_redraw()
	await get_tree().create_timer(0.55).timeout
	var view := UnderBedView.new()
	add_child(view)
	await get_tree().create_timer(0.7).timeout
	view.say("Osman... orada mısın?")
	blip("man")
	await get_tree().create_timer(1.3).timeout
	meow_player.pitch_scale = 1.15
	meow_player.play()
	view.say("Mıyaav... (titriyor)", Color(1, 0.8, 0.5))
	create_tween().tween_property(view, "reveal", 1.0, 1.0)
	await get_tree().create_timer(1.5).timeout
	view.say("Gel buraya, korkma... gel kızım...")
	blip("man")
	create_tween().tween_property(view, "cat_forward", 0.55, 2.4)
	await get_tree().create_timer(1.3).timeout
	# Tam o anda sallantı sertleşir.
	trap_done = true
	game.quake._on_tick()
	game.status.text = "Sarsıntı şiddetleniyor!"
	var walls := _trap_wardrobes()
	for w in walls:
		w.wobbling = true
	create_tween().tween_property(view, "shake", 1.0, 1.4)
	view.say("Sarsıntı şiddetleniyor!", Color(1, 0.5, 0.4))
	await get_tree().create_timer(1.6).timeout
	if _trap_secured():
		view.say("Vidaladığım dolaplar dayanıyor!", Color(0.6, 1, 0.6))
		create_tween().tween_property(view, "shake", 0.15, 1.2)
		create_tween().tween_property(view, "cat_forward", 1.0, 0.9)
		meow_player.play()
		await get_tree().create_timer(1.4).timeout
		await _tween_prop(view, "dark", 1.0, 0.4)
		view.queue_free()
		for w in walls:
			w.wobbling = false
			w.queue_redraw()
		p.crouching = false
		p.carry_cat = true
		world.add_item("cat")
		item.collect()
		p.input_locked = false
		looking = false
		await say(p, "Yakaladım seni! Gel Osman, buradan çıkıyoruz.", 2.2)
		return
	# Vidasız dolap: yukarıdan gıcırtı, sonra başa çarpma — ekran kırmızı, sonra karanlık.
	view.say("Bu gıcırtı... DOLAP!", Color(1, 0.4, 0.3))
	await get_tree().create_timer(0.55).timeout
	thud_player.play()
	pain_player.play()
	view.flash = 0.9
	create_tween().tween_property(view, "flash", 0.0, 0.5)
	await _tween_prop(view, "dark", 1.0, 0.25)
	await get_tree().create_timer(0.4).timeout
	view.queue_free()
	p.crouching = false
	looking = false
	await _crush_player()


# Zamanlı ara sahne kontrolü alırken: çömelme (C) ve açık envanter paneli bırakılır; yoksa C'yi
# bırakmak ya da paneli kapatmak sahnenin ortasında hareket kilidini açar.
func _take_control() -> void:
	if safety != null:
		safety._leave_cover("")
	if world.inventory_ui != null:
		world.inventory_ui.force_close()
	game.player.input_locked = true
	game.player.velocity = Vector2.ZERO


func _tween_prop(obj: Object, prop: String, to: float, seconds: float) -> void:
	var tw := create_tween()
	tw.tween_property(obj, prop, to, seconds)
	await tw.finished


# Osman'ın yatağının hemen yanındaki dolap (yatağa en yakın tuzak dolap).
func _bed_wardrobe() -> Area2D:
	var bed: Area2D = world.find_item("bed")
	var best: Area2D = null
	for w in _trap_wardrobes():
		if bed == null or best == null or w.global_position.distance_to(bed.global_position) < best.global_position.distance_to(bed.global_position):
			best = w
	return best


func _crush_player(target: Area2D = null) -> void:
	crushed_player = true
	game.player.input_locked = true
	var walls := _trap_wardrobes()
	var nearest: Area2D = walls[0]
	for w in walls:
		if w.global_position.distance_to(game.player.global_position) < nearest.global_position.distance_to(game.player.global_position):
			nearest = w
	if target != null:
		nearest = target
	for w in walls:
		if w != nearest:
			w.topple(false)
	for item in world.get_children():
		if item is Area2D and item.kind == "wardrobe" and item.room == &"salon":
			item.topple(false)
	await nearest.topple(true)
	thud_player.play()
	game.player.self_modulate = Color(1, 1, 1, 0)
	game.player.held_tex = null
	game.player.carry_cat = false
	game.player.carry_bag = false
	game.player.hand_drill = false
	game.player.hand_screws = false
	game.camera.shake(0.6, 18.0)
	game.status.text = "Dolabın altında kaldın..."
	game.player.die()


# Osman kurtarıldı: (kalıcı bilgi) kaydı, yangın bu andan sonra başlar.
func _on_osman_rescued() -> void:
	if osman_rescued:
		return
	osman_rescued = true
	var learned: Dictionary = Engine.get_meta(LEARN_KEY, {}) if Engine.has_meta(LEARN_KEY) else {}
	learned["osman_saved"] = true
	Engine.set_meta(LEARN_KEY, learned)
	state = &"rescue"
	game.status.text = "Osman kucağında!"
	say(game.player, "Seni buldum Osman! Hadi, çıkıyoruz!", 2.0)


# Osman kurtarılınca 20 sn: oyuncu serbest, sarsıntı giderek artar (son 5 sn yoğun),
# düşen parçalar öldürmez; sıfırda nerede olursa olsun enkaz sahnesi başlar.
const RESCUE_TIME := 20.0
var rescue_left := -1.0
var rescue_tick := 0.0


func _abort_under_view() -> void:
	under_view.queue_free()
	under_view = null
	looking = false
	game.player.crouching = false
	game.player.input_locked = false
	say(game.player, "Alevler! Her yer yanıyor!", 2.0)


# Tüpsüz biçimde alev hattının yatak tarafına geçen oyuncu: arkasındaki yangın onu köşeye sıkıştırır.
func _check_fire_trap() -> void:
	if rescue_phase or fire_trap or has_tool or not fire_field.active or game.finished or game.current_room != &"yatak_odasi":
		return
	var local_x: float = game.player.global_position.x - game.ROOMS[&"yatak_odasi"].position.x
	if local_x > fire_field.WALL_X - 50.0:
		return
	fire_trap = true
	fire_field.close_in()
	game.status.text = "Alevler arkandan yayılıyor!"
	await get_tree().create_timer(0.6).timeout
	await think(game.player, "Arkamda... alevler! Yangın tüpünü almadım!", 2.4)
	if not game.finished:
		await say(game.player, "Hayır, hayır... köşeye sıkıştım!", 2.2)


# Sehpadaki şişeler devrilip kırılır; camlar sehpanın hemen önüne, dar bir şeride saçılır.
func _break_bottles() -> void:
	var bottles: Array = []
	for item in world.get_children():
		if item is Area2D and item.kind == "alcohol" and not item.collected:
			bottles.append(item)
	if bottles.is_empty():
		return
	var center := Vector2.ZERO
	for b in bottles:
		center += b.global_position
		b.collect()
	center /= bottles.size()
	# Sehpanın sağ kenarından yere: koltuğun altına değil, açık zemine düşer.
	glass_rect = Rect2(center + Vector2(40, -8), Vector2(52, 18))
	var patch := GlassPatch.new()
	patch.area = Rect2(Vector2.ZERO, glass_rect.size)
	patch.position = glass_rect.position
	world.add_child(patch)
	crash_player.pitch_scale = 1.6
	crash_player.play()


# Cama basan oyuncu: "Ah!", can kaybı (her adımda değil, kısa aralıklarla).
func _update_glass(delta: float) -> void:
	glass_cd = maxf(0.0, glass_cd - delta)
	if rescue_phase or glass_rect.size == Vector2.ZERO or game.finished or game.current_room != &"salon":
		return
	var p: Node2D = game.player
	if not p.active or not glass_rect.grow(4.0).has_point(p.global_position) or glass_cd > 0.0:
		return
	glass_cd = 0.75
	glass_hurt_at = Time.get_ticks_msec() / 1000.0
	if safety != null:
		safety.ah_player.pitch_scale = randf_range(0.95, 1.1)
		safety.ah_player.play()
	show_bubble(p, ["Ah!", "Ahh! Cam!", "Ayağım!"][randi() % 3], false, "", 0.9)
	p.take_damage(7)


func _start_rescue_countdown() -> void:
	if rescue_phase or collapsing:
		return
	rescue_phase = true
	rescue_left = RESCUE_TIME
	rescue_tick = 0.3
	game.player.invulnerable = true
	burn_left = 0.0
	body_fire.emitting = false
	game.quake.timer.stop()
	if safety != null:
		safety.head_hit_at = -1.0
		safety.head_chunk = {}
		safety.brick = {}
	_rescue_monologue()


func _rescue_monologue() -> void:
	var lacking: bool = not (world.has_item("food") and world.has_item("water_bottle"))
	var lines: Array
	if lacking:
		lines = [[2.0, "Bir dakika... Mutfakta konserveler vardı!"], [7.0, "Su da vardı... Keşke çantaya koysaydım..."],
			[12.0, "Keşke önceden hazırlasaydım! Neden beklemedim ki?!"]]
		if loop > 0:
			lines.append([16.0, "Her seferinde aynı şey! Hazırlıksız yakalanıyorum!"])
	else:
		lines = [[2.0, "Erzak yanımda... Şimdi sadece buradan çıkmalıyım!"], [10.0, "Dayan Osman, dayan!"]]
		if not _trap_secured():
			lines.append([16.0, "Keşke dolabı da duvara taksaydım..."])
	for entry in lines:
		while rescue_phase and RESCUE_TIME - rescue_left < entry[0]:
			await get_tree().process_frame
		if not rescue_phase or game.finished:
			return
		say(game.player, entry[1], 2.6)


func _update_rescue(delta: float) -> void:
	if not rescue_phase or collapsing or game.finished:
		return
	rescue_left -= delta
	var k := clampf(1.0 - rescue_left / RESCUE_TIME, 0.0, 1.0)
	var final := rescue_left <= 5.0
	game.camera.intensity = lerpf(0.35, 0.85, k) + (0.15 if final else 0.0)
	var secs := ceili(maxf(rescue_left, 0.0))
	game.countdown.text = "%d" % secs
	game.countdown.modulate = Color(1, 0.3, 0.25) if final else Color(1, 0.75, 0.4)
	rescue_tick -= delta
	if rescue_tick <= 0.0:
		rescue_tick = randf_range(0.35, 0.6) if final else randf_range(1.3, 2.1)
		game.camera.shake(1.2, lerpf(8.0, 18.0, k) + (6.0 if final else 0.0))
		crash_player.pitch_scale = randf_range(0.7, 1.15)
		crash_player.volume_db = -10.0 if final else -16.0
		crash_player.play()
		if safety != null:
			safety._ambient_impact(game.player.global_position + Vector2(randf_range(-120, 120), randf_range(-60, 60)))
	if rescue_left <= 0.0:
		_collapse()


func _on_cat_taken() -> void:
	game.player.carry_cat = true
	if not fire_trap and not has_tool:
		_check_fire_trap()
	if fire_trap:
		# Yangın tüpü alınmadan doğrudan Osman'a gidildiyse alev kapanı sürer.
		osman_rescued = true
		say(game.player, "Seni aldım Osman... ama nereye kaçacağız?!", 2.2)
		return
	_on_osman_rescued()
	if trap_done or not quake_begun:
		return
	trap_done = true
	# Artçı sarsıntı ve dolap devrilmesi görülür; enkaza düşme yalnız sayaç sıfırlandığında olur.
	game.quake._on_tick()
	game.status.text = "Artçı sarsıntı!"
	var walls := _trap_wardrobes()
	for w in walls:
		w.wobbling = true
	await get_tree().create_timer(0.35).timeout
	if not rescue_phase:
		return
	for w in walls:
		w.wobbling = false
		if not w.anchored:
			w.topple(false)
		else:
			w.queue_redraw()
	for item in world.get_children():
		if item is Area2D and item.kind == "wardrobe" and item.room == &"salon" and not item.anchored:
			item.topple(false)


func _collapse() -> void:
	if collapsing:
		return
	collapsing = true
	rescue_phase = false
	game.countdown.text = ""
	state = &"rubble"
	guide.clear()
	_take_control()
	# Son büyük çöküş: sarsıntı normalden çok daha şiddetli; sarsılırken ekran kararır, sonra enkaz.
	crash_player.volume_db = 0.0
	crash_player.play()
	game.camera.intensity = 1.0
	game.camera.shake(3.4, 52.0)
	say(game.player, "Her şey yıkılıyor!", 1.2)
	for i in 6:
		get_tree().create_timer(0.25 + i * 0.35).timeout.connect(func():
			if safety != null:
				safety._ambient_impact(game.player.global_position + Vector2(randf_range(-140, 140), randf_range(-90, 60)))
			thud_player.pitch_scale = randf_range(0.6, 0.9)
			thud_player.play())
	var dark := create_tween()
	dark.tween_interval(0.9)
	dark.tween_property(fade_rect, "color:a", 1.0, 1.7).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(1.6).timeout
	crash_player.pitch_scale = 0.7
	crash_player.play()
	await dark.finished
	fire_field.roar.stop()
	# Yalnız gerçekten toplanan eşyalar enkaza taşınır; eksik olan asla verilmez.
	var carried := {}
	for id in ["flashlight", "whistle", "food", "water_bottle", "bandage"]:
		carried[id] = world.has_item(id) or (id == "flashlight" and torch != null)
	var learned: Dictionary = Engine.get_meta(LEARN_KEY, {}) if Engine.has_meta(LEARN_KEY) else {}
	var prepared: bool = carried.bandage and carried.food and carried.water_bottle and carried.whistle
	var repeat := 0
	if not prepared:
		learned["bag_incomplete"] = true
		if learned.get("rubble", false):
			repeat = int(Engine.get_meta(UNPREPARED_KEY, 0)) + 1
			Engine.set_meta(UNPREPARED_KEY, repeat)
	learned["rubble"] = true
	Engine.set_meta(LEARN_KEY, learned)
	var ending := RubbleEnding.new()
	ending.story = self
	ending.items = carried
	ending.unprepared_repeat = repeat
	ending.has_bag = carried.food and carried.water_bottle and carried.bandage and carried.whistle
	# Osman yalnız yanına alındıysa enkazda da onunla.
	ending.has_cat = game.player.carry_cat or world.has_item("cat")
	add_child(ending)
	game.camera.stop_shake()
	await get_tree().create_timer(0.8).timeout
	game.quake.stop()
	game.finished = true


func _point_to_exit() -> void:
	if state != &"after_fire":
		return
	guide.target_room = &"salon"
	guide.target_node = null
	guide.target_point = EXIT_POINT if game.gas_off else world.get_event_point(&"salon", &"gas_valve")


func can_exit() -> bool:
	return phase == 2 and quake_begun and not game.finished and not collapsing and exit_unlocked() and not front_blocked


func exit_unlocked() -> bool:
	return world.has_item("flashlight") or torch != null or osman_informed or game.player.carry_cat


# Kapı etkileşimi olur ama çıkış engellenir: Osman yoksa dönüşümlü iç sesler (her karede değil).
func exit_block_text() -> String:
	if exit_cooldown > 0.0:
		return game.status.text
	exit_cooldown = 2.2
	var line: String
	if not quake_begun:
		line = "Gece yarısı nereye gideceğim? Evde işim var."
	elif front_blocked:
		line = ["Kapı enkazla kapanmış! Taşlar kıpırdamıyor...",
			"Buradan çıkış yok... Osman'la güvenli bir köşe bulmalıyım.",
			"Sargı bezi, su, düdük... Enkaza hazırlanmalıyım."][exit_line % 3]
		exit_line += 1
	elif not exit_unlocked():
		line = ["Zifiri karanlık, merdivenleri göremem... Önce bir kafa lambası bulmalıyım.",
			"Bu karanlıkta çıkamam. Banyoda bir kafa lambası vardı...",
			"Dur... Osman nerede? Onu bilmeden gidemem."][exit_line % 3]
		exit_line += 1
	else:
		line = "Kapı sıkışmış! Kasa eğilmiş... açılmıyor!"
	say(game.player, line, 2.0)
	return line


# Evden süre içinde çıkış: dışarı sahnesi (karakter önden, yalnız monolog ve seçimler).
func exit_house() -> void:
	if left_house or game.finished:
		return
	left_house = true
	phase = 3
	game.countdown.text = ""
	var cat_saved: bool = game.player.carry_cat or world.has_item("cat")
	game.player.input_locked = true
	guide.clear()
	ring_player.stop()
	for t in bubbles.keys():
		clear_bubble(t)
	game.quake.stop()
	game.finished = true
	var o := Outside.new()
	o.story = self
	o.cat_saved = cat_saved
	o.wife_safe = wife_safe
	add_child(o)


# Hayatta kalınan son: Osman ya da eşi kurtarılamadıysa önce seçim (döngüyü yeniden başlat / kabul et).
func offer_restart_or_accept(cat_saved: bool, wife_ok: bool, where: String) -> void:
	var pick := await choose("Ne yapacaksın?", ["Döngüyü yeniden başlat — onlar için bir şans daha", "Bu sonu kabul et"])
	if pick == 0:
		die_from("sacrifice")
	else:
		show_ending(true, cat_saved, wife_ok, where)


func after_rubble_rescue(cat_saved: bool) -> void:
	if cat_saved and wife_safe:
		show_ending(true, cat_saved, wife_safe, "rubble")
	else:
		offer_restart_or_accept(cat_saved, wife_safe, "rubble")


func show_ending(_survived: bool, cat_saved: bool, wife_ok: bool, where: String) -> void:
	var scr := Outside.EndingScreen.new()
	scr.story = self
	if cat_saved and wife_ok:
		scr.title = "HEPİMİZ HAYATTAYIZ"
	elif cat_saved:
		scr.title = "OSMAN'LA BİRLİKTE"
	elif wife_ok:
		scr.title = "İKİMİZ"
	else:
		scr.title = "YAPAYALNIZ"
	scr.lines = [
		"Evden zamanında çıktın." if where == "outside" else "Enkazdan kurtarıldın.",
		"Osman: " + ("seninle, hayatta." if cat_saved else "evde kaldı, kurtarılamadı."),
		"Eşin: " + ("açık alana çıktı, hayatta." if wife_ok else "depremde hayatını kaybetti."),
	]
	add_child(scr)


func restart_all() -> void:
	reset_loop()
	for k in [UNPREPARED_KEY, TITLE_KEY]:
		if Engine.has_meta(k):
			Engine.remove_meta(k)
	get_tree().reload_current_scene()


func _on_player_died() -> void:
	Engine.set_meta(LOOP_KEY, loop + 1)
	var cause := ""
	if shock_killed:
		cause = "shock"
	elif Time.get_ticks_msec() / 1000.0 - glass_hurt_at < 1.2:
		cause = "glass"
	elif crushed_player:
		cause = "wardrobe"
	elif safety != null and safety.brick_killed:
		cause = "brick"
	elif burn_left > 0.0:
		cause = "fire"
	elif game.current_room == &"banyo" and _water_live():
		cause = "water"
	elif safety != null and safety.recently_hurt():
		cause = "quake"
	elif game.current_room == &"yatak_odasi" and fire_field.active:
		cause = "fire"
	Engine.set_meta(DEATH_KEY, cause)
	# Elektrik dışındaki ölümlerde karakter gözleri kapalı yere yığılır (dolap altındaki görünmez kalır).
	if cause not in ["water", "shock"] and not crushed_player:
		game.player.fall_dead()
		game.player.landed.connect(func():
			thud_player.play()
			game.camera.shake(0.3, 5.0)
			if safety != null:
				safety._ambient_impact(game.player.global_position + Vector2(game.player.fall_dir * 50.0, 0)), CONNECT_ONE_SHOT)
	if cause != "":
		var learned: Dictionary = Engine.get_meta(LEARN_KEY, {}) if Engine.has_meta(LEARN_KEY) else {}
		learned[cause] = true
		Engine.set_meta(LEARN_KEY, learned)
	body_fire.emitting = false
	buzz_player.stop()
	ring_player.stop()
	guide.clear()
	for target in bubbles.keys():
		clear_bubble(target)
	if game.current_room == &"banyo" and _water_live():
		zap_player.play()
		scream_player.play()
		game.player.shock = 1.8
		game.camera.shake(1.6, 7.0)
		flash.color.a = 0.6
		create_tween().tween_property(flash, "color:a", 0.0, 1.0)
	game.status.text = "ÖLDÜN — Zaman döngüsü yeniden başlıyor..."


func can_take_tools() -> bool:
	return _learned("wardrobe")


func _last_death() -> String:
	return Engine.get_meta(DEATH_KEY, "") if Engine.has_meta(DEATH_KEY) else ""


func _learned(cause: String) -> bool:
	return Engine.has_meta(LEARN_KEY) and Engine.get_meta(LEARN_KEY).get(cause, false)


# Konuşma efekti: baloncuk yazıldıkça kısa sesler; erkek alçak, kadın yüksek tonda.
func blip(voice: String) -> void:
	var base: float = {"man": 0.8, "wife": 1.55, "cat": 2.2, "rescuer": 0.95}.get(voice, 1.0)
	blip_player.pitch_scale = base * randf_range(0.88, 1.12)
	blip_player.volume_db = -20.0 if voice == "rescuer" else -12.0
	blip_player.play()


func _point_at_flashlight() -> void:
	guide.target_room = &"banyo"
	guide.target_node = null
	guide.target_point = game.ROOM_CENTERS[&"banyo"]


# --- Karanlıkta fener arama ---------------------------------------------------------

func search_active() -> bool:
	return state == &"pitch_dark" or (state == &"to_bath" and not _water_live())


func can_fix_leak() -> bool:
	return _learned("water")


func search(item: Area2D) -> void:
	if searching or game.finished:
		return
	var spot: String = item.search_spot
	if searched.has(spot):
		world.message("Burayı zaten aradım.")
		return
	searching = true
	game.player.input_locked = true
	game.player.velocity = Vector2.ZERO
	world.message("Karanlıkta el yordamıyla arıyorsun: " + spot + "...")
	for k in 3:
		sounds_rustle()
		await get_tree().create_timer(0.35).timeout
	searched[spot] = true
	searching = false
	game.player.input_locked = false
	if spot == flash_spot:
		world.add_item("flashlight")
		_on_item_collected("flashlight")
		return
	var finds: Array = SEARCH_FINDS.get(spot, ["Hiçbir şey."])
	if spot == "rezervuar":
		squeak_player.play()
	say(game.player, finds[randi() % finds.size()], 2.2)


func sounds_rustle() -> void:
	blip_player.pitch_scale = randf_range(0.35, 0.5)
	blip_player.volume_db = -10.0
	blip_player.play()


# --- Lavabonun çatlaması ve su ---------------------------------------------------------

func _on_quake_started(first: bool) -> void:
	if not first:
		return
	# İlk sarsıntıda salondaki dolap devrilip kırılır: kıymıklar, toz, saçılan tahtalar.
	for item in world.get_children():
		if item is Area2D and (item.kind == "wardrobe" or item.style == "bookshelf") and item.room == &"salon" and not item.fallen:
			item.topple(false)
			get_tree().create_timer(0.3).timeout.connect(func(): thud_player.play())
	_wreck_kitchen()
	_break_bottles()
	# Yatak odasında soba devrilir; yangın sobadan başlayıp yavaş yavaş yayılır (iki yolda da).
	var heater: Area2D = world.find_item("heater")
	if heater != null:
		heater.toppled = true
		heater.queue_redraw()
	fire_field.ignite(heater.global_position if heater != null else Vector2.ZERO)
	if has_tool:
		_start_spraying()
	var osman: Area2D = world.find_item("cat")
	if osman != null and not osman.collected:
		osman.under_bed = true
		osman.caption = "Osman (yatağın altında)"
		osman.queue_redraw()
	if puddle == null:
		return
	crack_player.play()
	# İlk damladan itibaren görünen su elektriklidir; yayılma 1,5 saniyede tamamlanır.
	puddle.flood = 0.02
	water_player.play()
	create_tween().tween_property(puddle, "flood", 1.0, 1.5).set_ease(Tween.EASE_OUT)


# Elde tutulan eşya görseli ve işlevi: fener yalnız eldeyken yanar; matkap/vida/tüp eldeyse görünür.
func _apply_equipment() -> void:
	var p: Node2D = game.player
	if crushed_player or game.finished:
		return
	var eq: String = world.equipped
	p.hand_drill = eq == "drill"
	p.hand_screws = eq == "nails"
	# Fener artık kafa lambası: elde tutulmaz, sahip olunduğu sürece başta takılıdır.
	p.hand_flashlight = false
	p.headlamp = world.has_item("flashlight")
	if eq == "fire_extinguisher":
		p.held_tex = load(ExtinguisherGame.TEX_NOPIN if has_tool else ExtinguisherGame.TEX_PIN)
	else:
		p.held_tex = null
	if torch != null:
		# Kafa lambası takılıyken ne olursa olsun yanar; ışıklar açıkken yumuşak, karanlıkta tam güç.
		torch.enabled = p.headlamp
		p.headlamp_on = torch.enabled
	p.tool_ready = fire_field.active and eq == "fire_extinguisher" and has_tool


# İlk sarsıntıda mutfak dağılır: buzdolabı yan yatar, sandalyeler devrilir, düdük yere düşer,
# tabaklar kırılıp yere saçılır.
func _wreck_kitchen() -> void:
	var origin: Vector2 = game.ROOMS[&"mutfak"].position
	for item in world.get_children():
		if not (item is Area2D) or item.room != &"mutfak":
			continue
		match item.kind:
			"fridge":
				item.sprite_rotation = -PI * 0.5
				item.draw_offset = Vector2(-12, 74)
				item.toppled = true
			"chair":
				item.sprite_rotation = PI * 0.5 if item.position.x < origin.x + 330 else -PI * 0.5
				item.draw_offset = Vector2(0, 9)
			"whistle":
				item.position = origin + Vector2(520, 150)
				item.draw_offset = Vector2.ZERO
		item.queue_redraw()
	for spot in [Vector2(150, 120), Vector2(300, 150), Vector2(420, 110)]:
		var shards = load("res://scenes/decor.tscn").instantiate()
		shards.world = world
		shards.room = &"mutfak"
		shards.style = "shards"
		shards.position = origin + spot
		world.add_child(shards)
		shards.set_room_active(game.current_room == &"mutfak")


func _update_water_sound() -> void:
	if puddle == null or not water_player.playing:
		return
	var d: float = game.player.global_position.distance_to(puddle.global_position)
	var near := clampf(1.0 - d / 520.0, 0.0, 1.0)
	if game.current_room != &"banyo":
		near *= 0.35
	water_player.volume_db = lerpf(-40.0, -6.0, near)


# --- Deprem çantası ve erzak --------------------------------------------------------------

func found_bag(item: Area2D) -> void:
	item.holds_bag = false
	world.add_item("quake_bag")
	game.player.carry_bag = true
	game.player.input_locked = true
	await say(game.player, "İşte deprem çantası!", 1.6)
	game.camera.shake(0.5, 4.0)
	await say(game.player, "BOŞ MU?! Bomboş! Hiç doldurmamışım bunu!", 2.4)
	await think(game.player, "Sakin... Yiyecek, su, düdük... ve sargı bezi lazım.", 2.8)
	game.player.input_locked = false


func bag_complete() -> bool:
	for k in ["quake_bag", "food", "water_bottle", "whistle", "bandage"]:
		if not world.has_item(k):
			return false
	return true


func _cat_meow() -> void:
	var p: AudioStreamPlayer = meow_players[randi() % meow_players.size()]
	p.pitch_scale = randf_range(0.95, 1.08)
	p.play()
	var bubble := Bubble.new()
	bubble.story = self
	bubble.anchor = game.player
	bubble.anchor_offset = Vector2(-26, -86)
	bubble.text = ["Miyav~", "Mrrr...", "Miyaav!", "Mıı..."][randi() % 4]
	bubble.lifetime = 1.4
	bubble.voice = "cat"
	overlay.add_child(bubble)


# --- Ölüm: animasyon + geri saran saat ---------------------------------------------------

func death_sequence() -> void:
	var cause: String = _last_death()
	# Ekran hemen kararmaz: önce yere yığılan beden bir an görünür.
	if cause in ["water", "shock"]:
		await get_tree().create_timer(1.9).timeout
	elif crushed_player:
		await get_tree().create_timer(1.1).timeout
	else:
		await get_tree().create_timer(2.2).timeout
	var clock := RewindClock.new()
	clock.deaths = deaths + 1
	add_child(clock)
	await clock.done


func die_from(cause: String) -> void:
	Engine.set_meta(LOOP_KEY, loop + 1)
	Engine.set_meta(DEATH_KEY, cause)
	var learned: Dictionary = Engine.get_meta(LEARN_KEY, {}) if Engine.has_meta(LEARN_KEY) else {}
	learned[cause] = true
	Engine.set_meta(LEARN_KEY, learned)
	var clock := RewindClock.new()
	clock.deaths = deaths + 1
	add_child(clock)
	await clock.done
	get_tree().reload_current_scene()


# --- Sürekli güncellemeler ---------------------------------------------------

func _process(delta: float) -> void:
	if game.current_room != last_room:
		var previous := last_room
		last_room = game.current_room
		if last_room == &"banyo":
			_on_enter_bath()
		elif previous == &"salon" and last_room == &"yatak_odasi" and quake_begun and not front_blocked \
				and not left_house and not game.finished:
			_block_front_door()
		elif previous == &"yatak_odasi" and last_room == &"salon" and quake_begun and not aftershock_done \
				and (game.player.cat_follower or game.player.carry_cat or world.has_item("cat")):
			_aftershock_debris()
	_update_water_sound()
	_apply_equipment()
	dim_light.enabled = game.lights_out and (torch == null or not torch.enabled)
	if game.player.carry_cat and not game.finished:
		meow_timer -= delta
		if meow_timer <= 0.0:
			meow_timer = randf_range(9.0, 16.0)
			_cat_meow()
	_update_buzz()
	_update_spark()
	_update_torch(delta)
	if state == &"escape" and game.current_room == &"salon" \
			and game.player.global_position.distance_to(EXIT_POINT) < CAT_TRIGGER_RADIUS:
		_cat_call()
	elif state == &"cat_call":
		meow_clock -= delta
		if meow_clock <= 0.0:
			meow_clock = 3.5
			meow_player.play()
		if game.current_room == &"yatak_odasi":
			_enter_osman_room()
	_update_phases(delta)
	_update_glass(delta)
	_check_fire_trap()
	# Köşeye sıkışmışken alevler yaklaşınca yatak altı sahnesi kapanır: karakter yangını görür.
	if fire_trap and under_view != null and not game.finished and osman_calls < OSMAN_CALLS_NEEDED:
		var near: Vector2 = fire_field.nearest_burning(game.player.global_position)
		if near != Vector2.ZERO and near.distance_to(game.player.global_position) < 70.0:
			_abort_under_view()
	_update_rescue(delta)
	call_cooldown = maxf(0.0, call_cooldown - delta)
	exit_cooldown = maxf(0.0, exit_cooldown - delta)
	_update_spray(delta)
	_update_burning(delta)
	if state == &"after_fire" and not game.finished:
		_update_after_fire_guide()


func _update_spray(delta: float) -> void:
	var player: Node2D = game.player
	var spraying: bool = fire_field.active and has_tool and world.equipped == "fire_extinguisher" and player.active and not player.input_locked \
		and (Input.is_action_pressed("interact") or player.mouse_interact_held)
	var aim := _aim_direction(player)
	spray_fx.global_position = player.nozzle_position()
	spray_fx.direction = aim
	spray_fx.emitting = spraying
	if spraying:
		if not hiss_player.playing:
			hiss_player.play()
		fire_field.spray(player.nozzle_position(), aim, delta)
	elif hiss_player.playing:
		hiss_player.stop()
	if fire_field.active and has_tool and world.equipped == "fire_extinguisher" and game.current_room == &"yatak_odasi":
		var left: int = fire_field.burning_count()
		game.status.text = "E / sol tık BASILI tut: alevlere püskürt!   Kalan alev: %d" % left


func _water_live() -> bool:
	return puddle != null and puddle.water_is_live()


func _update_buzz() -> void:
	# Elektrikli suyun cızırtısı banyoya yaklaştıkça yükselir.
	if puddle == null or game.finished or not _water_live():
		if buzz_player.playing:
			buzz_player.stop()
		return
	# Cızırtı yalnız banyoda ve banyo kapısının hemen önünde duyulur.
	var distance: float = game.player.global_position.distance_to(puddle.global_position)
	var near := clampf(1.0 - distance / 420.0, 0.0, 1.0)
	if game.current_room != &"banyo":
		near = near * 0.5 if distance < 200.0 else 0.0
	if near <= 0.0:
		if buzz_player.playing:
			buzz_player.stop()
		return
	buzz_player.volume_db = lerpf(-34.0, -1.0, near)
	if not buzz_player.playing:
		buzz_player.play()


func _build_spark_light() -> void:
	# Karanlıkta elektrikli su mavi-beyaz kıvılcımlarla titrer.
	spark_light = PointLight2D.new()
	spark_light.texture = _radial_texture()
	spark_light.color = Color(0.55, 0.75, 1.0)
	spark_light.texture_scale = 1.6
	spark_light.enabled = false
	if puddle != null:
		spark_light.position = puddle.global_position
	game.add_child.call_deferred(spark_light)


func _update_spark() -> void:
	var live: bool = puddle != null and game.lights_out and _water_live() and game.current_room == &"banyo"
	spark_light.enabled = live
	if live:
		spark_light.energy = randf_range(0.3, 1.1) if randf() > 0.15 else 1.8


func _enable_torch() -> void:
	torch = PointLight2D.new()
	torch.texture = _cone_texture()
	torch.texture_scale = 3.6
	torch.color = Color(1.0, 0.94, 0.78)
	torch.energy = 0.0
	torch.position = Vector2(0, -26)
	game.player.add_child(torch)
	# İkinci katman: daha geniş ve sönük yan ışık; merkez koni güçlü kalır, geçişler yumuşak.
	torch_wide = PointLight2D.new()
	torch_wide.texture = _cone_texture(true)
	torch_wide.texture_scale = 4.4
	torch_wide.color = Color(1.0, 0.9, 0.72)
	torch_wide.energy = 0.0
	game.player.add_child(torch_wide)
	torch_angle = game.player.facing.angle()
	torch.rotation = torch_angle
	# Kendiliğinden yanış: kısa titreme, sonra sabit.
	torch_flicker = create_tween()
	for e in [1.2, 0.0, 0.8, 0.1, 1.5]:
		torch_flicker.tween_property(torch, "energy", e, 0.07)


func _update_torch(delta: float) -> void:
	if torch == null:
		return
	# Işık yalnız yürünen yöne vurur; dönüş yumuşak.
	var target: float = game.player.facing.angle()
	torch_angle = lerp_angle(torch_angle, target, minf(1.0, delta * 12.0))
	torch.rotation = torch_angle
	# Işık kafa lambasının camından çıkar (görselle aynı nokta), baktığı yöne vurur.
	torch.position = game.player.headlamp_tip()
	if torch_flicker == null or not torch_flicker.is_running():
		var want := 1.5 if game.power_dead() else 0.45
		torch.energy = move_toward(torch.energy, want, delta * 3.0)
	if torch_wide != null:
		torch_wide.position = torch.position
		torch_wide.rotation = torch_angle
		torch_wide.enabled = torch.enabled
		torch_wide.energy = torch.energy * 0.42


# --- Baloncuklar ---------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Diyaloglar ve seslenme E'nin yanında farenin sol tıkıyla da ilerler.
	var confirm := (event.is_action_pressed("interact") and not event.is_echo()) or _left_click(event)
	if under_view != null and confirm:
		get_viewport().set_input_as_handled()
		_osman_call_step()
		return
	if not phone_waiting or not confirm:
		return
	get_viewport().set_input_as_handled()
	phone_waiting = false
	phone_advance.emit()


static func _left_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT


func _phone_line(target: Node2D, text: String, speaker := "") -> void:
	if call_cut or game.finished:
		return
	await _manual_line(target, text, false, speaker)


# manual: oyuncu E'ye basana kadar bekler (sinematik konuşmalar). Diğerleri süreyle kaybolur ve E'yi
# yakalamaz (oyun içi yorumlar etkileşimle çakışmasın).
func say(target: Node2D, text: String, seconds: float, manual := false) -> void:
	if manual:
		await _manual_line(target, text, false, "")
		return
	show_bubble(target, text, false, "", seconds)
	await get_tree().create_timer(seconds).timeout


func think(target: Node2D, text: String, seconds: float, manual := false) -> void:
	if manual:
		await _manual_line(target, text, true, "")
		return
	show_bubble(target, text, true, "", seconds)
	await get_tree().create_timer(seconds).timeout


func _manual_line(target: Node2D, text: String, thought: bool, speaker: String) -> void:
	show_bubble(target, text, thought, speaker, -1.0)
	bubbles[target].manual = true
	phone_waiting = true
	await phone_advance
	clear_bubble(target)


func wife(text: String, seconds: float) -> void:
	show_bubble(phone, text, false, "Karım (telefonda)", seconds)
	await get_tree().create_timer(seconds).timeout


func show_bubble(target: Node2D, text: String, thought: bool, speaker: String, seconds: float) -> void:
	clear_bubble(target)
	var bubble := Bubble.new()
	bubble.story = self
	bubble.anchor = target
	bubble.anchor_offset = PLAYER_HEAD if target == game.player else target.get("draw_offset") + Vector2(0, -44)
	if target.get("kind") == "cat":
		bubble.anchor_offset = Vector2(0, -80)
	bubble.text = text
	bubble.thought = thought
	bubble.speaker = speaker
	bubble.lifetime = seconds
	bubble.voice = "man" if target == game.player else ("wife" if speaker != "" else ("cat" if target.get("kind") == "cat" else ""))
	if thought:
		bubble.voice = ""
	overlay.add_child(bubble)
	bubbles[target] = bubble


func clear_bubble(target: Node2D) -> void:
	if bubbles.has(target):
		var old = bubbles[target]
		if is_instance_valid(old):
			old.queue_free()
		bubbles.erase(target)


func to_screen(world_point: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_point


# Osman oyuncunun peşinden gelir: uzaklaştıkça koşar, yetişince yürür, durunca oturur (8 yön).
class OsmanFollower extends Node2D:
	const CatSprite = preload("res://scripts/cat_sprite.gd")
	var story: Node
	var game: Node2D
	var room: StringName
	var t := 0.0
	var idle_t := 0.0
	var facing := Vector2.DOWN
	var moving := false
	var running := false

	func _process(delta: float) -> void:
		t += delta
		var p: Node2D = game.player
		visible = not game.finished and p.carry_cat
		if not visible:
			return
		if room != game.current_room:
			room = game.current_room
			global_position = p.global_position - p.facing * 40.0 + Vector2(0, 8)
		var back: Vector2 = -p.facing if p.facing.length() > 0.1 else Vector2.DOWN
		var target: Vector2 = p.global_position + back * 38.0 + back.orthogonal() * 18.0 + Vector2(0, 6)
		var to := target - global_position
		var d := to.length()
		moving = d > 10.0
		if moving:
			var speed := clampf(d * 5.0, 70.0, 460.0)
			running = speed > 170.0
			global_position += to.normalized() * minf(speed * delta, d)
			facing = to.normalized()
			idle_t = 0.0
		else:
			running = false
			idle_t += delta
		queue_redraw()

	func _draw() -> void:
		draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.6, 0.5))
		draw_circle(Vector2.ZERO, 11, Color(0, 0, 0, 0.25))
		draw_set_transform(Vector2.ZERO)
		var dir := CatSprite.dir_of(facing)
		if running:
			CatSprite.draw(self, "run", dir, t, 13.0, Vector2.ZERO, 1.7)
		elif moving:
			CatSprite.draw(self, "walk", dir, t, 7.0, Vector2.ZERO, 1.7)
		else:
			CatSprite.draw(self, "sit", dir, minf(idle_t, 0.95), 6.0, Vector2.ZERO, 1.7)


# Yerde kırık şişe camları ve köpüklü bira birikintisi; camlar ara ara parıldar.
# Osman'la yatak odasından çıkınca artçı şok: kapının önüne taş ve tahta parçaları düşer (oyuncuyu
# kıl payı ıskalar, yolu kapatmaz), evin başka yerlerinde de enkaz yığınları belirir, duvarlar soyulur.
var aftershock_done := false
const DEBRIS_SPOTS := {
	&"salon": [Vector2(560, 225), Vector2(110, 250), Vector2(420, 330)],
	&"mutfak": [Vector2(440, 170), Vector2(120, 175)],
	&"banyo": [Vector2(260, 300), Vector2(190, 115)],
	&"yatak_odasi": [Vector2(250, 250), Vector2(470, 210)],
}


func _aftershock_debris() -> void:
	if aftershock_done:
		return
	aftershock_done = true
	var p: Node2D = game.player
	game.camera.shake(1.1, 12.0)
	crash_player.pitch_scale = 0.8
	crash_player.volume_db = -2.0
	crash_player.play()
	# Kapının hemen önü (salon tarafı), oyuncunun arkasında.
	var door_pile := DebrisPile.new()
	door_pile.game = game
	door_pile.room = &"salon"
	door_pile.setup(97, 22, 22.0, true, 1.35)
	# Kapı aralığında, oyuncunun hemen arkasında (çizim sırası oyuncunun gerisinde kalır).
	door_pile.position = Vector2(game.ROOMS[&"salon"].position.x - 2.0, p.global_position.y - 3.0)
	world.add_child(door_pile)
	# Zamanlamalar bu düğümün Tween'leriyle: sahne yeniden yüklenirse kendiliğinden iptal olur.
	for i in 3:
		create_tween().tween_callback(func():
			thud_player.pitch_scale = randf_range(0.7, 0.95)
			thud_player.play()).set_delay(0.35 + i * 0.18)
	# Evin diğer yerlerinde zaten düşmüş enkaz.
	var n := 0
	for room in DEBRIS_SPOTS:
		for spot in DEBRIS_SPOTS[room]:
			var pile := DebrisPile.new()
			n += 1
			pile.game = game
			pile.room = room
			pile.setup(200 + n * 13, 10 + n % 4, 20.0, false, 1.15)
			pile.position = game.ROOMS[room].position + spot
			world.add_child(pile)
	create_tween().tween_method(func(v: float):
		game.wall_damage = v
		game.queue_redraw(), 0.0, 1.0, 0.9)
	create_tween().tween_callback(func():
		if not game.finished:
			say(p, "Az kalsın!", 1.4)).set_delay(0.7)


# Ön kapı enkazla kapanır: oyuncu yatak odasındayken salondan büyük bir gümbürtü gelir; döndüğünde
# kapının önünde taş ve kalaslardan bir yığın vardır.
func _block_front_door() -> void:
	front_blocked = true
	game.camera.shake(1.4, 14.0)
	crash_player.pitch_scale = 0.7
	crash_player.volume_db = 0.0
	crash_player.play()
	for i in 4:
		create_tween().tween_callback(func():
			thud_player.pitch_scale = randf_range(0.6, 0.85)
			thud_player.play()).set_delay(0.25 + i * 0.22)
	# Kapının tam önüne tek parça, kapıyı açtırmayacak büyüklükte duvar/tavan bloğu düşer.
	var slab := FallenSlab.new()
	slab.game = game
	slab.room = &"salon"
	slab.position = EXIT_POINT + Vector2(0, -6)
	world.add_child(slab)
	game.status.text = "Salondan bir gümbürtü! Ön kapının önü enkazla kapandı."
	create_tween().tween_callback(func():
		if not game.finished:
			think(game.player, "Bu ses... ön kapı! Artık geri dönüş yok, Osman'ı alıp güvenli bir yere sığınmalıyım.", 3.2)).set_delay(0.9)


# Kapının önüne düşen büyük blok: salonun kendi duvarından kopmuş parça (krem sıva, ahşap lambri
# şeridi, kırık köşede tuğla ve demir filizleri). Kapıyı tamamen örter; dibinde birkaç kırıntı.
class FallenSlab extends Node2D:
	var game: Node2D
	var room: StringName
	const PLASTER := Color("efe0ab")
	const PLASTER_DARK := Color("cdb987")
	const PANEL := Color("905c39")
	const CORE := Color("a89a80")
	const EDGE := Color("3a2a1c")

	func _process(_delta: float) -> void:
		visible = game == null or game.current_room == room

	func _draw() -> void:
		# Zemin gölgesi.
		draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.28))
		draw_circle(Vector2.ZERO, 70.0, Color(0, 0, 0, 0.3))
		draw_set_transform(Vector2.ZERO, -0.06)
		var slab := PackedVector2Array([Vector2(-54, 0), Vector2(-58, -34), Vector2(-44, -70), Vector2(-6, -84),
			Vector2(30, -78), Vector2(56, -60), Vector2(62, -26), Vector2(52, 0)])
		# Kalınlık: alt kenarda koyu beton yüz.
		var side := PackedVector2Array()
		for p in slab:
			side.append(p + Vector2(0, 9))
		draw_colored_polygon(side, CORE.darkened(0.35))
		draw_colored_polygon(slab, PLASTER)
		# Işık sol üstten: sağ alt yarı hafif gölgeli.
		var shade := Geometry2D.intersect_polygons(slab, PackedVector2Array([Vector2(10, -90), Vector2(80, -90), Vector2(80, 10), Vector2(-20, 10)]))
		for poly in shade:
			draw_colored_polygon(poly, Color(PLASTER_DARK, 0.55))
		# Duvarın alt kısmındaki ahşap lambri şeridi (salon duvarıyla aynı renk) ve pervaz çizgisi.
		var band := Geometry2D.intersect_polygons(slab, PackedVector2Array([Vector2(-70, -30), Vector2(70, -22), Vector2(70, 10), Vector2(-70, 10)]))
		for poly in band:
			draw_colored_polygon(poly, PANEL)
			for x in range(-50, 60, 14):
				draw_line(Vector2(x, -24), Vector2(x + 1, 0), PANEL.darkened(0.3), 1.0)
		draw_line(Vector2(-58, -30), Vector2(62, -22), PANEL.darkened(0.45), 2.0)
		# Kırık köşe: sıvanın altından tuğla ve beton görünür.
		var broken := PackedVector2Array([Vector2(-6, -84), Vector2(30, -78), Vector2(40, -66), Vector2(18, -58), Vector2(2, -66)])
		draw_colored_polygon(broken, CORE)
		for row in 3:
			for col in 3:
				var b := Vector2(4 + col * 11 - (5 if row % 2 else 0), -80 + row * 7)
				if Geometry2D.is_point_in_polygon(b + Vector2(4, 2), broken):
					draw_rect(Rect2(b, Vector2(9, 5)), Color("9a5a3c"))
		# Demir filizleri.
		draw_polyline(PackedVector2Array([Vector2(12, -76), Vector2(16, -96), Vector2(24, -102)]), Color("5a3a28"), 2.0)
		draw_polyline(PackedVector2Array([Vector2(24, -72), Vector2(30, -90)]), Color("5a3a28"), 2.0)
		# Çatlaklar.
		draw_polyline(PackedVector2Array([Vector2(-40, -66), Vector2(-28, -50), Vector2(-32, -38), Vector2(-18, -28)]), EDGE, 1.5)
		draw_polyline(PackedVector2Array([Vector2(38, -62), Vector2(30, -44), Vector2(40, -32)]), EDGE, 1.5)
		draw_polyline(PackedVector2Array([Vector2(-28, -50), Vector2(-46, -46)]), EDGE, 1.0)
		# Dış hat.
		var out := slab.duplicate()
		out.append(slab[0])
		draw_polyline(out, EDGE, 2.0)
		draw_set_transform(Vector2.ZERO)
		# Dipte birkaç kırıntı.
		for f in [[Vector2(-66, 4), 5.0], [Vector2(-58, 9), 3.5], [Vector2(64, 6), 4.5], [Vector2(70, 1), 3.0], [Vector2(8, 12), 3.5]]:
			var c: Vector2 = f[0]
			var r: float = f[1]
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r, 0), c + Vector2(-r * 0.3, -r), c + Vector2(r, -r * 0.4), c + Vector2(r * 0.6, r * 0.5)]), PLASTER_DARK)


# Taş ve tahta parçası yığını: düşüyorsa parçalar yukarıdan sırayla iner, sekip toz kaldırır.
class DebrisPile extends Node2D:
	var pieces: Array = []
	var t := 0.0
	var falling := false
	var game: Node2D
	var room: StringName

	func setup(seed: int, count: int, spread: float, fall: bool, scale_k := 1.0) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		falling = fall
		for i in count:
			var stone := rng.randf() < 0.62
			var g := rng.randf_range(0.42, 0.62)
			pieces.append({
				"stone": stone,
				"pos": Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread * 0.32, spread * 0.32)),
				"size": (rng.randf_range(4.0, 8.5) if stone else rng.randf_range(16.0, 30.0)) * scale_k,
				"rot": rng.randf_range(-PI, PI) if stone else rng.randf_range(-0.6, 0.6),
				"col": Color(g, g * 0.95, g * 0.88) if stone else Color(0.5, 0.31, 0.17).lerp(Color(0.62, 0.42, 0.24), rng.randf()),
				"delay": rng.randf_range(0.0, 0.55) if fall else -10.0,
			})
		pieces.sort_custom(func(a, b): return a.pos.y < b.pos.y)

	func _process(delta: float) -> void:
		t += delta
		# Yalnız kendi odasındayken görünür (komşu odanın duvar kadrajına taşmasın).
		visible = game == null or game.current_room == room
		if t < 4.0:
			queue_redraw()

	func _draw() -> void:
		draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.32))
		draw_circle(Vector2.ZERO, 30.0, Color(0, 0, 0, 0.18))
		draw_set_transform(Vector2.ZERO)
		for p in pieces:
			var k := 1.0
			if falling:
				k = clampf((t - p.delay) / 0.42, 0.0, 1.0)
				if k <= 0.0:
					continue
			var bounce := sin(clampf((t - p.delay - 0.42) / 0.25, 0.0, 1.0) * PI) * 4.0 if falling else 0.0
			var pos: Vector2 = p.pos - Vector2(0, (1.0 - k * k) * 150.0 + bounce)
			draw_set_transform(pos, p.rot + (1.0 - k) * 4.0)
			var s: float = p.size
			var c: Color = p.col
			if p.stone:
				var poly := PackedVector2Array([Vector2(-s, -s * 0.3), Vector2(-s * 0.4, -s * 0.9), Vector2(s * 0.6, -s * 0.7),
					Vector2(s, 0.0), Vector2(s * 0.5, s * 0.7), Vector2(-s * 0.7, s * 0.6)])
				draw_colored_polygon(poly, c)
				draw_colored_polygon(PackedVector2Array([Vector2(-s * 0.4, -s * 0.9), Vector2(s * 0.6, -s * 0.7), Vector2(0.0, -s * 0.2)]), c.lightened(0.18))
				var out := poly.duplicate()
				out.append(poly[0])
				draw_polyline(out, c.darkened(0.45), 1.0)
			else:
				draw_rect(Rect2(-s * 0.5, -2.5, s, 5.0), c)
				draw_rect(Rect2(-s * 0.5, -2.5, s, 1.5), c.lightened(0.2))
				draw_rect(Rect2(-s * 0.5, -2.5, s, 5.0), c.darkened(0.45), false, 1.0)
				draw_line(Vector2(s * 0.5, -2.5), Vector2(s * 0.5 + 3.0, 0.5), c.darkened(0.3), 1.0)
				draw_circle(Vector2(-s * 0.3, 0.0), 0.8, Color(0.25, 0.25, 0.28))
		draw_set_transform(Vector2.ZERO)
		if falling:
			var dk := clampf(1.0 - (t - 0.4) / 1.6, 0.0, 1.0)
			if t > 0.35 and dk > 0.0:
				for i in 6:
					var r := 10.0 + (t - 0.35) * 26.0 + i * 3.0
					draw_circle(Vector2(sin(i * 1.7) * 18.0, -6.0 - i * 3.0 - (t - 0.35) * 10.0), r, Color(0.78, 0.72, 0.64, 0.1 * dk))


class GlassPatch extends Node2D:
	var area := Rect2()
	var shards: Array = []
	var t := 0.0

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 314
		for i in 26:
			var c := Vector2(rng.randf_range(2, area.size.x - 2), rng.randf_range(2, area.size.y - 2))
			var sz := rng.randf_range(2.0, 4.5)
			var green := rng.randf() < 0.55
			shards.append({"c": c, "s": sz, "r": rng.randf() * TAU, "green": green, "phase": rng.randf() * 6.0})

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		# Bira: düzensiz amber birikinti ve köpük benekleri.
		draw_set_transform(area.get_center() + Vector2(-4, 1), 0.0, Vector2(1.0, 0.32))
		draw_circle(Vector2.ZERO, area.size.x * 0.42, Color(0.75, 0.5, 0.12, 0.32))
		draw_circle(Vector2(14, 6), area.size.x * 0.22, Color(0.75, 0.5, 0.12, 0.28))
		draw_set_transform(Vector2.ZERO)
		for k in 5:
			draw_circle(area.position + Vector2(10 + k * 9, area.size.y * 0.5 + sin(k * 1.7) * 3), 1.5, Color(1, 0.97, 0.88, 0.6))
		for sh in shards:
			var col := Color(0.45, 0.72, 0.42, 0.9) if sh.green else Color(0.55, 0.33, 0.12, 0.9)
			var pts := PackedVector2Array()
			for k in 3:
				pts.append(sh.c + Vector2.from_angle(sh.r + k * TAU / 3.0 + (0.4 if k == 1 else 0.0)) * sh.s)
			draw_colored_polygon(pts, col)
			var glint := maxf(0.0, sin(t * 2.4 + sh.phase))
			if glint > 0.85:
				draw_line(sh.c - Vector2(1.5, 0), sh.c + Vector2(1.5, 0), Color(1, 1, 1, (glint - 0.85) * 6.0), 1.0)


class Bubble extends Node2D:
	var story: Node
	var anchor: Node2D
	var anchor_offset := Vector2.ZERO
	var text := ""
	var thought := false
	var speaker := ""
	var lifetime := -1.0
	var age := 0.0
	var voice := ""
	var spoken := 0
	# Elle ilerleyen diyalog: köşede küçük [E] göstergesi.
	var manual := false
	const WIDTH := 400.0
	const FONT_SIZE := 24

	func _process(delta: float) -> void:
		age += delta
		if not is_instance_valid(anchor) or (lifetime > 0.0 and age >= lifetime):
			queue_free()
			return
		# Konuşan başka odadaysa (gizliyse) baloncuk görünmez.
		visible = anchor.is_visible_in_tree()
		# Her iki harfte bir konuşma sesi (düşüncede ses yok).
		var shown := mini(int(age * 48.0), text.length())
		if voice != "" and visible and shown / 2 > spoken:
			spoken = shown / 2
			if text[shown - 1] != " ":
				story.blip(voice)
		position = story.to_screen(anchor.global_position + anchor_offset)
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var text_size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, WIDTH, FONT_SIZE)
		var head := 0.0
		var head_w := 0.0
		if speaker != "":
			head = FONT_SIZE + 2.0
			head_w = font.get_string_size(speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 4).x
		var pad := Vector2(16, 12)
		var box := Vector2(maxf(text_size.x, head_w), text_size.y + head) + pad * 2.0
		if manual:
			box.x = maxf(box.x, 120.0)
			box.y += 14.0
		var pop := minf(age / 0.12, 1.0)
		var rect := Rect2(Vector2(-box.x * 0.5, -box.y - 22.0), box)
		# Ekran kenarında kesilmesin: kutu içeri kaydırılır, kuyruk konuşanda kalır.
		var view: Vector2 = story.get_viewport().get_visible_rect().size
		var margin := 10.0
		rect.position.x += maxf(0.0, margin - (position.x + rect.position.x))
		rect.position.x -= maxf(0.0, position.x + rect.end.x - (view.x - margin))
		rect.position.y += maxf(0.0, margin + 12.0 - (position.y + rect.position.y))
		draw_set_transform(Vector2(0, -12), 0.0, Vector2.ONE * (0.6 + 0.4 * pop))
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.97, 0.97, 1.0, 0.94) if thought else Color(1, 1, 1, 0.97)
		style.border_color = Color("6d7fa8") if thought else (Color("b24a4a") if speaker != "" else Color("27272b"))
		style.set_border_width_all(3)
		style.set_corner_radius_all(22 if thought else 10)
		style.draw(get_canvas_item(), rect)
		if thought:
			# Düşünce baloncuğu: başa doğru küçülen daireler.
			for i in 3:
				var r := 7.0 - i * 2.0
				var p := Vector2(-6.0 + i * 4.0, -14.0 + i * 9.0)
				draw_circle(p, r + 2.5, style.border_color)
				draw_circle(p, r, style.bg_color)
		else:
			var tail := PackedVector2Array([Vector2(-10, -23), Vector2(10, -23), Vector2(0, -6)])
			draw_colored_polygon(tail, style.border_color)
			draw_colored_polygon(PackedVector2Array([Vector2(-6, -25), Vector2(6, -25), Vector2(0, -11)]), style.bg_color)
		var origin := rect.position + pad
		if speaker != "":
			draw_string(font, origin + Vector2(0, font.get_ascent(FONT_SIZE - 4)), speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 4, Color("b24a4a"))
			origin.y += head
		# Daktilo efekti: harfler sırayla belirir.
		var shown := text.substr(0, int(age * 48.0))
		var ink := Color("3b4660") if thought else Color("17171a")
		draw_multiline_string(font, origin + Vector2(0, font.get_ascent(FONT_SIZE)), shown, HORIZONTAL_ALIGNMENT_LEFT, WIDTH, FONT_SIZE, -1, ink)
		if manual and shown.length() >= text.length():
			# Piksel [E] çipi: konuşmanın E ile ilerlediğini gösterir.
			var chip := Rect2(rect.end - Vector2(34, 26), Vector2(24, 20))
			var lift := 1.0 if fmod(age, 1.0) < 0.5 else 0.0
			chip.position.y -= lift
			draw_rect(Rect2(chip.position + Vector2(0, 3), chip.size), Color(0.2, 0.13, 0.08))
			draw_rect(chip, Color(0.98, 0.9, 0.72))
			draw_rect(chip, Color(0.35, 0.22, 0.12), false, 2.0)
			draw_string(font, chip.position + Vector2(0, 16), "E", HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 16, Color(0.25, 0.15, 0.08))
		draw_set_transform(Vector2.ZERO)


# --- Yön okları -----------------------------------------------------------------

# Zihnin kararması: ölüm sayısıyla güçlenen kenar karartması, hafifçe nefes alır gibi dalgalanır.
class MindVignette extends Node2D:
	var strength := 0.0
	var time := 0.0

	func _process(delta: float) -> void:
		time += delta
		if strength > 0.0:
			queue_redraw()

	func _draw() -> void:
		if strength <= 0.0:
			return
		var view := get_viewport().get_visible_rect().size
		var c := view * 0.5
		var breathe := 1.0 + 0.04 * sin(time * 1.3)
		for i in 30:
			var r := (view.length() * 0.32 + i * 16.0) * breathe
			draw_arc(c, r, 0, TAU, 96, Color(0.05, 0.0, 0.02, strength * 0.06), 18.0)


# Elektrik tehlikesi işareti: sigorta kutusunun hemen altında süzülen sarı üçgen içinde yıldırım ve
# kutuyu gösteren ok (kutu duvarın tepesinde, üstünde yer yok). Ekran katmanında çizilir, karartmadan
# etkilenmez; kaçak onarılınca kaybolur.
class HazardSign extends Node2D:
	var story: Node
	var time := 0.0
	var box: Area2D
	# Kutunun görünen alt kenarı (dünya) ve işaretin ekranda ondan uzaklığı.
	const BOX_BOTTOM := Vector2(0, -8)
	const GAP := 48.0
	const SCALE := 0.75

	func _process(delta: float) -> void:
		time += delta
		if box == null or not is_instance_valid(box):
			box = story.world.find_item("electrical_box")
		var game: Node2D = story.game
		visible = box != null and box.is_visible_in_tree() and not story.world.leak_repaired and not game.finished
		if visible:
			var p: Vector2 = story.to_screen(box.global_position + box.draw_offset + BOX_BOTTOM)
			position = p + Vector2(0, GAP + sin(time * 3.0) * 5.0)
			queue_redraw()

	func _draw() -> void:
		var pulse := 0.5 + 0.5 * sin(time * 5.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * SCALE)
		# Sıcak sarı hale: dikkat çeker.
		for i in 5:
			draw_circle(Vector2(0, -4), 46.0 - i * 7.0, Color(1.0, 0.85, 0.2, (0.04 + 0.05 * pulse) * (i + 1) / 5.0))
		# Kutuyu gösteren ok (yukarı).
		var lift := -4.0 * pulse
		draw_colored_polygon(PackedVector2Array([Vector2(0, -50 + lift), Vector2(11, -38 + lift), Vector2(-11, -38 + lift)]), Color(0.12, 0.1, 0.06))
		draw_colored_polygon(PackedVector2Array([Vector2(0, -46 + lift), Vector2(7, -39 + lift), Vector2(-7, -39 + lift)]), Color(1.0, 0.85, 0.2))
		# Uyarı üçgeni: koyu kenar, sarı iç.
		var tri := PackedVector2Array([Vector2(0, -34), Vector2(31, 20), Vector2(-31, 20)])
		var inner := PackedVector2Array([Vector2(0, -26), Vector2(24, 15), Vector2(-24, 15)])
		draw_colored_polygon(tri, Color(0.12, 0.1, 0.06))
		draw_colored_polygon(inner, Color(1.0, 0.82, 0.12).lerp(Color(1.0, 0.95, 0.5), pulse * 0.6))
		# Yıldırım.
		var bolt := PackedVector2Array([Vector2(3, -20), Vector2(-9, 1), Vector2(-1, 1), Vector2(-5, 13),
			Vector2(9, -6), Vector2(1, -6), Vector2(6, -20)])
		draw_colored_polygon(bolt, Color(0.1, 0.08, 0.05))
		# Ara ara çakan kıvılcım.
		var k := fmod(time, 1.4)
		if k < 0.25:
			var a := sin(k / 0.25 * PI)
			for d in [Vector2(-38, -18), Vector2(36, -22), Vector2(30, 14)]:
				draw_line(d, d + Vector2(6, -6) * a, Color(1, 1, 0.75, a), 2.0)
				draw_line(d + Vector2(6, -6) * a, d + Vector2(2, -12) * a, Color(1, 1, 0.75, a), 2.0)


class Guide extends Node2D:
	var story: Node
	var target_room: StringName = &""
	var target_node: Node2D
	var target_offset := Vector2.ZERO
	var target_point := Vector2.ZERO
	var time := 0.0

	func clear() -> void:
		target_room = &""
		target_node = null

	func _process(delta: float) -> void:
		time += delta
		queue_redraw()

	func _goal_world() -> Vector2:
		var game: Node2D = story.game
		var goal: Vector2 = target_node.global_position + target_offset if is_instance_valid(target_node) else target_point
		if game.current_room == target_room:
			return goal
		# Hedef başka odadaysa önce o odaya (yoksa salona) açılan kapıya yönlendir.
		var fallback: Vector2 = goal
		for row in game.DOOR_TRANSITIONS:
			if row[0] != game.current_room:
				continue
			if row[1] == target_room:
				return row[2]
			if row[1] == &"salon":
				fallback = row[2]
		return fallback

	# Ok yerine "déjà vu" ışıltısı: zaman döngüsündeki adamın hatırası ona yol gösterir.
	# Oyuncudan hedefe süzülen birkaç sıcak ışık zerresi (toz gibi), hedefte yumuşak nabız ve kıvılcımlar;
	# hedef ekran dışındaysa o kenardan sızan hafif bir parıltı. Hiçbir UI şekli (ok, çizgi) yok.
	func _draw() -> void:
		if target_room == &"" or story.game.finished:
			return
		var game: Node2D = story.game
		# Yalnız odalar arası yön: hedef bu odadaysa oyuncu kendisi arar (ışıltı yok).
		if game.current_room == target_room:
			return
		var from: Vector2 = story.to_screen(game.player.global_position + Vector2(0, -40))
		var goal: Vector2 = story.to_screen(_goal_world())
		var delta := goal - from
		var distance := delta.length()
		if distance < 1.0:
			return
		var dir := delta / distance
		var side := dir.orthogonal()
		var warm := Color(1.0, 0.88, 0.6)
		# Süzülen zerreler: yay çizen yol boyunca, uçlarda solarak.
		var bend := minf(distance * 0.18, 70.0)
		for i in 5:
			var t := fmod(time * 0.32 + i * 0.2, 1.0)
			var arc := sin(t * PI)
			var sway := sin(time * 1.7 + i * 2.1) * 10.0
			var p := from + delta * t + side * (arc * bend + sway)
			var a := smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.75, 1.0, t)) * 0.55
			_glow(p, 8.5, Color(warm, a))
			# Kısa iz: zerrenin biraz gerisinde sönük noktalar.
			for k in range(1, 4):
				var tk := maxf(0.0, t - k * 0.012)
				var pk := from + delta * tk + side * (sin(tk * PI) * bend + sway)
				draw_circle(pk, 2.7 - k * 0.6, Color(warm, a * (0.5 - k * 0.12)))
		var view := story.get_viewport().get_visible_rect().size
		var on_screen := Rect2(Vector2.ZERO, view).grow(-30).has_point(goal)
		if game.current_room == target_room and on_screen:
			# Hedefte hatıra nabzı + çevresinde göz kırpan kıvılcımlar.
			var pulse := 0.5 + 0.5 * sin(time * 2.4)
			_glow(goal, 26.0 + pulse * 10.0, Color(warm, 0.16 + 0.12 * pulse))
			for k in 6:
				var ang := TAU * k / 6.0 + time * 0.4
				var tw := pow(maxf(0.0, sin(time * 3.0 + k * 1.3)), 6.0)
				var sp := goal + Vector2.from_angle(ang) * (30.0 + 8.0 * sin(time + k))
				if tw > 0.05:
					draw_line(sp - Vector2(5, 0) * tw, sp + Vector2(5, 0) * tw, Color(1, 0.97, 0.85, tw), 1.5)
					draw_line(sp - Vector2(0, 5) * tw, sp + Vector2(0, 5) * tw, Color(1, 0.97, 0.85, tw), 1.5)
		elif not on_screen:
			# Hedef görünmüyorsa o yöndeki ekran kenarından sızan sıcak ışık.
			var edge := Vector2(clampf(goal.x, 0.0, view.x), clampf(goal.y, 0.0, view.y))
			var pulse := 0.5 + 0.5 * sin(time * 2.0)
			for k in 24:
				draw_circle(edge, 150.0 - k * 6.0, Color(warm, 0.008 + 0.006 * pulse))

	func _glow(p: Vector2, r: float, color: Color) -> void:
		for k in 4:
			draw_circle(p, r * (1.0 - k * 0.22), Color(color, color.a * (0.18 + k * 0.22)))


func _radial_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


func _cone_texture(wide := false) -> Texture2D:
	# Merkezden sağa açılan fener konisi (yarım açı ~26°) + ayak ucunda küçük hale.
	# wide: yan katman için daha geniş (~50°), kenarları çok yumuşak, hale yok.
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var half_angle := deg_to_rad(50.0 if wide else 26.0)
	var soft := deg_to_rad(26.0 if wide else 8.0)
	for y in size:
		for x in size:
			var d := Vector2(x, y) - c
			var r := d.length() / (size * 0.5)
			var a := 0.0
			if d.x > 0.0 and r <= 1.0:
				var off := absf(atan2(d.y, d.x))
				var edge := clampf((half_angle - off) / soft, 0.0, 1.0)
				edge = edge * edge * (3.0 - 2.0 * edge)
				a = edge * pow(1.0 - r, 0.55 if not wide else 0.8) * smoothstep(0.0, 0.08, r)
			if not wide:
				a = maxf(a, clampf(1.0 - r / 0.14, 0.0, 1.0) * 0.45)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _wav(samples: PackedFloat32Array, loop_stream: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = data
	if loop_stream:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples.size()
	return stream


func _build_ring() -> AudioStreamWAV:
	# Klasik ev telefonu: 0.4 sn çal, 0.2 sn sus, 0.4 sn çal, 2 sn sus.
	var length := 3.0
	var samples := PackedFloat32Array()
	samples.resize(int(length * MIX_RATE))
	for i in samples.size():
		var t := float(i) / MIX_RATE
		var on := t < 0.4 or (t > 0.6 and t < 1.0)
		if on:
			var bell := sin(TAU * 400.0 * t) + sin(TAU * 450.0 * t)
			samples[i] = bell * 0.3 * (0.6 + 0.4 * signf(sin(TAU * 20.0 * t)))
	return _wav(samples, true)


func _build_buzz() -> AudioStreamWAV:
	# Elektrik cızırtısı: 100 Hz uğultu + rastgele çıtırtı patlamaları (1 sn döngü).
	var samples := PackedFloat32Array()
	samples.resize(MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var crackle := 0.0
	for i in samples.size():
		var t := float(i) / MIX_RATE
		var hum := sin(TAU * 100.0 * t) * 0.25 + sin(TAU * 200.0 * t) * 0.14 + sin(TAU * 300.0 * t) * 0.08
		hum = signf(hum) * pow(absf(hum), 0.7)
		if rng.randf() < 0.0009:
			crackle = rng.randf_range(0.4, 0.9)
		crackle *= 0.996
		samples[i] = hum * 0.6 + rng.randf_range(-1.0, 1.0) * crackle
	return _wav(samples, true)


# Hortum, bakış yönüne yakın (±70°) ve menzildeki en yakın aleve kendiliğinden döner.
func _aim_direction(player: Node2D) -> Vector2:
	var origin: Vector2 = player.nozzle_position()
	var facing: Vector2 = player.facing
	var best := facing
	var best_d := INF
	for f in fire_field.fires:
		if f.out:
			continue
		var v: Vector2 = f.pos + Vector2(0, -12) - origin
		var d := v.length()
		if d < AIM_ASSIST_RANGE and absf(facing.angle_to(v)) < AIM_ASSIST_ANGLE and d < best_d:
			best_d = d
			best = v / maxf(d, 0.001)
	return best


func touch_fire() -> void:
	if game.finished or rescue_phase or not game.player.active:
		return
	if burn_left <= 0.0:
		burn_tick = 0.0
		body_fire.emitting = true
	burn_left = BURN_AFTER
	if scream_cooldown <= 0.0:
		scream_cooldown = 2.2
		scream_player.play()
		show_bubble(game.player, "AAAAH! Yanıyorum!", false, "", 1.6)
		world.message("Yanıyorsun! Hemen alevlerden uzaklaş!")


func _update_burning(delta: float) -> void:
	if rescue_phase:
		return
	scream_cooldown = maxf(0.0, scream_cooldown - delta)
	body_fire.global_position = game.player.global_position + Vector2(0, -36)
	if burn_left <= 0.0:
		return
	burn_left -= delta
	burn_tick -= delta
	if burn_tick <= 0.0:
		burn_tick = BURN_TICK
		game.player.take_damage(BURN_DAMAGE)
	if burn_left <= 0.0 or not game.player.active:
		burn_left = 0.0
		body_fire.emitting = false


func _build_body_fire() -> void:
	# Oyuncunun üstünde yanan alevler.
	body_fire = CPUParticles2D.new()
	body_fire.emitting = false
	body_fire.amount = 46
	body_fire.lifetime = 0.55
	body_fire.local_coords = false
	body_fire.texture = fire_field._soft_texture()
	body_fire.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	body_fire.emission_rect_extents = Vector2(13, 30)
	body_fire.direction = Vector2(0, -1)
	body_fire.spread = 10.0
	body_fire.gravity = Vector2(0, -220)
	body_fire.initial_velocity_min = 30.0
	body_fire.initial_velocity_max = 70.0
	body_fire.scale_amount_min = 0.35
	body_fire.scale_amount_max = 0.7
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1.0, 0.85, 0.4, 0.9), Color(1.0, 0.5, 0.1, 0.8), Color(0.3, 0.05, 0.0, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	body_fire.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	body_fire.material = mat
	body_fire.z_index = 4
	game.add_child.call_deferred(body_fire)


func _build_spray() -> void:
	# Su püskürtmesi: nozuldan bakış yönüne beyaz-mavi sis.
	spray_fx = CPUParticles2D.new()
	spray_fx.emitting = false
	spray_fx.amount = 160
	spray_fx.lifetime = 0.6
	spray_fx.local_coords = false
	spray_fx.texture = _radial_texture()
	spray_fx.spread = 13.0
	spray_fx.initial_velocity_min = 330.0
	spray_fx.initial_velocity_max = 430.0
	spray_fx.damping_min = 150.0
	spray_fx.damping_max = 260.0
	spray_fx.gravity = Vector2(0, 160)
	spray_fx.scale_amount_min = 0.1
	spray_fx.scale_amount_max = 0.32
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.0))
	spray_fx.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(0.8, 0.9, 1.0, 0.0))
	ramp.add_point(0.4, Color(0.92, 0.97, 1.0, 0.7))
	spray_fx.color_ramp = ramp
	spray_fx.z_index = 3
	game.add_child.call_deferred(spray_fx)


func _build_hiss() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var prev := 0.0
	for i in samples.size():
		var n := rng.randf_range(-1.0, 1.0)
		var high := n - prev * 0.6
		prev = n
		var edge := minf(1.0, minf(float(i), float(samples.size() - i)) / 400.0)
		samples[i] = high * 0.35 * edge
	return _wav(samples, true)


func _build_thud() -> AudioStreamWAV:
	# Ağır mobilya düşüşü: alçak gümleme + kırılan tahta çıtırtısı.
	var length := 1.0
	var samples := PackedFloat32Array()
	samples.resize(int(length * MIX_RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var low := 0.0
	for i in samples.size():
		var t := float(i) / MIX_RATE
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.04
		var boom := (sin(TAU * 55.0 * t) * 0.7 + low * 2.5) * exp(-t * 5.0)
		var crack := rng.randf_range(-1.0, 1.0) * 0.5 * exp(-t * 14.0) * (1.0 if rng.randf() < 0.3 else 0.2)
		samples[i] = boom + crack
	return _wav(samples, false)


func _build_zap() -> AudioStreamWAV:
	var length := 0.9
	var samples := PackedFloat32Array()
	samples.resize(int(length * MIX_RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in samples.size():
		var t := float(i) / MIX_RATE
		var env := exp(-t * 3.5)
		var buzz := signf(sin(TAU * 60.0 * t)) * 0.4 + rng.randf_range(-1.0, 1.0) * 0.6
		samples[i] = buzz * env
	return _wav(samples, false)
