extends Node2D

# Afet bilinci — her büyük sarsıntıdan önce hafif bir öncü titreme gelir (habercisi).
#  - Öncü titremede güvenli yerler (sağlam masa/sehpa yanı, yatak yanı, iç duvar dibi) yumuşakça parlar.
#  - Güvenli yerin yanında [C]: adam oraya geçer → ÇÖK → KAPAN (eller başta) → TUTUN; C basılı kaldıkça korunur.
#  - Büyük sarsıntıda yürümek neredeyse imkânsız (yavaşlama + sendeleme). Korunmayanın başına tavandan
#    bir parça düşer: gölge, düşen parça, çarpma, "AH!" ve can kaybı.

const Sfx = preload("res://scripts/sfx.gd")
const VoiceSynth = preload("res://scripts/voice_synth.gd")
const SPOT_RANGE := 90.0
const HEAD_DAMAGE := 15
const TRIP_DAMAGE := 5
const BRICK_HIT_RADIUS := 24.0
const QUAKE_SLOW := 0.6
# Eski çift C (küçük eşyada iyice büzülme) kaldırıldı; aşağıdaki alanlar artık kullanılmıyor.
const SMALL_AREA := 4500.0
const DOUBLE_TAP := 0.7
var tap_pending := false
var tap_time := 0.0
var tap_spot := []

var game: Node2D
var story: Node
var time := 0.0
var warning := 0.0
# Öncü titreme ile büyük sarsıntı arasındaki geçiş anında sığınak bırakılmasın.
var quake_pending := false
var in_cover := false
var cover_step := 0
var cover_spot := Vector2.ZERO
var cover_label := ""
var cover_entry := Vector2.ZERO
var cover_released_required := false
var cover_run := 0
var head_hit_at := -1.0
var head_chunk := {}
var last_hurt := -10.0
var stumble_clock := 0.0
var tripping := false
var piles: Array = []
var ambient_debris: Array = []
var ambient_clock := 0.0
var puff: CPUParticles2D
var impact_player: AudioStreamPlayer
var ah_player: AudioStreamPlayer
var grunt_player: AudioStreamPlayer
var rumble_player: AudioStreamPlayer
var ui: CanvasLayer
var ui_canvas: Control
var red_flash := 0.0
# Eğitimde, sarsıntı olmadan da çök-kapan-tutun denenebilir.
var tutorial_cover := false
var brick := {}
var brick_killed := false
# Fısıltı gibi yükselip sönen adım sözcükleri: [metin, yaş].
var whispers: Array = []
var warned_once := false


func _ready() -> void:
	z_index = 2
	puff = CPUParticles2D.new()
	puff.emitting = false
	puff.one_shot = true
	puff.explosiveness = 0.92
	puff.amount = 22
	puff.lifetime = 1.0
	puff.local_coords = false
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var soft := GradientTexture2D.new()
	soft.gradient = g
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.width = 32
	soft.height = 32
	puff.texture = soft
	puff.spread = 180.0
	puff.initial_velocity_min = 30.0
	puff.initial_velocity_max = 110.0
	puff.damping_min = 60.0
	puff.damping_max = 120.0
	puff.gravity = Vector2(0, -15)
	puff.scale_amount_min = 0.6
	puff.scale_amount_max = 1.8
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.85, 0.8, 0.72, 0.7), Color(0.8, 0.75, 0.68, 0.0)])
	puff.color_ramp = ramp
	add_child(puff)
	impact_player = _audio(Sfx.sink_crack(), -4.0)
	impact_player.max_polyphony = 3
	ah_player = _audio(VoiceSynth.ah(), 0.0)
	grunt_player = _audio(Sfx.grunt(), 0.0)
	rumble_player = _audio(Sfx.rumble(), -30.0)
	ui = CanvasLayer.new()
	ui.layer = 4
	add_child(ui)
	ui_canvas = Control.new()
	ui_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_canvas.draw.connect(_draw_ui)
	ui.add_child(ui_canvas)
	game.quake.foreshock_started.connect(_on_foreshock)
	game.quake.quake_started.connect(_on_quake)


func _audio(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


func shaking() -> bool:
	return game.camera.remaining > 0.35 and not game.finished


func recently_hurt() -> bool:
	return time - last_hurt < 1.5


# Oyuncu senaryo dışında kendi kontrolünde mi (telefon, mini oyun, yatak altı vb. değil)?
func _free() -> bool:
	var p: Node2D = game.player
	return p.active and not game.finished and not story.looking and (not p.input_locked or in_cover or tripping)


# --- Güvenli yerler ----------------------------------------------------------------

func spots() -> Array:
	var list := []
	for item in game.objects.get_children():
		if not (item is Area2D) or item.room != game.current_room or item.collected:
			continue
		match item.kind:
			"table":
				# Alt duvara veya sandalyeye denk gelen noktaya oyuncuyu taşıma.
				var offsets := [Vector2(-item.size.x * 0.18, 22),
					Vector2(-item.size.x * 0.18, -item.foot_depth - 20),
					Vector2(-item.size.x * 0.5 - 22, -item.foot_depth * 0.5),
					Vector2(item.size.x * 0.5 + 22, -item.foot_depth * 0.5)]
				for offset in offsets:
					var candidate: Vector2 = item.global_position + offset
					if _cover_position_clear(candidate):
						list.append([candidate, "Masanın yanı", false])
						break
			"coffee_table":
				list.append([item.global_position + Vector2(-(item.size.x * 0.5 + 14), -8), "Sehpanın yanı", true])
			"bed":
				list.append([item.global_position + Vector2(item.size.x * 0.5 + 16, -30), "Yatağın yanı", false])
	if game.current_room == &"banyo":
		list.append([game.ROOMS[&"banyo"].position + Vector2(300, 250), "İç duvar dibi", false])
	return list


func _nearest_spot() -> Array:
	var best := []
	var best_d := INF
	for s in spots():
		var d: float = game.player.global_position.distance_to(s[0])
		if d < best_d:
			best_d = d
			best = s
	if best_d <= SPOT_RANGE:
		return best
	# Masa, sandalye, sehpa, koltuk... her sağlam mobilyanın yanında çök-kapan-tutun yapılır (yerinde).
	# Uzaklık eşyanın merkezine değil taban izine göre ölçülür; uzun masaların ucunda da çalışır.
	var pp: Vector2 = game.player.global_position
	for item in game.objects.get_children():
		if not (item is Area2D) or item.room != game.current_room or not item.solid or not item.visible or item.collected:
			continue
		if item.collectible or item.kind in ["cat", "puddle", "flashlight"]:
			continue
		var foot := Rect2(item.global_position - Vector2(item.size.x * 0.5, 24.0), Vector2(item.size.x, 34.0))
		var near := Vector2(clampf(pp.x, foot.position.x, foot.end.x), clampf(pp.y, foot.position.y, foot.end.y))
		if near.distance_to(pp) < 48.0:
			var small: bool = item.size.x * item.size.y < SMALL_AREA
			return [pp, ("Küçük eşyanın yanı" if small else "Eşyanın yanı"), small]
	return []


# --- Akış -------------------------------------------------------------------------

func _on_foreshock(seconds: float) -> void:
	if story.rescue_phase:
		return
	warning = seconds
	quake_pending = true
	rumble_player.play()
	# Adam titremeyi fark eder ve kendi kendine söyler (UI kutusu yerine düşünce baloncuğu).
	if _free() and not in_cover:
		var lines := ["Yer titriyor... büyüğü geliyor! Güvenli bir yere geçmeliyim.", "Bu titreme... yine geliyor! Masanın yanına!", "Hissediyorum... deprem! Sağlam bir yer bul."]
		story.think(game.player, lines[randi() % lines.size()], minf(seconds, 2.6))
		game.status.text = "Öncü titreme — bir eşyanın yanına geç, [C] basılı tut: çömel."
	create_tween().tween_property(rumble_player, "volume_db", -10.0, seconds)


func _on_quake(first: bool) -> void:
	warning = 0.0
	quake_pending = false
	create_tween().tween_property(rumble_player, "volume_db", -40.0, 3.5)
	if story.rescue_phase:
		return
	# İlk sarsıntıda tavandan tuğla düşer (öğrenilmiş tehlike); sonrakilerde korunmayanın başına parça.
	if first:
		_start_brick()
	else:
		head_hit_at = time + 0.9


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo or event.physical_keycode != KEY_C:
		return
	if not event.pressed:
		cover_released_required = false
		if in_cover:
			_leave_cover("Çömelmeyi bıraktın!" if shaking() else "")
		elif tap_pending:
			# İkinci C basışı için beklerken hareket kilidini kaldır.
			game.player.input_locked = false
			game.player.crouching = false
			game.player.cover_pose = 0
		return
	if cover_released_required:
		return
	# Küçük eşyada ikinci basış: iyice büzülüp otur.
	if tap_pending:
		get_viewport().set_input_as_handled()
		tap_pending = false
		_take_cover(tap_spot, true)
		return
	if not in_cover and (warning > 0.0 or shaking() or tutorial_cover) and _free():
		get_viewport().set_input_as_handled()
		var spot := _nearest_spot()
		if spot.is_empty():
			game.objects.message("Burası açık alan! Bir eşyanın ya da parlayan güvenli yerin yanına geç.")
			return
		# Küçük ya da büyük her eşyada tek C: çök-kapan-tutun.
		_take_cover(spot, false)


func _cover_position_clear(pos: Vector2) -> bool:
	var p: CharacterBody2D = game.player
	var foot: CollisionShape2D = p.get_node("CollisionShape2D")
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = foot.shape
	query.transform = foot.global_transform
	query.transform.origin += pos - p.global_position
	query.collision_mask = p.collision_mask
	query.exclude = [p.get_rid()]
	query.margin = p.safe_margin
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _take_cover(spot: Array, deep: bool) -> void:
	if in_cover:
		return
	if not _cover_position_clear(game.player.global_position):
		game.player.input_locked = false
		game.player.crouching = false
		game.player.cover_pose = 0
		return
	cover_entry = game.player.global_position
	cover_run += 1
	var run := cover_run
	in_cover = true
	cover_step = 0
	cover_spot = game.player.global_position
	cover_label = spot[1]
	var p: Node2D = game.player
	p.input_locked = true
	p.velocity = Vector2.ZERO
	# Oyuncuyu mobilyanın içinden çekmeden, bulunduğu yerde çöktür.
	# Yalnız çömelme: kol/tutunma pozu yok. Korunma birkaç adımda tamamlanır (cover_step 3).
	p.crouching = true
	p.cover_pose = 0
	whispers.append(["Çömel...", 0.0])
	for step in [1, 2, 3]:
		if not in_cover or run != cover_run:
			return
		cover_step = step
		await get_tree().create_timer(0.28).timeout


func _leave_cover(text: String) -> void:
	if not in_cover:
		return
	in_cover = false
	cover_run += 1
	cover_step = 0
	var p: Node2D = game.player
	# Geçiş yarıda kesildiyse masanın gövdesinin içinde bırakma.
	if not _cover_position_clear(p.global_position) and _cover_position_clear(cover_entry):
		p.global_position = cover_entry
	p.cover_pose = 0
	p.crouching = false
	p.input_locked = false
	if text != "":
		game.objects.message(text)


func _process(delta: float) -> void:
	time += delta
	if not Input.is_action_pressed("crouch"):
		cover_released_required = false
	var moving_input := Input.get_vector("move_left", "move_right", "move_up", "move_down") != Vector2.ZERO
	# Eğitim adımı C zaten basılıyken açılabilir; eşyanın yanında bekleyince korunmayı başlat.
	if tutorial_cover and not in_cover and not cover_released_required \
			and not moving_input and Input.is_action_pressed("crouch") and _free():
		var tutorial_spot := _nearest_spot()
		if not tutorial_spot.is_empty():
			_take_cover(tutorial_spot, false)
	if moving_input and (in_cover or tap_pending):
		cover_released_required = true
		if in_cover:
			_leave_cover("")
		if tap_pending:
			tap_pending = false
			game.player.input_locked = false
			game.player.cover_pose = 0
			game.player.crouching = Input.is_action_pressed("crouch")
	if tap_pending and time - tap_time > DOUBLE_TAP:
		# İkinci basış gelmedi: küçük eşya bu haliyle korumaz.
		tap_pending = false
		var pl: Node2D = game.player
		pl.cover_pose = 0
		pl.crouching = false
		pl.input_locked = false
		game.objects.message("Bu eşya küçük — iyice büzülmek için C'ye art arda iki kez bas!")
	for wsp in whispers:
		wsp[1] += delta
	whispers = whispers.filter(func(wsp): return wsp[1] < 1.6)
	warning = maxf(0.0, warning - delta)
	red_flash = maxf(0.0, red_flash - delta * 2.0)
	var p: Node2D = game.player
	if in_cover:
		if not Input.is_action_pressed("crouch"):
			_leave_cover("Çömelmeyi bıraktın!" if shaking() else "")
		elif not shaking() and warning <= 0.0 and not quake_pending and cover_step >= 3 and not tutorial_cover:
			_leave_cover("Sarsıntı geçti. Şimdi hareket edebilirsin.")
	# Büyük sarsıntıda yürümek neredeyse imkânsız.
	p.speed_mult = QUAKE_SLOW if (shaking() and _free() and not in_cover) else 1.0
	p.tremble = in_cover and shaking()
	if shaking() and _free() and not in_cover:
		var moving: bool = p.velocity.length() > 5.0
		if moving and not tripping and not story.rescue_phase:
			stumble_clock += delta
			if stumble_clock > 0.6:
				stumble_clock = 0.0
				if randf() < 0.5:
					_trip()
		ambient_clock -= delta
		if ambient_clock <= 0.0:
			ambient_clock = randf_range(1.0, 1.8)
			var room: Rect2 = game.ROOMS[game.current_room]
			ambient_debris.append({"pos": Vector2(randf_range(room.position.x + 30, room.end.x - 30), randf_range(room.position.y + 30, room.end.y - 20)), "age": 0.0, "dur": 0.75})
	_update_brick(delta)
	if head_hit_at > 0.0 and time >= head_hit_at:
		head_hit_at = -1.0
		var crouched_by_object: bool = p.crouching and not _nearest_spot().is_empty()
		if crouched_by_object and not in_cover:
			game.objects.message("Bir eşyanın yanında çömeldiğin için parça seni ıskaladı!")
		elif _free() and not in_cover:
			head_chunk = {"age": 0.0}
		elif in_cover:
			_ambient_impact(p.global_position + Vector2(randf_range(30, 50) * (1 if randf() < 0.5 else -1), -6))
			game.objects.message("Yanına bir parça düştü ama korundun! (" + cover_label + ")")
	if not head_chunk.is_empty():
		head_chunk.age += delta
		if head_chunk.age >= 0.55:
			head_chunk = {}
			_head_hit()
	for d in ambient_debris:
		d.age += delta
		if d.age >= d.dur:
			_ambient_impact(d.pos)
	ambient_debris = ambient_debris.filter(func(d): return d.age < d.dur)
	for pl in piles:
		pl.age += delta
	piles = piles.filter(func(pl): return pl.age < 5.0)
	queue_redraw()
	ui_canvas.queue_redraw()


func _head_hit() -> void:
	if not game.player.active or story.rescue_phase:
		return
	var p: Node2D = game.player
	_ambient_impact(p.global_position + Vector2(0, -4))
	ah_player.pitch_scale = randf_range(0.95, 1.05)
	ah_player.play()
	game.camera.shake(0.4, 10.0)
	red_flash = 0.6
	last_hurt = time
	_damage(HEAD_DAMAGE)
	story.say(p, "AH!", 1.0)
	game.objects.message("Başına tavandan bir parça düştü. Öncü titremede bir eşyanın yanında [C] ile çömel.")


func _trip() -> void:
	if story.rescue_phase:
		return
	# Sendeleme: kontrol kilitlenmez, yalnız küçük hasar ve sarsılma.
	tripping = true
	grunt_player.play()
	game.camera.shake(0.3, 6.0)
	last_hurt = time
	_damage(TRIP_DAMAGE)
	game.objects.message("Sarsıntıda yürümek tehlikeli! Sendeledin.")
	await get_tree().create_timer(0.5).timeout
	tripping = false


# Bütün deprem darbeleri aynı can sistemini kullanır.
func _damage(amount: int) -> void:
	if story.rescue_phase:
		return
	var p: Node2D = game.player
	if amount > 0:
		p.take_damage(amount)


# --- Tuğla: ilk sarsıntıda başa düşen tuğla ----------------------------------------------
# Tuğla düşeceği yeri önceden işaretler; yürüyerek gölgeden çıkmak veya C ile korunmak mümkündür.
func _start_brick() -> void:
	if not _free():
		return
	brick_killed = false
	brick = {"age": 0.0, "dur": 1.0, "target": game.player.global_position}


func _update_brick(_delta: float) -> void:
	if story.rescue_phase:
		brick = {}
		return
	if brick.is_empty():
		return
	brick.age += _delta
	if brick.age < brick.dur:
		return
	var p: Node2D = game.player
	var pos: Vector2 = brick.target
	var nearby: bool = p.global_position.distance_to(pos) <= BRICK_HIT_RADIUS
	var safe: bool = in_cover or p.crouching
	brick = {}
	_ambient_impact(pos)
	if not p.active or not nearby:
		return
	if safe:
		story.say(p, "Kıl payı! Tuğla yanıma düştü...", 1.8)
		return
	ah_player.play()
	red_flash = 0.9
	game.camera.shake(0.5, 14.0)
	last_hurt = time
	brick_killed = true
	p.take_damage(p.health)


func _ambient_impact(pos: Vector2) -> void:
	puff.global_position = pos
	puff.restart()
	puff.emitting = true
	impact_player.pitch_scale = randf_range(0.5, 0.75)
	impact_player.play()
	var pieces := []
	for k in randi_range(3, 5):
		pieces.append([Vector2(randf_range(-14, 14), randf_range(-6, 6)), randf_range(2.5, 5.0), randf_range(0.42, 0.62)])
	piles.append({"pos": pos, "age": 0.0, "pieces": pieces})


func _rock(pos: Vector2, size: float, rot: float) -> void:
	draw_set_transform(pos, rot)
	var s := size
	draw_colored_polygon(PackedVector2Array([Vector2(-s, -s * 0.4), Vector2(-s * 0.3, -s), Vector2(s * 0.8, -s * 0.6), Vector2(s, s * 0.3), Vector2(s * 0.2, s), Vector2(-s * 0.8, s * 0.6)]), Color(0.6, 0.57, 0.52))
	draw_line(Vector2(-s * 0.5, -s * 0.5), Vector2(s * 0.4, -s * 0.4), Color(0.78, 0.75, 0.7), 1.5)
	draw_set_transform(Vector2.ZERO)


func _draw() -> void:
	# Öncü titreme / sarsıntıda güvenli yerler yumuşak ışıkla belirir.
	if (warning > 0.0 or shaking()) and _free() and not in_cover:
		var pulse := 0.5 + 0.5 * sin(time * 5.0)
		for s in spots():
			draw_set_transform(s[0], 0.0, Vector2(1.0, 0.45))
			for i in 4:
				draw_circle(Vector2.ZERO, 26.0 - i * 5.0, Color(0.55, 1.0, 0.6, (0.05 + 0.05 * pulse)))
			draw_set_transform(Vector2.ZERO)
	if in_cover and cover_step >= 3:
		var breath := 0.5 + 0.5 * sin(time * 2.2)
		draw_set_transform(game.player.global_position, 0.0, Vector2(1.0, 0.45))
		for i in 4:
			draw_circle(Vector2.ZERO, 30.0 - i * 6.0, Color(1.0, 0.92, 0.7, 0.04 + 0.04 * breath))
		draw_set_transform(Vector2.ZERO)
	for pl in piles:
		var a := clampf(1.0 - (pl.age - 3.5) / 1.5, 0.0, 1.0)
		for pc in pl.pieces:
			var c: Vector2 = pl.pos + pc[0]
			var gcol: float = pc[2]
			draw_rect(Rect2(c - Vector2(pc[1], pc[1] * 0.6), Vector2(pc[1] * 2.0, pc[1] * 1.2)), Color(gcol, gcol * 0.95, gcol * 0.88, a))
	for d in ambient_debris:
		var k: float = d.age / d.dur
		draw_set_transform(d.pos, 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, 6.0 + 8.0 * k, Color(0, 0, 0, 0.15 + 0.25 * k))
		draw_set_transform(Vector2.ZERO)
		_rock(d.pos - Vector2(0, 240.0 * (1.0 - k * k)), 8.0, k * 7.0)
	if not brick.is_empty():
		# Tuğla: başın üstünde büyüyen gölge, dönerek inen kırmızı tuğla.
		var kb: float = clampf(brick.age / brick.dur, 0.0, 1.0)
		var pp: Vector2 = brick.target
		draw_set_transform(pp, 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, 8.0 + 10.0 * kb, Color(0, 0, 0, 0.2 + 0.35 * kb))
		draw_set_transform(pp + Vector2(0, -80) - Vector2(0, 300.0 * (1.0 - kb * kb)), kb * 5.0)
		draw_rect(Rect2(-12, -6, 24, 12), Color("a8432e"))
		draw_rect(Rect2(-12, -6, 24, 12), Color("5e2418"), false, 1.5)
		draw_line(Vector2(-12, 0), Vector2(12, 0), Color("c86a50"), 1.0)
		draw_set_transform(Vector2.ZERO)
	# Başa düşen parça: başın üstünde büyüyen gölge, hızlanarak inen beton.
	if not head_chunk.is_empty():
		var k2: float = head_chunk.age / 0.55
		var head: Vector2 = game.player.global_position + Vector2(0, -80)
		draw_set_transform(game.player.global_position, 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, 8.0 + 10.0 * k2, Color(0, 0, 0, 0.2 + 0.3 * k2))
		draw_set_transform(Vector2.ZERO)
		_rock(head - Vector2(0, 260.0 * (1.0 - k2 * k2)), 11.0, k2 * 8.0)


func _draw_ui() -> void:
	var font := ThemeDB.fallback_font
	var view := ui_canvas.size
	var p: Node2D = game.player
	if not brick.is_empty() and not (p.crouching or in_cover) \
			and p.global_position.distance_to(brick.target) <= BRICK_HIT_RADIUS + 18.0:
		# Tuğla düşerken başın üstünde nabız gibi atan [C] uyarısı.
		var hc: Vector2 = get_viewport().get_canvas_transform() * (p.global_position + Vector2(0, -130))
		var pulse := 0.6 + 0.4 * sin(time * 14.0)
		var kr := Rect2(hc - Vector2(26, 26), Vector2(52, 52))
		ui_canvas.draw_rect(kr, Color(0.1, 0.06, 0.04, 0.85))
		ui_canvas.draw_rect(kr, Color(1, 0.75, 0.3, pulse), false, 4.0)
		ui_canvas.draw_string(font, kr.position + Vector2(0, 38), "C", HORIZONTAL_ALIGNMENT_CENTER, kr.size.x, 34, Color(1, 0.92, 0.75))
	if red_flash > 0.0:
		ui_canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0.8, 0.05, 0.05, red_flash * 0.45))
	var head: Vector2 = get_viewport().get_canvas_transform() * (p.global_position + Vector2(0, -112))
	# Adımlar: başın üstünden süzülüp sönen fısıltılar (gölgeli, sıcak beyaz).
	for wsp in whispers:
		var k: float = wsp[1] / 1.6
		var a := clampf(1.0 - k, 0.0, 1.0) * clampf(wsp[1] / 0.15, 0.0, 1.0)
		var pos := head + Vector2(-30, 70 - 40.0 * k)
		ui_canvas.draw_string(font, pos + Vector2(2, 2), wsp[0], HORIZONTAL_ALIGNMENT_CENTER, 300, 22, Color(0, 0, 0, 0.6 * a))
		ui_canvas.draw_string(font, pos, wsp[0], HORIZONTAL_ALIGNMENT_CENTER, 300, 22, Color(1.0, 0.94, 0.82, a))
