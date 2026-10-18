extends Node2D

signal earthquake_started
signal escaped

const InteractionScript = preload("res://interaction.gd")
const QuakeScript = preload("res://scripts/quake.gd")
const StoryScript = preload("res://scripts/story.gd")
const WALL_HALF_WIDTH := 12.0
const BACKGROUND_COLOR := Color("30495c")
const ROOMS := {
	# Salon ve yatak odası tek ekran yüksekliğinde (taban y 760.7); kapı bandı y 578.7-722.7 ortak.
	&"salon": Rect2(600, 405, 655.2, 355.7),
	# Salona göre: yatak odası biraz, mutfak ve banyo belirgin şekilde daha küçük.
	&"yatak_odasi": Rect2(50, 410.7, 550, 330),
	# Mutfak salonun altında; salonun alt duvarındaki kapıdan girilir.
	&"mutfak": Rect2(600, 760.7, 540, 250),
	&"banyo": Rect2(1255.2, 440.7, 400, 340),
}
const ROOM_CENTERS := {
	&"salon": Vector2(927.6, 582.85),
	&"yatak_odasi": Vector2(325, 575.7),
	&"mutfak": Vector2(870, 885.7),
	&"banyo": Vector2(1455.2, 610.7),
}
const DOOR_TRANSITIONS := [
	[&"salon", &"yatak_odasi", Vector2(564, 650.7), Vector2(24, 120)],
	[&"yatak_odasi", &"salon", Vector2(636, 650.7), Vector2(24, 120)],
	[&"salon", &"banyo", Vector2(1291.2, 650.7), Vector2(24, 120)],
	[&"banyo", &"salon", Vector2(1219.2, 650.7), Vector2(24, 120)],
	[&"salon", &"mutfak", Vector2(1028, 796.7), Vector2(96, 24)],
	[&"mutfak", &"salon", Vector2(1028, 724.7), Vector2(96, 24)],
]
const WALL_RECTS := [
	Rect2(588, 405, 24, 173.7),
	Rect2(588, 722.7, 24, 38),
	Rect2(1243.2, 405, 24, 173.7),
	# Salonun sağ alt duvarı banyonun sol duvarıdır; banyo tabanına (780.7) kadar iner.
	Rect2(1243.2, 722.7, 24, 70),
	Rect2(588, 393, 679.2, 24),
	# Salonun alt duvarı mutfak kapısında (x 980-1076) bölünür.
	Rect2(588, 748.7, 392, 24),
	Rect2(1076, 748.7, 191.2, 24),
	Rect2(38, 410.7, 24, 330),
	Rect2(38, 398.7, 574, 24),
	Rect2(38, 728.7, 574, 24),
	Rect2(1643.2, 440.7, 24, 340),
	Rect2(1243.2, 428.7, 424, 24),
	# Mutfak: sol, sağ ve alt duvarlar.
	Rect2(588, 760.7, 24, 262),
	Rect2(1128, 760.7, 24, 262),
	Rect2(588, 998.7, 564, 24),
	Rect2(1243.2, 768.7, 424, 24),
	# Kuru eşik: yan kaideler sigortaya uzanırken suyu dolaşmayı engeller.
	Rect2(1267.2, 572.7, 42, 12),
	Rect2(1267.2, 716.7, 42, 12),
]
const DOOR_RECTS := [
	Rect2(588, 578.7, 24, 144),
	Rect2(1243.2, 578.7, 24, 144),
	Rect2(891.6, 393, 72, 24),
	Rect2(980, 748.7, 96, 24),
]
# Oda görünümleri: yalnız burada tanımlı odalar dokulu çizilir; diğerleri düz renk kalır.
# Yeni oda için aynı anahtarlarla satır eklemek yeterli. Duvar yüzü üst duvarın önünde yükselir.
const ROOM_SKINS := {
	&"salon": {
		"floor": "res://assets/salon/floor.png",
		"wall_lower": "res://assets/salon/wall_lower.png",
		"wall_upper": "res://assets/salon/wall_upper.png",
		"scale": 2.0,
		# Üst duvar kâğıdının yukarı ek uzaması (piksel).
		"upper_extra": 40.0,
		# Duvar üst yüzeyi/kenar rengi (lambri ile uyumlu koyu ahşap).
		"trim": Color("4a3020"),
		"door": "res://assets/salon/front_door.png",
		# Duvar yüzündeki pencereler (dünya x merkezi) ve zemindeki halılar (dünya merkezi, ölçek).
		"windows": [["res://assets/salon/window.png", 760.0], ["res://assets/salon/window.png", 1112.2]],
		"rugs": [["res://assets/salon/rug.png", Vector2(1040, 608), 3.0]],  # oturma grubu merkezi: salon (600,405) + (440,203)
		"ambient": Color(0.5, 0.47, 0.6)
	},
	&"yatak_odasi": {
		"floor": "res://assets/bedroom/floor.png",
		"wall_lower": "res://assets/bedroom/wall_lower.png",
		"wall_upper": "res://assets/bedroom/wall_upper.png",
		"scale": 2.0,
		"upper_extra": 40.0,
		"trim": Color("4a3020"),
		"ambient": Color(0.56, 0.52, 0.62)
	},
	&"mutfak": {
		# Mutfak: fayans zemin ve fayans duvar (banyo dokuları), sıcak ortam ışığı.
		"floor": "res://assets/banyo/floor.png",
		"wall_lower": "res://assets/banyo/wall.png",
		"wall_upper": "res://assets/banyo/wall.png",
		"scale": 2.0,
		"upper_extra": 64.0,
		"trim": Color("3a2c22"),
		"ambient": Color(0.72, 0.68, 0.62)
	},
	&"banyo": {
		"floor": "res://assets/banyo/floor.png",
		# Tek fayans dokusu alt+üst olarak kullanılır; toplam yükseklik salonla aynı (176 px).
		"wall_lower": "res://assets/banyo/wall.png",
		"wall_upper": "res://assets/banyo/wall.png",
		"scale": 2.0,
		"upper_extra": 64.0,
		"trim": Color("2c3a33"),
		"rugs": [["res://assets/banyo/rug.png", Vector2(1455.2, 640.7), 2.5]],
		"ambient": Color(0.84, 0.9, 0.92)
	}
}
const WALL_CAP := 24.0
var skin_textures := {}
var ambient: CanvasModulate

# Merkezi oyun saati: 00:00'dan başlar; time_scale ileride zaman yavaşlatma için kullanılır.
var clock_seconds := 0.0
var time_scale := 1.0
# Ön kapı açıklığı (0 kapalı, 1 açık): girişte kapı menteşesinden açılır.
var door_open := 0.0
# Deprem hasarı (0-1): duvar sıvası yer yer dökülür, altından tuğla görünür; çatlaklar. Artçı şokta açılır.
var wall_damage := 0.0
var current_room: StringName = &"salon"
var objects: Node2D
var transitioning: bool = false

# Hikâye betiği: oyunda her zaman story.gd; fragman kendi alt sınıfını verir (oynanış değişmez).
var story_script: Script = StoryScript
@onready var player = $Player
@onready var camera = $Camera2D
@onready var status: Label = $HUD/Status
@onready var countdown: Label = $HUD/Countdown

var electricity_off: bool = false
var gas_off: bool = false
var quake: Node
var story: Node
# Karartma: deprem ışıkları söndürür (lights_out); kaçak giderilince zifiri karanlık (pitch_dark).
var lights_out := false
var pitch_dark := false
const BLACKOUT_AMBIENT := Color(0.13, 0.13, 0.2)
const PITCH_AMBIENT := Color(0.03, 0.03, 0.05)
var finished: bool = false


func _enter_tree() -> void:
	var bindings := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"interact": [KEY_E], "crouch": [KEY_C], "sprint": [KEY_SHIFT],
		"restart": [KEY_R], "use_bandage": [KEY_B]
	}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if action == "sprint":
				event.location = KEY_LOCATION_LEFT
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)


func _ready() -> void:
	y_sort_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ambient = CanvasModulate.new()
	ambient.name = "ambient"
	add_child(ambient)
	_build_clock()
	$Triggers.y_sort_enabled = true
	_build_rooms()
	_build_doors()
	objects = preload("res://scripts/world.gd").new()
	objects.name = "objects"
	objects.game = self
	add_child(objects)
	for legacy in [$Triggers/Switch, $Triggers/TV]:
		legacy.hide()
		legacy.remove_from_group("interactables")
		legacy.set_deferred("monitoring", false)
	player.position = objects.get_event_point(&"salon", &"entry_spawn")
	get_viewport().size_changed.connect(_update_camera_frame)
	_enter_room(&"salon")
	$Triggers/Switch.setup(InteractionScript.Kind.SWITCH, "ŞALTER", Vector2(890, 467))
	$Triggers/GasValve.setup(InteractionScript.Kind.GAS, "GAZ", objects.get_event_point(&"salon", &"gas_valve"))
	$Triggers/TV.setup(InteractionScript.Kind.TV, "TV", Vector2(1100.5, 497.3))
	$Triggers/ExitDoor.setup(InteractionScript.Kind.EXIT, "KAPI", Vector2(927.6, 445))
	for trigger in $Triggers.get_children():
		trigger.used.connect(_on_interaction)
	player.died.connect(_on_player_died)
	# Geri sayım / çöküş döngüsü yok: her 10 sn'de bir sarsıntı olur.
	quake = QuakeScript.new()
	quake.name = "quake"
	quake.game = self
	add_child(quake)
	quake.quake_started.connect(_on_quake_started)
	story = story_script.new()
	story.name = "story"
	story.game = self
	add_child(story)
	status.text = "Salondaki TV'yi kontrol et.   |   WASD / Oklar: hareket   •   E: etkileşim"


func _build_rooms() -> void:
	for rect in WALL_RECTS:
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collider := CollisionShape2D.new()
		collider.position = rect.get_center()
		collider.shape = shape
		$Walls.add_child(collider)


func _build_doors() -> void:
	var doors := Node2D.new()
	doors.name = "doors"
	add_child(doors)
	for row in DOOR_TRANSITIONS:
		_add_door(doors, row[0], row[1], row[2], row[3])


func _add_door(parent: Node2D, source: StringName, target: StringName,
	location: Vector2, size: Vector2) -> void:
	var door := Area2D.new()
	door.name = String(source) + "_to_" + String(target)
	door.position = location
	door.collision_layer = 0
	door.collision_mask = 2
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collider.shape = shape
	door.add_child(collider)
	parent.add_child(door)
	door.body_entered.connect(_on_door_entered.bind(source, target))


func _on_door_entered(body: Node2D, source: StringName, target: StringName) -> void:
	if body != player or not player.active or transitioning or current_room != source:
		return
	transitioning = true
	_change_room.call_deferred(target)


func _change_room(target: StringName) -> void:
	# Oyuncu ortak kapıdan yürür; dünya konumu değiştirilmez.
	_enter_room(target)
	await get_tree().physics_frame
	transitioning = false


func _enter_room(id: StringName) -> void:
	current_room = id
	apply_ambient()
	_update_camera_frame()
	objects.set_room(id)
	$Triggers/Switch.visible = false
	$Triggers/GasValve.visible = id == &"salon"
	$Triggers/TV.visible = false
	$Triggers/ExitDoor.visible = id == &"salon"
	queue_redraw()


func power_dead() -> bool:
	return electricity_off or lights_out


func apply_ambient() -> void:
	if ambient == null:
		return
	# Banyo karanlıkta da çok hafif daha aydınlık (fayans ve ayna ışığı yansıtır).
	var bath_lift := 0.04 if current_room == &"banyo" else 0.0
	if pitch_dark:
		ambient.color = PITCH_AMBIENT + Color(bath_lift, bath_lift, bath_lift * 1.2, 0)
	elif lights_out:
		ambient.color = BLACKOUT_AMBIENT + Color(bath_lift, bath_lift, bath_lift * 1.2, 0)
	else:
		ambient.color = ROOM_SKINS[current_room].get("ambient", Color.WHITE) if ROOM_SKINS.has(current_room) else Color.WHITE


func _skin_tex(path: String) -> Texture2D:
	if not skin_textures.has(path):
		# Güvenlik: yalnız res:// içindeki içe aktarılmış dokular.
		var tex: Texture2D = null
		if path.begins_with("res://assets/") and path.ends_with(".png") \
				and not path.contains("..") and ResourceLoader.exists(path):
			tex = load(path) as Texture2D
		skin_textures[path] = tex
	return skin_textures[path]


func _wall_face_height(id: StringName) -> float:
	if not ROOM_SKINS.has(id):
		return 0.0
	var skin: Dictionary = ROOM_SKINS[id]
	var lower := _skin_tex(skin["wall_lower"])
	var upper := _skin_tex(skin["wall_upper"])
	if lower == null or upper == null:
		return 0.0
	return (lower.get_height() + upper.get_height()) * float(skin["scale"]) + float(skin.get("upper_extra", 0.0))


func _room_frame(id: StringName) -> Rect2:
	# Dokulu odada üst duvar yüzü ve kapağı kadar kadraj yukarı uzar.
	var frame: Rect2 = ROOMS[id].grow(WALL_HALF_WIDTH)
	var face := _wall_face_height(id)
	if face > 0.0:
		frame = frame.grow_side(SIDE_TOP, face + WALL_CAP - 2.0 * WALL_HALF_WIDTH)
	return frame


func _update_camera_frame() -> void:
	var frame := _room_frame(current_room)
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	# Tüm odalar salonla aynı ölçekte görünür (küçük oda küçük görünsün); salon ekranı kaplar.
	var ref := _room_frame(&"salon")
	var fit_zoom := maxf(viewport_size.x / ref.size.x, viewport_size.y / ref.size.y)
	# Görüş alanından küçük oda ortalanır (kenarlarda duvar rengi kalır).
	var vis := viewport_size / fit_zoom
	if frame.size.x < vis.x:
		frame = frame.grow_individual((vis.x - frame.size.x) * 0.5, 0, (vis.x - frame.size.x) * 0.5, 0)
	if frame.size.y < vis.y:
		frame = frame.grow_individual(0, (vis.y - frame.size.y) * 0.5, 0, (vis.y - frame.size.y) * 0.5)
	# Oda geçişi sarsıntıyı kesmez; kamera offset'i sarsıntı betiğinde yönetilir.
	camera.position_smoothing_enabled = false
	camera.rotation_smoothing_enabled = false
	camera.drag_horizontal_enabled = false
	camera.drag_vertical_enabled = false
	camera.limit_smoothed = false
	camera.ignore_rotation = true
	camera.offset = Vector2.ZERO
	camera.zoom = Vector2.ONE * fit_zoom
	camera.limit_left = floori(frame.position.x)
	camera.limit_right = ceili(frame.end.x)
	camera.limit_top = floori(frame.position.y)
	camera.limit_bottom = ceili(frame.end.y)
	camera.global_position = player.global_position
	camera.make_current()
	camera.reset_smoothing()
	camera.reset_physics_interpolation()
	camera.force_update_scroll()
	RenderingServer.set_default_clear_color(ROOM_SKINS[current_room].get("trim", BACKGROUND_COLOR) if ROOM_SKINS.has(current_room) else BACKGROUND_COLOR)
	queue_redraw()


func _process(_delta: float) -> void:
	camera.global_position = player.global_position
	_tick_clock(_delta)


func _unhandled_input(event: InputEvent) -> void:
	if finished and player.active == false and event.is_action_pressed("restart"):
		if status.text.begins_with("KAZANDIN"):
			StoryScript.reset_loop()
			get_tree().reload_current_scene()


func _on_interaction(kind: int) -> void:
	if finished:
		return
	match kind:
		InteractionScript.Kind.SWITCH:
			electricity_off = true
			objects.on_power_off()
			status.text = "Şalter kapatıldı. Gaz vanasını da kapatıp üst kapıya ulaş."
		InteractionScript.Kind.GAS:
			gas_off = true
			objects.on_gas_off()
			status.text = "Gaz vanası kapatıldı."
		InteractionScript.Kind.TV:
			status.text = "TV kapalı: elektrik kesildi." if electricity_off else "TV: Deprem uyarısı! Banyodaki sigortayı ve salondaki gazı kapat; üst kapıdan çık."
		InteractionScript.Kind.EXIT:
			if not story.can_exit():
				status.text = story.exit_block_text()
			else:
				story.exit_house()


func _on_quake_started(first: bool) -> void:
	# Devrilme/yangın/alarm sonuçları yalnız ilk sarsıntıda tetiklenir (hasar tekrarlanmasın).
	if finished or not first:
		return
	status.text = "DEPREM! Bir eşyanın yanında çömel [C]."
	earthquake_started.emit()


func _win() -> void:
	finished = true
	_stop_round()
	status.text = "KAZANDIN — Hazırlıkları tamamlayıp evden çıktın.   |   R: yeniden oyna"
	countdown.text = ""
	escaped.emit()


func _stop_round() -> void:
	objects.close_minigame()
	player.active = false
	player.velocity = Vector2.ZERO
	quake.stop()


func _on_player_died() -> void:
	if finished:
		return
	finished = true
	_stop_round()
	status.text = "ÖLDÜN — Zaman döngüsü yeniden başlıyor..."
	countdown.text = ""
	# Ölüm animasyonu + geri sarılan saat; sonra döngü baştan.
	await story.death_sequence()
	get_tree().reload_current_scene()


func _draw() -> void:
	var room: Rect2 = ROOMS[current_room]
	var skinned := _wall_face_height(current_room) > 0.0
	var wall_line := room.position.y - WALL_HALF_WIDTH + 2.0 * WALL_HALF_WIDTH
	if skinned:
		var skin: Dictionary = ROOM_SKINS[current_room]
		var k: float = skin["scale"]
		# Duvar dışında kalan her alan da duvar kenar rengiyle doldurulur.
		draw_rect(_room_frame(current_room).grow(600), skin.get("trim", BACKGROUND_COLOR))
		_draw_tiled(_skin_tex(skin["floor"]), room, k)
		for rug in skin.get("rugs", []):
			var rug_tex := _skin_tex(rug[0])
			if rug_tex != null:
				var rug_size: Vector2 = Vector2(rug_tex.get_size()) * float(rug[2])
				draw_texture_rect(rug_tex, Rect2(rug[1] - rug_size / 2.0, rug_size), false)
	else:
		draw_rect(room, Color("30495c"))
		for x in range(int(room.position.x), int(room.end.x), 60):
			draw_line(Vector2(x, room.position.y), Vector2(x, room.end.y), Color("344e61"))
		for y in range(int(room.position.y), int(room.end.y), 60):
			draw_line(Vector2(room.position.x, y), Vector2(room.end.x, y), Color("344e61"))
	# Ortak duvar tek çarpıştırıcıdır; yalnız etkin odaya bakan yüzü çizilir.
	var frame := room.grow(WALL_HALF_WIDTH)
	for wall in WALL_RECTS:
		var visible_wall: Rect2 = frame.intersection(wall)
		if skinned and wall.position.y < room.position.y:
			continue
		if visible_wall.has_area():
			draw_rect(visible_wall, ROOM_SKINS[current_room].get("trim", Color("91a8b7")) if skinned else Color("91a8b7"))
	if skinned:
		_draw_wall_face(room, frame, wall_line)
	for door in DOOR_RECTS:
		var visible_door: Rect2 = frame.intersection(door)
		if skinned and door.position.y < room.position.y:
			continue
		if visible_door.has_area():
			draw_rect(visible_door, Color("c59d70"))
			if door.position.y == 393.0:
				draw_rect(visible_door, Color("6e5236"), false, 3)
				draw_circle(Vector2(door.end.x - 16, door.get_center().y), 4, Color("e7c35a"))


func _draw_tiled(tex: Texture2D, rect: Rect2, k: float) -> void:
	if tex == null:
		return
	draw_set_transform(rect.position, 0.0, Vector2(k, k))
	draw_texture_rect(tex, Rect2(Vector2.ZERO, rect.size / k), true)
	draw_set_transform(Vector2.ZERO)


func _draw_wall_face(room: Rect2, frame: Rect2, wall_line: float) -> void:
	var skin: Dictionary = ROOM_SKINS[current_room]
	var k: float = skin["scale"]
	var lower := _skin_tex(skin["wall_lower"])
	var upper := _skin_tex(skin["wall_upper"])
	var lower_h := lower.get_height() * k
	var upper_h := upper.get_height() * k + float(skin.get("upper_extra", 0.0))
	var face_top := wall_line - lower_h - upper_h
	var x0 := frame.position.x + 2.0 * WALL_HALF_WIDTH
	var width := frame.size.x - 4.0 * WALL_HALF_WIDTH
	# Üst duvarın dikey yüzü: alt lambri + üst duvar kâğıdı, aralıksız üst üste.
	var upper_base := upper.get_height() * k
	_draw_tiled(upper, Rect2(x0, face_top, width, upper_h - upper_base), k)
	_draw_tiled(upper, Rect2(x0, wall_line - lower_h - upper_base, width, upper_base), k)
	_draw_tiled(lower, Rect2(x0, wall_line - lower_h, width, lower_h), k)
	# Duvar kapağı ve yan duvarların yukarı uzayan üst yüzleri (köşe birleşimi).
	var cap_top := face_top - WALL_CAP
	draw_rect(Rect2(frame.position.x, cap_top, frame.size.x, WALL_CAP), skin.get("trim", Color("91a8b7")))
	draw_rect(Rect2(frame.position.x, cap_top, 2.0 * WALL_HALF_WIDTH, wall_line - cap_top), skin.get("trim", Color("91a8b7")))
	draw_rect(Rect2(frame.end.x - 2.0 * WALL_HALF_WIDTH, cap_top, 2.0 * WALL_HALF_WIDTH, wall_line - cap_top), skin.get("trim", Color("91a8b7")))
	draw_line(Vector2(x0, face_top), Vector2(x0 + width, face_top), Color("5d6f7b"), 2)
	draw_line(Vector2(x0, wall_line), Vector2(x0 + width, wall_line), Color("3b2a1c"), 2)
	_draw_wall_damage(x0, face_top, width, wall_line)
	for win in skin.get("windows", []):
		var win_tex := _skin_tex(win[0])
		if win_tex != null:
			var win_size := Vector2(win_tex.get_size()) * k
			draw_texture_rect(win_tex, Rect2(Vector2(float(win[1]) - win_size.x / 2.0,
				wall_line - lower_h - win_size.y), win_size), false)
	# Duvara gömülü giriş kapısı (üst duvardaki kapı açıklığına oturur).
	var door_tex: Texture2D = _skin_tex(skin["door"]) if skin.has("door") else null
	for door in DOOR_RECTS:
		if door.position.y >= room.position.y or not frame.intersects(door):
			continue
		if door_tex != null:
			var door_size := Vector2(door_tex.get_size()) * k
			var door_rect := Rect2(Vector2(door.get_center().x - door_size.x / 2.0, wall_line - door_size.y), door_size)
			draw_rect(door_rect.grow_individual(4, 4, 4, 0), Color("2b1d14"))
			if door_open > 0.0:
				# Açık kapının ardında gece: koyu lacivert dışarı ve sokak lambasının sarı hüzmesi.
				draw_rect(door_rect, Color(0.05, 0.07, 0.14))
				draw_colored_polygon(PackedVector2Array([door_rect.position + Vector2(door_rect.size.x * 0.6, 0),
					door_rect.position + Vector2(door_rect.size.x, 0), door_rect.end, door_rect.end - Vector2(door_rect.size.x * 0.75, 0)]), Color(1.0, 0.85, 0.5, 0.18))
				draw_rect(Rect2(door_rect.position.x, door_rect.end.y - 6, door_rect.size.x, 6), Color(0.12, 0.12, 0.16))
				# Kapı kanadı menteşede (sol kenar) döner: genişliği daralır, iç yüzü gölgeli.
				var leaf_w := door_rect.size.x * (1.0 - 0.82 * door_open)
				draw_texture_rect(door_tex, Rect2(door_rect.position, Vector2(leaf_w, door_rect.size.y)), false, Color(1, 1, 1).lerp(Color(0.55, 0.5, 0.48), door_open))
				# Içeri sızan sıcak ışık zemine düşer.
				draw_colored_polygon(PackedVector2Array([Vector2(door_rect.position.x + 6, door_rect.end.y), Vector2(door_rect.end.x - 2, door_rect.end.y),
					Vector2(door_rect.end.x + 18, door_rect.end.y + 60 * door_open), Vector2(door_rect.position.x - 10, door_rect.end.y + 60 * door_open)]), Color(0.75, 0.82, 1.0, 0.12 * door_open))
			else:
				draw_texture_rect(door_tex, door_rect, false)
			continue
		# Kapısız geçit: ahşap kasa ve içeride karşı odanın loş görüntüsü.
		var door_h := minf(lower_h + upper_h * 0.55, wall_line - face_top)
		var outer := Rect2(door.position.x - 6, wall_line - door_h, door.size.x + 12, door_h)
		draw_rect(outer, Color("4a3424"))
		var opening := outer.grow_individual(-8, -8, -8, 0)
		draw_rect(opening, Color("2a1d15"))
		draw_rect(Rect2(opening.position.x, opening.end.y - opening.size.y * 0.35, opening.size.x, opening.size.y * 0.35), Color("5a3d28"))
		draw_rect(Rect2(opening.position, Vector2(opening.size.x, 6)), Color(0, 0, 0, 0.35))


# Soyulmuş sıva yamaları (tuğla örgüsü görünür, yırtık sıva kenarı açık renk) ve aşağı inen çatlaklar.
# Her oda için sabit tohum: aynı oda her bakışta aynı hasarı gösterir.
func _draw_wall_damage(x0: float, top: float, width: float, bottom: float) -> void:
	if wall_damage <= 0.0:
		return
	var a := wall_damage
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(current_room)) + 7
	var h := bottom - top
	for i in 7:
		var cx := x0 + rng.randf_range(0.05, 0.95) * width
		var cy := top + rng.randf_range(0.18, 0.86) * h
		var rx := rng.randf_range(12.0, 28.0)
		var ry := rng.randf_range(9.0, 20.0)
		var poly := PackedVector2Array()
		for k in 10:
			var ang := TAU * k / 10.0
			var rr := rng.randf_range(0.6, 1.15)
			poly.append(Vector2(cx + cos(ang) * rx * rr, cy + sin(ang) * ry * rr))
		draw_colored_polygon(poly, Color(0.42, 0.24, 0.16, a))
		# Tuğla örgüsü: yalnız yamanın içine düşen tuğlalar.
		var bb := Rect2(cx - rx * 1.2, cy - ry * 1.2, rx * 2.4, ry * 2.4)
		var row := 0
		var y := bb.position.y
		while y < bb.end.y:
			var x := bb.position.x - (4.0 if row % 2 == 1 else 0.0)
			while x < bb.end.x:
				if Geometry2D.is_point_in_polygon(Vector2(x + 4.0, y + 2.0), poly):
					var shade := 0.9 + 0.2 * rng.randf()
					draw_rect(Rect2(x + 0.6, y + 0.6, 6.8, 2.8), Color(0.66 * shade, 0.38 * shade, 0.26 * shade, a))
				x += 8.0
			y += 4.0
			row += 1
		# Yırtık sıva kenarı: açık renk dudak, altında ince gölge.
		var rim := poly.duplicate()
		rim.append(poly[0])
		draw_polyline(rim, Color(0.94, 0.89, 0.8, 0.85 * a), 1.6)
		var lower_edge := PackedVector2Array()
		for k in range(1, 5):
			lower_edge.append(poly[k] + Vector2(0, 1.5))
		draw_polyline(lower_edge, Color(0.15, 0.09, 0.06, 0.45 * a), 1.2)
	for i in 5:
		var p := Vector2(x0 + rng.randf_range(0.04, 0.96) * width, top + rng.randf_range(0.0, 0.35) * h)
		var pts := PackedVector2Array([p])
		for step in 8:
			p += Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(5.0, 12.0))
			if p.y > bottom:
				break
			pts.append(p)
		if pts.size() < 2:
			continue
		draw_polyline(pts, Color(0.1, 0.07, 0.05, 0.8 * a), 1.5)
		if pts.size() > 3 and rng.randf() < 0.6:
			var fork := pts[2]
			draw_line(fork, fork + Vector2(rng.randf_range(-10.0, 10.0), rng.randf_range(6.0, 12.0)), Color(0.1, 0.07, 0.05, 0.6 * a), 1.0)


# Zaman atlaması (enkazda uyku): analog saat aynı saat değişkeninden okur.
func jump_clock(hours: float) -> void:
	clock_seconds += hours * 3600.0


func reset_clock() -> void:
	clock_seconds = 0.0


# Ekranda saat gösterilmez; clock_seconds yalnız iç zamanlama için tutulur.
func _build_clock() -> void:
	pass


func _tick_clock(delta: float) -> void:
	clock_seconds += delta * time_scale
