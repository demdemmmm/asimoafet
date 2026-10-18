extends CanvasLayer

# Envanter paneli: F ile açılır/kapanır. 5 yuva; ←/→ seç, E: eline al / elinden bırak, Q: yere bırak.
# 1-5 tuşları panel kapalıyken de o yuvadaki eşyayı ele alır. Çanta yuvasının altında içindeki erzak.

const ICONS := {
	"fire_extinguisher": "res://assets/furniture/extinguisher_nopin.png",
	"quake_bag": "res://assets/rubble/bag_closed.png",
	"bandage": "res://assets/rubble/item_bandage.png",
	"food": "res://assets/rubble/item_food.png",
	"water_bottle": "res://assets/rubble/item_water.png",
	"whistle": "res://assets/rubble/item_whistle.png",
}
const SLOT := 104.0

var world: Node2D
var open := false
var cursor := 0
var anim := 0.0
var canvas: Control
var textures := {}


func _ready() -> void:
	layer = 26
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw.connect(_draw_ui)
	add_child(canvas)
	for id in ICONS:
		textures[id] = load(ICONS[id])


func _player() -> Node2D:
	return world.game.player


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_mouse_input(event)
		return
	if not (event is InputEventKey) or not event.pressed or event.echo or world.game.finished:
		return
	var key: int = event.physical_keycode
	var p := _player()
	if key == KEY_F:
		if open:
			_close()
		elif p.active and not p.input_locked:
			open = true
			cursor = clampi(cursor, 0, maxi(0, world.slot_order.size() - 1))
			p.input_locked = true
			p.velocity = Vector2.ZERO
		get_viewport().set_input_as_handled()
		return
	if key >= KEY_1 and key <= KEY_5:
		var i := key - KEY_1
		if (open or (p.active and not p.input_locked)) and i < world.slot_order.size():
			world.equip(world.slot_order[i])
			cursor = i
			get_viewport().set_input_as_handled()
		return
	if not open:
		return
	get_viewport().set_input_as_handled()
	var n: int = world.slot_order.size()
	match key:
		KEY_ESCAPE:
			_close()
		KEY_LEFT, KEY_A:
			if n > 0:
				cursor = (cursor + n - 1) % n
		KEY_RIGHT, KEY_D:
			if n > 0:
				cursor = (cursor + 1) % n
		KEY_E, KEY_ENTER:
			if cursor < n:
				world.equip(world.slot_order[cursor])
		KEY_Q:
			if cursor < n:
				world.drop(world.slot_order[cursor])
				cursor = clampi(cursor, 0, maxi(0, world.slot_order.size() - 1))


func _panel_rect() -> Rect2:
	var k := 1.0 - pow(1.0 - anim, 3.0)
	return Rect2(Vector2(12, 10 - (1.0 - k) * 120), Vector2(SLOT * world.SLOTS + 16 * (world.SLOTS - 1) + 48, 210))


func _mouse_input(event: InputEventMouseButton) -> void:
	if world.game.finished:
		return
	var p := _player()
	var mouse: Vector2 = canvas.make_input_local(event).position
	if open:
		get_viewport().set_input_as_handled()
		p.mouse_interact_held = false
		if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			return
		var panel := _panel_rect()
		if not panel.has_point(mouse) or Rect2(panel.position + Vector2(panel.size.x - 84, 8), Vector2(72, 30)).has_point(mouse):
			_close()
			return
		for i in world.SLOTS:
			var slot := Rect2(panel.position + Vector2(24 + i * (SLOT + 16), 52), Vector2(SLOT, SLOT))
			if slot.has_point(mouse) and i < world.slot_order.size():
				cursor = i
				if event.button_index == MOUSE_BUTTON_RIGHT:
					world.drop(world.slot_order[i])
					cursor = clampi(cursor, 0, maxi(0, world.slot_order.size() - 1))
				else:
					world.equip(world.slot_order[i])
				return
		return
	if not p.active or p.input_locked or event.button_index != MOUSE_BUTTON_LEFT:
		return
	for i in world.SLOTS:
		if Rect2(Vector2(12 + i * 58, 10), Vector2(52, 52)).has_point(mouse):
			get_viewport().set_input_as_handled()
			p.mouse_interact_held = false
			if i < world.slot_order.size():
				cursor = i
				world.equip(world.slot_order[i])
			return
	if Rect2(Vector2(12 + world.SLOTS * 58, 10), Vector2(58, 52)).has_point(mouse):
		get_viewport().set_input_as_handled()
		p.mouse_interact_held = false
		open = true
		p.input_locked = true
		p.velocity = Vector2.ZERO


func _close() -> void:
	open = false
	# E'nin aynı karede etkileşime dönüşmemesi için kilit bir kare sonra açılır.
	await get_tree().process_frame
	_player().input_locked = false


# Ara sahne başlarken panel kapanır ama kilit bırakılmaz; kilidi sahne yönetir.
func force_close() -> void:
	open = false


func _process(delta: float) -> void:
	# Panel açıkken kilit panelindir: başka bir akış (eğitim sonu, deprem başlangıcı) kilidi açarsa
	# karakter panel açıkken yürümesin.
	if open:
		var p := _player()
		if world.game.finished or not p.active:
			open = false
		elif not p.input_locked:
			p.input_locked = true
			p.velocity = Vector2.ZERO
	anim = move_toward(anim, 1.0 if open else 0.0, delta * 6.0)
	canvas.queue_redraw()


# Her zaman görünen küçük hotbar: ekranın en sol üst köşesi. Panel açılınca onun yerini alır.
func _draw_hotbar() -> void:
	var font := ThemeDB.fallback_font
	var a := 1.0 - anim
	if a <= 0.0 or world.game.finished:
		return
	const HB := 52.0
	var origin := Vector2(12, 10)
	canvas.draw_rect(Rect2(origin - Vector2(4, 4), Vector2(HB * world.SLOTS + 6 * (world.SLOTS - 1) + 8, HB + 8)), Color(0.08, 0.06, 0.04, 0.7 * a))
	for i in world.SLOTS:
		var r := Rect2(origin + Vector2(i * (HB + 6), 0), Vector2(HB, HB))
		var id: String = world.slot_order[i] if i < world.slot_order.size() else ""
		var eq: bool = id != "" and id == world.equipped
		canvas.draw_rect(r, Color(0.2, 0.15, 0.1, 0.85 * a))
		canvas.draw_rect(r, Color(1, 0.82, 0.3, a) if eq else Color(1, 1, 1, 0.25 * a), false, 3.0 if eq else 1.5)
		canvas.draw_string(font, r.position + Vector2(4, 13), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55 * a))
		if id != "":
			_draw_icon(id, r.grow(-9), a)
			var count := int(world.inventory.get(id, 1))
			if count > 1:
				canvas.draw_string(font, r.end - Vector2(24, 4), "×%d" % count, HORIZONTAL_ALIGNMENT_RIGHT, 22, 12, Color(1, 1, 1, a))
	var hint := origin + Vector2(world.SLOTS * (HB + 6) + 6, 32)
	canvas.draw_string(font, hint, "[F]", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.9, 0.7, 0.8 * a))


func _draw_ui() -> void:
	_draw_hotbar()
	if anim <= 0.0:
		return
	var view := canvas.size
	var font := ThemeDB.fallback_font
	var k := 1.0 - pow(1.0 - anim, 3.0)
	# En sol üst köşe: hotbar'ın yerinde, yukarıdan kayarak açılır.
	var panel := _panel_rect()
	canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.35 * k))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.08, 0.06, 0.94 * k)
	style.border_color = Color(0.85, 0.62, 0.3, k)
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.draw(canvas.get_canvas_item(), panel)
	canvas.draw_string(font, panel.position + Vector2(24, 34), "ENVANTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 0.85, 0.6, k))
	canvas.draw_string(font, panel.position + Vector2(0, 34), "%d / %d" % [world.slot_order.size(), world.SLOTS], HORIZONTAL_ALIGNMENT_RIGHT, panel.size.x - 100, 20, Color(1, 1, 1, 0.6 * k))
	canvas.draw_string(font, panel.position + Vector2(panel.size.x - 76, 30), "KAPAT", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.9, 0.7, k))
	for i in world.SLOTS:
		var r := Rect2(panel.position + Vector2(24 + i * (SLOT + 16), 52), Vector2(SLOT, SLOT))
		var id: String = world.slot_order[i] if i < world.slot_order.size() else ""
		var is_cursor: bool = i == cursor and id != ""
		var is_equipped: bool = id != "" and id == world.equipped
		canvas.draw_rect(r, Color(1, 1, 1, 0.06 * k))
		var border := Color(1, 0.82, 0.3, k) if is_equipped else (Color(1, 1, 1, 0.75 * k) if is_cursor else Color(1, 1, 1, 0.18 * k))
		canvas.draw_rect(r, border, false, 4.0 if (is_equipped or is_cursor) else 2.0)
		canvas.draw_string(font, r.position + Vector2(6, 18), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.5 * k))
		if id == "":
			continue
		_draw_icon(id, r.grow(-18), k)
		canvas.draw_string(font, Vector2(r.position.x, r.end.y + 18), world.NAMES.get(id, id), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, Color(1, 1, 1, 0.9 * k))
		var count := int(world.inventory.get(id, 1))
		if count > 1:
			canvas.draw_string(font, r.end - Vector2(30, 8), "×%d" % count, HORIZONTAL_ALIGNMENT_RIGHT, 26, 15, Color(1, 1, 1, k))
		if is_equipped:
			canvas.draw_string(font, Vector2(r.position.x, r.position.y - 6), "ELDE", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, Color(1, 0.82, 0.3, k))
		if id == "quake_bag":
			# Çantanın içindekiler: küçük simgeler.
			var x := r.position.x + 4
			for b in world.BAG_KINDS:
				if world.has_item(b):
					_draw_icon(b, Rect2(Vector2(x, r.end.y + 26), Vector2(22, 22)), k)
					x += 25
	canvas.draw_string(font, Vector2(panel.position.x, panel.end.y - 12), "Tıkla / E: al-bırak  •  Sağ tık / Q: yere bırak  •  F / dışarı tıkla: kapat", HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 15, Color(1, 0.9, 0.7, 0.75 * k))


# Simgeler: dokusu olanlar dokudan, fener/matkap/vida çizimle.
func _draw_icon(id: String, r: Rect2, k: float) -> void:
	if textures.has(id):
		var tex: Texture2D = textures[id]
		var src := Rect2(Vector2.ZERO, tex.get_size())
		if id == "fire_extinguisher":
			src = Rect2(16, 7, 57, 79)
		var aspect := src.size.x / src.size.y
		var size := Vector2(r.size.y * aspect, r.size.y) if aspect < 1.0 else Vector2(r.size.x, r.size.x / aspect)
		canvas.draw_texture_rect_region(tex, Rect2(r.get_center() - size * 0.5, size), src, Color(1, 1, 1, k))
		return
	var c := r.get_center()
	match id:
		"flashlight":
			# Kafa lambası simgesi: siyah kayış halkası + önde lamba ve sarı cam.
			canvas.draw_set_transform(c, 0.0, Vector2(1.0, 0.6))
			canvas.draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 32, Color(0.08, 0.08, 0.08, k), 6.0)
			canvas.draw_set_transform(Vector2.ZERO)
			canvas.draw_rect(Rect2(c + Vector2(-11, 4), Vector2(22, 15)), Color(0.12, 0.12, 0.13, k))
			canvas.draw_rect(Rect2(c + Vector2(-11, 4), Vector2(22, 3)), Color(0.33, 0.35, 0.36, k))
			canvas.draw_circle(c + Vector2(0, 12), 5.0, Color(1, 0.88, 0.5, k))
		"drill":
			canvas.draw_rect(Rect2(c + Vector2(-26, -18), Vector2(40, 18)), Color(0.88, 0.69, 0.13, k))
			canvas.draw_rect(Rect2(c + Vector2(14, -14), Vector2(10, 10)), Color(0.55, 0.56, 0.58, k))
			canvas.draw_line(c + Vector2(24, -9), c + Vector2(34, -9), Color(0.8, 0.82, 0.84, k), 3.0)
			canvas.draw_rect(Rect2(c + Vector2(-16, 0), Vector2(14, 24)), Color(0.16, 0.16, 0.16, k))
			canvas.draw_rect(Rect2(c + Vector2(-20, 20), Vector2(22, 8)), Color(0.24, 0.24, 0.24, k))
		"nails":
			canvas.draw_rect(Rect2(c + Vector2(-22, -6), Vector2(44, 28)), Color(0.69, 0.53, 0.31, k))
			canvas.draw_rect(Rect2(c + Vector2(-22, -6), Vector2(44, 28)), Color(0.37, 0.27, 0.14, k), false, 2.0)
			for i in 4:
				var x := -15.0 + i * 10.0
				canvas.draw_line(c + Vector2(x, -6), c + Vector2(x, -22), Color(0.8, 0.82, 0.84, k), 2.5)
				canvas.draw_circle(c + Vector2(x, -22), 3.5, Color(0.88, 0.89, 0.9, k))
		_:
			canvas.draw_circle(c, 16.0, Color(1, 1, 1, 0.3 * k))
