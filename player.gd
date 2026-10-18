extends CharacterBody2D

signal died
signal health_changed(value: int)

@export var speed: float = 250.0
const SPRINT_MULTIPLIER := 1.35
@export var max_health := 100
var health := 100
var input_locked := false
var active: bool = true
var invulnerable := false
var facing := Vector2.DOWN
var crouching := false
var moving := false
# Ara sahnede (kapıdan giriş) kilitliyken de yürüme animasyonu oynasın.
var scripted_walk := false
# Osman yanında yürüyor (omuzda taşınmaz).
var cat_follower := false
var sprinting := false
var anim_time := 0.0
var sheet: Texture2D
# Elde tutulan eşya (yangın tüpü): görseli ve PNG içindeki dolu bölge.
var held_tex: Texture2D
var held_region := Rect2(16, 7, 57, 79)
# Tüp kullanıma hazırken E basılı tutma püskürtmedir; etkileşim tetiklenmez.
var tool_ready := false
# Yalnız arayüzün tüketmediği dünya tıklamaları basılı etkileşim sayılır.
var mouse_interact_held := false
# Taşıma animasyonları: elde matkap / vida kutusu, omuzda kedi, sırtta deprem çantası.
var hand_drill := false
var hand_screws := false
var hand_flashlight := false
# Kafa lambası: banyodan alınınca başa takılır (siyah kayış + alında lamba); ışık her zaman bakılan yöne.
var headlamp := false
var headlamp_on := false
var carry_cat := false
var carry_bag := false
# Elektrik çarpması animasyonu (saniye): beyaz parlama ↔ röntgen iskelet, titreme, kıvılcımlar.
var shock := 0.0
# Çök-Kapan-Tutun pozu: 1 çömel, 2 + eller başta, 3 + bir kol masaya tutunur.
var cover_pose := 0
# Büyük sarsıntıda yürüme hızı çarpanı (deprem güvenliği ayarlar).
var speed_mult := 1.0
# Çömelme animasyonu: crouch_blend 0→1 (ayakta→çömelik) yumuşak geçiş; hands_k eller yanlardan başa.
var crouch_blend := 0.0
var hands_k := 0.0
# Sığınakta sarsıntı sırasında hafif titreme (deprem güvenliği ayarlar).
var tremble := false

# Kare sırası: 0 düz, 1 sağa bakış, 2-3 sağa koşu, 4 sola bakış, 5-6 sola koşu,
# 7 yukarı bakış, 8 çömelme, 9 eşya tutma
const FRAME := 32
const SPRITE_SCALE := 3.0


func _ready() -> void:
	health = max_health
	add_to_group("player")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1
	z_index = 0
	# CharacterBody2D kökeni ayak hizasıdır; görsel yukarı çizilir.
	$CollisionShape2D.position = Vector2(0, -7)
	var foot_shape := CircleShape2D.new()
	foot_shape.radius = 12.0
	$CollisionShape2D.shape = foot_shape
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var path := "res://assets/player_sheet.png"
	if ResourceLoader.exists(path):
		sheet = load(path)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		mouse_interact_held = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		mouse_interact_held = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	if not active or input_locked:
		return
	mouse_interact_held = true
	get_viewport().set_input_as_handled()
	if tool_ready:
		return
	# Tıklanan yakındaki nesneyi seç; menzil ve kullanılabilirlik E ile aynıdır.
	var target: Area2D = null
	var best := INF
	for node in get_tree().get_nodes_in_group("interactables"):
		var area := node as Area2D
		if area == null or not area.is_visible_in_tree() or not area.overlaps_body(self):
			continue
		if area.has_method("can_interact") and not area.can_interact(self):
			continue
		var extent := Vector2(100, 80)
		var offset := Vector2.ZERO
		if area.get("size") is Vector2:
			extent = area.get("size")
		if area.get("draw_offset") is Vector2:
			offset = area.get("draw_offset")
		var bounds := Rect2(Vector2(-extent.x * 0.5, -extent.y) + offset, extent).grow(12)
		if bounds.has_point(area.get_local_mouse_position()):
			var distance := bounds.get_center().distance_squared_to(area.get_local_mouse_position())
			if distance < best:
				best = distance
				target = area
	if target != null:
		target.call("interact", self)
	else:
		_interact()


func _process(delta: float) -> void:
	anim_time += delta * (SPRINT_MULTIPLIER if sprinting else 1.0)
	shock = maxf(0.0, shock - delta)
	crouch_blend = move_toward(crouch_blend, 1.0 if crouching else 0.0, delta * 6.0)
	hands_k = move_toward(hands_k, 1.0 if cover_pose >= 2 else 0.0, delta * 5.0)
	queue_redraw()


func _physics_process(_delta: float) -> void:
	_process_focus()
	if not active or input_locked:
		velocity = Vector2.ZERO
		moving = scripted_walk
		sprinting = false
		return
	crouching = Input.is_action_pressed("crouch")
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	moving = direction != Vector2.ZERO
	sprinting = moving and not crouching and Input.is_action_pressed("sprint")
	var pace := 0.4 if crouching else (SPRINT_MULTIPLIER if sprinting else 1.0)
	velocity = direction * speed * pace * speed_mult
	if moving:
		facing = direction.normalized()
	move_and_slide()
	if Input.is_action_just_pressed("interact") and not tool_ready:
		_interact()


# Etkileşim odağı: E ile kullanılacak tek nesne; yalnız onun [E] yazısı gösterilir.
var focus: Area2D = null


func _process_focus() -> void:
	var next := nearest_interactable() if active and not input_locked else null
	if next != focus:
		var old := focus
		focus = next
		if is_instance_valid(old):
			old.queue_redraw()
		if is_instance_valid(focus):
			focus.queue_redraw()


func _interact() -> void:
	var nearest := nearest_interactable()
	if nearest != null:
		nearest.call("interact", self)


func nearest_interactable() -> Area2D:
	var nearest: Area2D = null
	var best_distance: float = INF
	for node in get_tree().get_nodes_in_group("interactables"):
		var area := node as Area2D
		if area == null or not area.is_visible_in_tree() or not area.overlaps_body(self):
			continue
		if area.has_method("can_interact") and not area.can_interact(self):
			continue
		var distance := global_position.distance_squared_to(area.global_position)
		# Osman, üstünde/altında durduğu yatağa göre önceliklidir.
		if area.get("kind") is String and area.get("kind") == "cat":
			distance *= 0.1
		if distance < best_distance:
			best_distance = distance
			nearest = area
	return nearest


func take_damage(amount: int) -> void:
	if not active or invulnerable:
		return
	health = maxi(0, health - maxi(amount, 0))
	health_changed.emit(health)
	if health == 0:
		die()

func heal(amount: int) -> void:
	if not active:
		return
	health = mini(max_health, health + maxi(amount, 0))
	health_changed.emit(health)


# Ceset: karakter ayak bileğinden devrilip sırt üstü yere yığılır, gözleri kapalı.
var dead := false
var fall_k := 0.0
var fall_dir := 1.0
signal landed


func fall_dead() -> void:
	if dead:
		return
	dead = true
	crouching = false
	crouch_blend = 0.0
	cover_pose = 0
	fall_dir = -1.0 if facing.x < -0.3 else 1.0
	var tw := create_tween()
	tw.tween_property(self, "fall_k", 1.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "fall_k", 0.93, 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "fall_k", 1.0, 0.1).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(0.42).timeout
	landed.emit()


func _draw_corpse(size: float) -> void:
	# Yere düşen gölge, devrildikçe uzar.
	draw_set_transform(Vector2(fall_dir * 40.0 * fall_k, 0), 0.0, Vector2(1.0 + fall_k * 1.4, 0.3))
	draw_circle(Vector2.ZERO, 22.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	# Önden görünen kare (0) ayak hizasından döndürülür: yerde sırt üstü yatan beden.
	var angle := fall_dir * PI * 0.5 * fall_k
	draw_set_transform(Vector2.ZERO, angle)
	draw_texture_rect_region(sheet, Rect2(-size / 2.0, -29.0 * SPRITE_SCALE, size, size), Rect2(0, 0, FRAME, FRAME))
	# Gözler kapalı: göz pikselleri ten rengiyle örtülür, altına ince göz kapağı çizgisi.
	var skin := Color(0.79, 0.59, 0.5)
	var lid := Color(0.42, 0.28, 0.22)
	for ex in [12, 16]:
		draw_rect(Rect2(-48 + ex * SPRITE_SCALE, -87 + 7 * SPRITE_SCALE, 2 * SPRITE_SCALE, SPRITE_SCALE), skin)
		draw_rect(Rect2(-48 + ex * SPRITE_SCALE, -87 + 7.6 * SPRITE_SCALE, 2 * SPRITE_SCALE, 1.0), lid)
	draw_set_transform(Vector2.ZERO)


func die() -> void:
	if not active or invulnerable:
		return
	active = false
	velocity = Vector2.ZERO
	died.emit()


func _is_holding() -> bool:
	var world = get_parent().get("objects") if get_parent() != null else null
	return world != null and not world.inventory.is_empty()


func _current_frame() -> int:
	if crouch_blend > 0.55:
		return 8
	var run := int(anim_time * 8.0) % 2
	var side := absf(facing.x) >= absf(facing.y)
	if moving:
		if side:
			return (2 if facing.x > 0 else 5) + run
		if facing.y < 0:
			return 7
		return 9 if _is_holding() else 0
	if side:
		return 1 if facing.x > 0 else 4
	if facing.y < 0:
		return 7
	return 9 if _is_holding() else 0


func _draw() -> void:
	if sheet == null:
		draw_rect(Rect2(-16, -64, 32, 64), Color("4c9bbd"))
		return
	var size := FRAME * SPRITE_SCALE
	if shock > 0.0:
		_draw_shock(size)
		return
	if dead:
		_draw_corpse(size)
		return
	_draw_held(true)
	_draw_carry(true)
	if cover_pose == 4:
		# Küçük eşyanın yanında iyice büzülme: gövde ayak hizasından basık, hafifçe sallanır.
		draw_set_transform(_tremor(), sin(anim_time * 3.0) * 0.035, Vector2(1.1, 0.74))
	elif crouch_blend > 0.0:
		# Çömelirken önce ezilip genişler (dizler bükülür), sonra yerine oturur; çömelikken nefes alır.
		var dip := sin(PI * minf(crouch_blend, 1.0))
		var sy := 1.0 - 0.16 * dip
		var sx := 1.0 + 0.07 * dip
		if crouch_blend >= 1.0:
			sy = 1.0 + 0.018 * sin(anim_time * 2.4)
			sx = 1.0 - 0.008 * sin(anim_time * 2.4)
		draw_set_transform(_tremor(), 0.0, Vector2(sx, sy))
	elif not moving and not dead:
		# Ayakta nefes alıp verme: göğüs hafifçe yükselir (ayak sabit), omuzlar az daralır.
		var breath := 0.5 + 0.5 * sin(anim_time * 2.2)
		draw_set_transform(_tremor(), 0.0, Vector2(1.0 - 0.012 * breath, 1.0 + 0.035 * breath))
	draw_texture_rect_region(sheet, Rect2(-size / 2.0, -29.0 * SPRITE_SCALE, size, size),
		Rect2(_current_frame() * FRAME, 0, FRAME, FRAME))
	if headlamp:
		_draw_headlamp()
	_draw_held(false)
	_draw_carry(false)
	_draw_cover_pose()
	draw_set_transform(Vector2.ZERO)


# Taşıma görselleri karakterle aynı piksel ızgarasında (3x) çizilir: kare pikseli (fx, fy) →
# yerel (-48 + fx*3, -87 + fy*3). Yöne göre çanta arkadan/yandan, kedi omuzda.
const CARRY_TEX := {
	"cat": "res://assets/carry/cat_shoulder.png", "cat_back": "res://assets/carry/cat_shoulder_back.png",
	"bag_back": "res://assets/carry/bag_back.png", "bag_side": "res://assets/carry/bag_side.png"}
var carry_tex := {}


func _carry(name: String, fx: int, fy: int, flip := false, region := Rect2()) -> void:
	if not carry_tex.has(name):
		carry_tex[name] = load(CARRY_TEX[name])
	var tex: Texture2D = carry_tex[name]
	var src := region if region.has_area() else Rect2(Vector2.ZERO, tex.get_size())
	var size := src.size * SPRITE_SCALE
	var pos := Vector2(-48 + fx * SPRITE_SCALE, -87 + fy * SPRITE_SCALE)
	if flip:
		# Aynalama: yatay ölçek -1 ile, görselin sağ kenarı pos.x + size.x'e oturur.
		draw_set_transform(pos + Vector2(size.x, 0), 0.0, Vector2(-1, 1))
		draw_texture_rect_region(tex, Rect2(Vector2.ZERO, size), src)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_texture_rect_region(tex, Rect2(pos, size), src)


# Çömelme karesinin üstüne piksel ızgarasında eller (başı korur) ve tutunan kol.
func _tremor() -> Vector2:
	return Vector2(randf_range(-1.0, 1.0), 0.0) * 1.5 if tremble else Vector2.ZERO


func _draw_cover_pose() -> void:
	if hands_k <= 0.01:
		return
	var skin := Color(0.79, 0.59, 0.5)
	var shade := Color(0.67, 0.49, 0.41)
	var px := func(fx: float, fy: float, w: float, h: float, c: Color) -> void:
		draw_rect(Rect2(-48 + round(fx) * SPRITE_SCALE, -87 + round(fy) * SPRITE_SCALE, w * SPRITE_SCALE, h * SPRITE_SCALE), c)
	# Eller yanlardan yükselip başın üstünde kapanır; ön kollar kulakların yanından iner.
	var k := 1.0 - pow(1.0 - hands_k, 3.0)
	px.call(lerpf(6, 9, k), lerpf(17, 8, k), 3, 2, skin)
	px.call(lerpf(22, 18, k), lerpf(17, 8, k), 3, 2, skin)
	if hands_k > 0.6:
		px.call(9, 10, 1, 5, shade)
		px.call(20, 10, 1, 5, shade)
	if cover_pose < 2:
		return
	if cover_pose == 4:
		# Büzülme: kollar başı tamamen sarar, dizler göğse çekilmiş.
		px.call(8, 10, 2, 6, shade)
		px.call(20, 10, 2, 6, shade)
		px.call(10, 9, 10, 2, skin)
		px.call(11, 20, 8, 2, shade)
		return
	if cover_pose >= 3:
		var right := facing.x >= 0.0
		if right:
			px.call(21, 19, 6, 2, skin)
			px.call(26, 18, 2, 4, shade)
		else:
			px.call(3, 19, 6, 2, skin)
			px.call(2, 18, 2, 4, shade)


func _draw_shock(size: float) -> void:
	var xray := int(anim_time / 0.07) % 2 == 0
	var jolt := Vector2(randf_range(-4, 4), randf_range(-3, 3))
	var rect := Rect2(Vector2(-size / 2.0, -29.0 * SPRITE_SCALE) + jolt, Vector2(size, size))
	var src := Rect2(_current_frame() * FRAME, 0, FRAME, FRAME)
	if xray:
		# Röntgen karesi: koyu mavi silüet + beyaz iskelet.
		draw_texture_rect_region(sheet, rect, src, Color(0.08, 0.12, 0.35))
		var o := jolt + Vector2(0, -87)
		var bone := Color(0.95, 0.97, 1.0)
		draw_circle(o + Vector2(0, 20), 10.0, bone)
		draw_rect(Rect2(o + Vector2(-5, 17), Vector2(4, 4)), Color(0.08, 0.12, 0.35))
		draw_rect(Rect2(o + Vector2(2, 17), Vector2(4, 4)), Color(0.08, 0.12, 0.35))
		draw_line(o + Vector2(0, 30), o + Vector2(0, 66), bone, 3.0)
		for r in 4:
			draw_line(o + Vector2(-11, 38 + r * 6), o + Vector2(11, 38 + r * 6), bone, 2.0)
		draw_line(o + Vector2(-14, 36), o + Vector2(-20, 58), bone, 2.5)
		draw_line(o + Vector2(14, 36), o + Vector2(20, 58), bone, 2.5)
		draw_line(o + Vector2(-8, 66), o + Vector2(8, 66), bone, 3.0)
		draw_line(o + Vector2(-5, 66), o + Vector2(-7, 84), bone, 2.5)
		draw_line(o + Vector2(5, 66), o + Vector2(7, 84), bone, 2.5)
	else:
		draw_texture_rect_region(sheet, rect, src, Color(2.2, 2.2, 2.6))
	# Gövdeyi saran mavi-beyaz kıvılcımlar.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(anim_time * 30.0)
	for k in 5:
		var p := Vector2(rng.randf_range(-26, 26), rng.randf_range(-84, 0))
		var bolt := PackedVector2Array([p])
		for j in 4:
			p += Vector2(rng.randf_range(-12, 12), rng.randf_range(-12, 12))
			bolt.append(p)
		draw_polyline(bolt, Color(0.75, 0.9, 1.0, 0.95), 2.0)
		draw_polyline(bolt, Color(1, 1, 1, 0.9), 1.0)


func _draw_carry(behind: bool) -> void:
	var up := facing.y < 0 and absf(facing.y) > absf(facing.x)
	var side := absf(facing.x) >= absf(facing.y)
	var right := facing.x > 0
	if behind:
		# Önden bakınca çantanın yalnız üst kenarı omuzların arkasından görünür.
		if carry_bag and not up and not side:
			_carry("bag_back", 11, 9, false, Rect2(0, 0, 10, 3))
		return
	if carry_bag:
		if up:
			_carry("bag_back", 10, 11)
		elif side:
			_carry("bag_side", 7 if right else 21, 11)
		else:
			# Askılar ve tokalar.
			for sx in [11, 19]:
				draw_rect(Rect2(-48 + sx * SPRITE_SCALE, -87 + 11 * SPRITE_SCALE, SPRITE_SCALE, 8 * SPRITE_SCALE), Color("962f0a"))
				draw_rect(Rect2(-48 + sx * SPRITE_SCALE, -87 + 16 * SPRITE_SCALE, SPRITE_SCALE, SPRITE_SCALE), Color("ebc83c"))
	if carry_cat and not cat_follower:
		if up:
			_carry("cat_back", 8, 8)
		elif side:
			# Yandan: kedi omuz boyunca uzanır, başı sırta doğru (yüzü kapatmaz).
			_carry("cat", 7 if right else 11, 8, not right)
		else:
			_carry("cat", 14, 8, true)
	var bob := sin(anim_time * 16.0) * 1.5 if moving else 0.0
	var dir := -1.0 if facing.x < -0.3 else 1.0
	var hand := Vector2(14.0 * dir if absf(facing.x) > 0.3 else 13.0, -36 + bob)
	if hand_drill:
		draw_set_transform(hand, 0.0, Vector2(dir, 1))
		draw_rect(Rect2(-4, -10, 18, 8), Color("e0b020"))
		draw_rect(Rect2(-4, -10, 18, 8), Color("5a4510"), false, 1.0)
		draw_rect(Rect2(14, -8, 5, 4), Color("8a8f93"))
		draw_line(Vector2(19, -6), Vector2(24, -6), Color("c9ced1"), 1.5)
		draw_rect(Rect2(-1, -2, 6, 9), Color("2a2a2a"))
		draw_set_transform(Vector2.ZERO)
	if hand_flashlight:
		_draw_flashlight()
	if hand_screws:
		var p := Vector2(-hand.x, hand.y + 4)
		draw_rect(Rect2(p + Vector2(-6, -6), Vector2(12, 8)), Color("b08850"))
		draw_rect(Rect2(p + Vector2(-6, -6), Vector2(12, 8)), Color("5e4423"), false, 1.0)
		for k in 2:
			draw_line(p + Vector2(-2 + k * 4, -6), p + Vector2(-2 + k * 4, -10), Color("c9ced1"), 1.2)


# Fener elin piksel ızgarasına oturur; yürürken sallanmaz, bakış yönüne göre döner.
# Işık da aynı noktadan çıkar (flashlight_tip), böylece görsel ile ışık hiç ayrılmaz.
func _flashlight_pose() -> Dictionary:
	var side := absf(facing.x) >= absf(facing.y)
	if side:
		var d := 1.0 if facing.x > 0 else -1.0
		return {"grip": Vector2(13.0 * d, -36), "dir": Vector2(d, 0)}
	if facing.y < 0:
		return {"grip": Vector2(13, -40), "dir": Vector2(0, -1)}
	return {"grip": Vector2(13, -33), "dir": Vector2(0, 1)}


# Kafa lambası yerleşimi (sprite karesinin piksel ızgarasında): kayış satırı ve başın sol/sağ kenarı.
# Değerler oyuncu sayfasındaki her kareden ölçüldü; çömelince baş 6 piksel aşağıdadır.
func _headlamp_layout() -> Dictionary:
	# Kayış alında, saç çizgisinde (gözlerin iki satır üstü); gözlüğe benzemesin.
	var f := _current_frame()
	if f == 8:
		return {"row": 10, "x0": 10, "x1": 19, "view": "front"}
	if f in [1, 2, 3]:
		return {"row": 4, "x0": 12, "x1": 18, "view": "right"}
	if f in [4, 5, 6]:
		return {"row": 4, "x0": 13, "x1": 19, "view": "left"}
	if f == 7:
		return {"row": 4, "x0": 10, "x1": 19, "view": "back"}
	return {"row": 4, "x0": 10, "x1": 19, "view": "front"}


func _hp(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(-FRAME * SPRITE_SCALE / 2.0 + x * SPRITE_SCALE, -29.0 * SPRITE_SCALE + y * SPRITE_SCALE,
		w * SPRITE_SCALE, h * SPRITE_SCALE), c)


func _draw_headlamp() -> void:
	var l := _headlamp_layout()
	var r: int = l.row
	var x0: int = l.x0
	var x1: int = l.x1
	var strap := Color("141414")
	var body := Color("1f1f22")
	var rim := Color("55585c")
	var lens := Color(1.0, 0.95, 0.7) if headlamp_on else Color("8d8f80")
	# Esnek siyah kayış başın çevresinde.
	_hp(x0, r, x1 - x0 + 1, 1, strap)
	match l.view:
		"front":
			_hp(13, r - 1, 4, 3, body)
			_hp(13, r - 1, 4, 1, rim)
			_hp(14, r, 2, 1, lens)
		"right":
			_hp(x1 - 1, r - 1, 3, 3, body)
			_hp(x1 - 1, r - 1, 3, 1, rim)
			_hp(x1 + 1, r, 1, 1, lens)
		"left":
			_hp(x0 - 1, r - 1, 3, 3, body)
			_hp(x0 - 1, r - 1, 3, 1, rim)
			_hp(x0 - 1, r, 1, 1, lens)
		"back":
			# Arkadan: kayışın tokası ve pil kutusu, küçük kırmızı ışık.
			_hp(13, r, 4, 2, Color("2a2a2e"))
			_hp(16, r, 1, 1, Color(0.9, 0.2, 0.15) if headlamp_on else Color("4a2020"))


# Işığın çıktığı nokta: lambanın camı (görselle birebir).
func headlamp_tip() -> Vector2:
	var l := _headlamp_layout()
	var lx := 15.0
	match l.view:
		"right":
			lx = l.x1 + 1.5
		"left":
			lx = l.x0 - 0.5
	return Vector2(-FRAME * SPRITE_SCALE / 2.0 + lx * SPRITE_SCALE, -29.0 * SPRITE_SCALE + (l.row + 0.5) * SPRITE_SCALE)


func flashlight_tip() -> Vector2:
	var pose := _flashlight_pose()
	return pose.grip + pose.dir * 13.0


func _draw_flashlight() -> void:
	var pose := _flashlight_pose()
	var g: Vector2 = pose.grip
	var d: Vector2 = pose.dir
	var body := Color("2c3138")
	var rim := Color("9aa0a6")
	var lens := Color(1.0, 0.92, 0.6)
	if d.y == 0.0:
		# Yandan: gövde yatay, kafa önde biraz daha kalın.
		var x0 := g.x if d.x > 0 else g.x - 9.0
		draw_rect(Rect2(x0, g.y - 3, 9, 6), body)
		var hx := g.x + 9.0 if d.x > 0 else g.x - 13.0
		draw_rect(Rect2(hx, g.y - 4, 4, 8), rim)
		draw_rect(Rect2(hx + (3.0 if d.x > 0 else 0.0), g.y - 3, 1, 6), lens)
		draw_rect(Rect2(g.x - 2, g.y - 3, 4, 6), Color("c9967a"))
	else:
		# Önden/arkadan: gövde dikey, cam bakış yönünde.
		var y0 := g.y if d.y > 0 else g.y - 9.0
		draw_rect(Rect2(g.x - 3, y0, 6, 9), body)
		var hy := g.y + 9.0 if d.y > 0 else g.y - 13.0
		draw_rect(Rect2(g.x - 4, hy, 8, 4), rim)
		if d.y > 0:
			draw_rect(Rect2(g.x - 3, hy + 3, 6, 1), lens)
		draw_rect(Rect2(g.x - 3, g.y - 2, 6, 4), Color("c9967a"))


# Tüpü tutma animasyonu: bakış yönüne göre elde, yürürken hafif sallanır; yukarı bakınca sırtın arkasında kalır.
func _draw_held(behind: bool) -> void:
	if held_tex == null:
		return
	var up := facing.y < 0 and absf(facing.y) > absf(facing.x)
	if up != behind:
		return
	var side := absf(facing.x) >= absf(facing.y)
	var bob := sin(anim_time * 16.0) * 1.5 if moving else 0.0
	var size := Vector2(24, 33)
	var pos := Vector2(8, -50 + bob)
	if side:
		pos = Vector2(8 if facing.x > 0 else -32, -52 + bob)
	elif up:
		pos = Vector2(4, -56 + bob)
	var rect := Rect2(pos, size)
	if side and facing.x < 0:
		rect = Rect2(pos + Vector2(size.x, 0), Vector2(-size.x, size.y))
	draw_texture_rect_region(held_tex, rect, held_region)


func nozzle_position() -> Vector2:
	return global_position + Vector2(0, -32) + facing * 30.0
