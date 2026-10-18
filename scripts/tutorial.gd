extends CanvasLayer

# Oyun başı eğitimi: her adımda oyuncunun ilgili kontrolü gerçekten kullanması beklenir.
# 1 WASD hareket · 2 sol Shift koş · 3 C ile çömelme · 4 F envanter · 5 E masadan nesne al
# · 6 Q bırak · 7 süre bilgisi (30 sn sonra deprem, depremden sonra 70 sn içinde çıkılmazsa enkaz; E ile geçilir).
signal finished

const TaskPath = preload("res://scripts/task_path.gd")
const PICKUP_STEP := 4

const STEPS := [
	["HAREKET", "Karakteri WASD ya da ok tuşlarıyla (← ↑ → ↓) kontrol et ve yürü.", "WASD"],
	["KOŞ", "Hareket ederken sol Shift'i basılı tutarak koş.", "SHIFT"],
	["ÇÖMEL", "Başına bir şey düşmesini önlemek için eşyaların yanında çömelmelisin. Bu adımı tamamlamak için C'ye bir kez bas.", "C"],
	["ENVANTER", "F ile envanterini aç.", "F"],
	["NESNE AL", "Telefon masasına git, matkabın yanında E'ye bas ve onu masadan al.", "E"],
	["NESNE BIRAK", "F ile envanteri aç, eşyayı seç ve Q ile yere bırak.", "Q"],
	["SÜRE", "Telefon çalınca sayaç başlar: 30 saniye sonra deprem olur. Depremden sonra 70 saniye içinde evden çıkamazsan enkaz altında kalırsın.\n[E] ya da tıkla: Anladım", "E"],
]
const TIME_STEP := 6

var story: Node
var game: Node2D
var step := 0
var moved := 0.0
var sprint_time := 0.0
var last_pos := Vector2.ZERO
var start_items := 0
var start_drops := 0
var done_flash := 0.0
var time := 0.0
var step_time := 0.0
var e_was_down := true
var canvas: Control


func _ready() -> void:
	layer = 24
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_box)
	add_child(canvas)
	last_pos = game.player.global_position
	game.status.text = "Eğitim"


func _advance() -> void:
	done_flash = 0.6
	step += 1
	step_time = 0.0
	var world: Node2D = game.objects
	if step == 3:
		story.safety.tutorial_cover = false
	elif step == 4:
		start_items = world.slot_order.size()
	elif step == 5:
		start_drops = world.drop_count
	if step >= STEPS.size():
		story.safety.tutorial_cover = false
		await get_tree().create_timer(0.8).timeout
		finished.emit()
		queue_free()


func _process(delta: float) -> void:
	time += delta
	done_flash = maxf(0.0, done_flash - delta)
	canvas.queue_redraw()
	if step >= STEPS.size():
		return
	var p: Node2D = game.player
	var world: Node2D = game.objects
	match step:
		0:
			moved += p.global_position.distance_to(last_pos)
			last_pos = p.global_position
			if moved > 90.0:
				_advance()
		1:
			sprint_time = sprint_time + delta if p.sprinting else 0.0
			if sprint_time > 0.4:
				_advance()
		2:
			# Eğitimde tek basış yeterli; eşya, konum veya basılı tutma şartı yok.
			if Input.is_action_just_pressed("crouch"):
				_advance()
		3:
			if world.inventory_ui.open:
				_advance()
		4:
			if world.slot_order.size() > start_items:
				_advance()
		5:
			if world.drop_count > start_drops:
				_advance()
		TIME_STEP:
			# Süre bilgisi: okunsun diye en az 1.5 sn kalır; E'ye yeni basılınca geçilir.
			step_time += delta
			var e_down := Input.is_physical_key_pressed(KEY_E) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			if step_time > 1.5 and e_down and not e_was_down:
				_advance()
			e_was_down = e_down


# Nesne alma adımında parlayan eşyalar: masadaki matkap ve vidalar (alınan eşya listeden çıkar).
func _pickup_targets() -> Array:
	var out: Array = []
	if step != PICKUP_STEP:
		return out
	for kind in ["drill", "nails"]:
		var it: Area2D = game.objects.find_item(kind)
		if it != null and it.visible and it.room == game.current_room:
			out.append(it)
	return out


func _draw_box() -> void:
	var targets := _pickup_targets()
	if step >= STEPS.size() and done_flash <= 0.0:
		return
	var view := canvas.size
	var font := ThemeDB.fallback_font
	var i := mini(step, STEPS.size() - 1)
	var data: Array = STEPS[i]
	# Uzun yazılı adımda kutu metne göre büyür.
	var text_h := font.get_multiline_string_size(data[1], HORIZONTAL_ALIGNMENT_LEFT, 524, 20).y
	var box_h := maxf(118.0, text_h + 86.0)
	var box := Rect2(Vector2(view.x * 0.5 - 330, view.y - 78 - box_h), Vector2(660, box_h))
	# Kutu parlayan eşyaların ya da karakterin üstüne denk gelirse ekranın üstüne alınır.
	var cover_check := box.grow(40.0)
	var blocked := cover_check.has_point(story.to_screen(game.player.global_position + Vector2(0, -40)))
	for it in targets:
		if cover_check.has_point(story.to_screen(TaskPath.item_center(it)[0])):
			blocked = true
	if blocked:
		box.position.y = 112.0
	# Piksel tarzı kutu: koyu ahşap zemin, kalın sıcak kenar, köşelerde küçük kareler.
	canvas.draw_rect(box.grow(4), Color(0.05, 0.03, 0.02, 0.9))
	canvas.draw_rect(box, Color(0.16, 0.11, 0.08, 0.95))
	canvas.draw_rect(box, Color(0.92, 0.7, 0.38), false, 3.0)
	for c in [box.position, Vector2(box.end.x - 6, box.position.y), Vector2(box.position.x, box.end.y - 6), box.end - Vector2(6, 6)]:
		canvas.draw_rect(Rect2(c, Vector2(6, 6)), Color(0.92, 0.7, 0.38))
	# Tuş simgesi.
	var key := Rect2(box.position + Vector2(20, 24), Vector2(76, 70))
	var pulse := 0.65 + 0.35 * sin(time * 5.0)
	canvas.draw_rect(Rect2(key.position + Vector2(0, 6), key.size), Color(0.35, 0.25, 0.15))
	canvas.draw_rect(key, Color(0.95, 0.88, 0.72))
	canvas.draw_rect(key, Color(0.45, 0.3, 0.18), false, 3.0)
	canvas.draw_string(font, key.position + Vector2(0, 46), data[2], HORIZONTAL_ALIGNMENT_CENTER, key.size.x, 26 if data[2].length() > 2 else 34, Color(0.25, 0.15, 0.08))
	canvas.draw_string(font, box.position + Vector2(118, 36), "EĞİTİM %d/%d — %s" % [i + 1, STEPS.size(), data[0]], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.82, 0.5, pulse))
	canvas.draw_multiline_string(font, box.position + Vector2(118, 66), data[1], HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 136, 20, -1, Color(0.96, 0.92, 0.85))
	# İlerleme noktaları.
	for d in STEPS.size():
		var dot := Vector2(box.end.x - 20 - (STEPS.size() - 1 - d) * 16, box.position.y + 18)
		canvas.draw_rect(Rect2(dot - Vector2(4, 4), Vector2(8, 8)), Color(0.5, 0.9, 0.5) if d < step else (Color(1, 0.8, 0.4) if d == step else Color(1, 1, 1, 0.25)))
	if done_flash > 0.0:
		canvas.draw_string(font, box.position + Vector2(0, -14), "Tamam!", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 24, Color(0.55, 1, 0.55, done_flash / 0.6))
	# Parıltılar kutunun da üstünde çizilir (hiçbir zaman örtülmesin).
	for k in targets.size():
		TaskPath.sparkle_item(canvas, story, targets[k], k, time)
