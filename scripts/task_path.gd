extends CanvasLayer

# Görev yolu: oyuncunun sırayla ilerleyeceği görevler. Sol üstte yalnız şu an yapılması gereken görev
# büyük yazıyla görünür ("GÖREV 3 / 9" + ilerleme noktaları); görev bitince yeşil tikle yukarı kayıp
# söner, sıradaki görev soldan gelir. Sıradaki görevin;
# hedefi başka odadaysa ışıltı rehberi (Guide) o odanın kapısına, aynı odadaysa hedefin üstünde
# ufak parıltılar (göz kırpan yıldızcıklar ve hafif hale) yol gösterir; ok yoktur. Önceden yapılan görev
# sırası gelince kendiliğinden tamamlanır. Erzak görevinde (önceki görevler bitip çanta alınmışsa) dört
# eşyanın her biri ayrı parıldar.
# En son görev evden çıkmaktır (dış sahne ve sonlar).

const SUPPLIES := ["bandage", "water_bottle", "whistle", "food"]
const SUPPLY_TASK := 7

var story: Node
var canvas: Control
var time := 0.0
var flash := 0.0
var last_current := -1
# Panel görünürlüğü: karakter ya da konuşma balonu panelin üstüne gelince solar, uzaklaşınca geri gelir.
var panel_alpha := 1.0
const PANEL_POS := Vector2(18, 162)
const PANEL_W := 620.0
const TASK_SIZE := 27
const HEAD_SIZE := 18
const PANEL_H := 108.0
# Görev değişim geçişi: önce eski görev tikle söner, sonra yenisi kayarak gelir.
const OUT_TIME := 0.55
const IN_TIME := 0.35
var prev_title := ""
var change_t := 99.0
# Parıltı halesinin ekrandaki en küçük / en büyük yarıçapı.
const SPARKLE_MIN := 24.0
const SPARKLE_MAX := 46.0


func _ready() -> void:
	layer = 22
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_panel)
	add_child(canvas)


# Görev listesi yalnız hikâye, dünya, oyuncu ve yangın alanı hazırken hesaplanır (hata vermesin).
func _ready_to_list() -> bool:
	return story != null and is_instance_valid(story) and story.game != null and is_instance_valid(story.game) \
		and story.world != null and is_instance_valid(story.world) and story.game.player != null \
		and story.fire_field != null and is_instance_valid(story.fire_field)


func _fire_out() -> bool:
	var ff: Node2D = story.fire_field
	return story.quake_begun and not ff.active and ff.fires.size() > 0


func _missing_supplies() -> Array:
	var out: Array = []
	for k in SUPPLIES:
		if not story.world.has_item(k):
			var it: Area2D = story.world.find_item(k)
			if it != null:
				out.append(it)
	return out


# [başlık, tamamlandı mı, hedef düğüm, oda, (isteğe bağlı) hedef nokta]
func _tasks() -> Array:
	var w: Node2D = story.world
	var g: Node2D = story.game
	var list: Array = []
	list.append(["Banyodaki suyu ve elektriği düzelt (sigorta kutusu)", w.leak_repaired, w.find_item("electrical_box"), &"salon"])
	list.append(["Kafa lambasını al (banyo)", w.has_item("flashlight") or story.torch != null, w.find_item("flashlight"), &"banyo"])
	var tools_ok: bool = (w.has_item("drill") and w.has_item("nails")) or story._trap_secured()
	var tool_target: Node2D = w.find_item("drill") if not w.has_item("drill") else w.find_item("nails")
	list.append(["Matkap ve çivileri al (telefon masası)", tools_ok, tool_target, &"salon"])
	# Yangın: tüp alınmadıysa önce tüp, sonra yanan alevler.
	var fire_target: Node2D = null if story.has_tool else w.find_item("fire_extinguisher")
	var fire_point: Vector2 = Vector2.ZERO
	if fire_target == null and story.fire_field.active:
		fire_point = story.fire_field.nearest_burning(g.player.global_position)
	var fire_title := "Yangın tüpüyle yatak odasındaki yangını söndür" if story.quake_begun or story.has_tool \
		else "Yangın tüpünü al (yatak odası) — yangın depremle çıkar"
	list.append([fire_title, _fire_out(), fire_target, &"yatak_odasi", fire_point])
	var trap: Node2D = null
	for wr in story._trap_wardrobes():
		if not wr.anchored:
			trap = wr
			break
	list.append(["Yatak odasındaki dolabı duvara çivile", story._trap_secured(), trap, &"yatak_odasi"])
	var bag_box: Node2D = null
	for wr in story._trap_wardrobes():
		if wr.holds_bag:
			bag_box = wr
	list.append(["Dolabın içinden deprem çantasını al", w.has_item("quake_bag"), bag_box, &"yatak_odasi"])
	var cat: Node2D = w.find_item("cat")
	list.append(["Osman'ı kurtar", g.player.cat_follower or g.player.carry_cat or w.has_item("cat"), cat, &"yatak_odasi"])
	# Erzak: odadaki eksik eşya öncelikli; yoksa ilk eksiğin odası.
	var missing := _missing_supplies()
	var sup_target: Node2D = null
	for it in missing:
		if it.room == g.current_room:
			sup_target = it
			break
	if sup_target == null and not missing.is_empty():
		sup_target = missing[0]
	list.append(["Sargı bezi, su, düdük ve konserveyi topla (%d/4)" % (4 - missing.size()), missing.is_empty(),
		sup_target, sup_target.room if sup_target != null else &"mutfak"])
	if story.front_blocked:
		# Ön kapı enkazla kapandı: çıkış yok; hedef gösterilmez (rehber de kapıya çağırmaz).
		list.append(["Ön kapı kapandı! Osman'la güvenli bir köşeye sığın, enkaza hazırlan", false, null, g.current_room])
	else:
		list.append(["Süre bitmeden evden çık (ön kapı)" if story.exit_unlocked() else "Evden çık (önce kafa lambası ya da Osman)",
			story.left_house, null, &"salon", story.EXIT_POINT])
	return list


func _current(list: Array) -> int:
	for i in list.size():
		if not list[i][1]:
			return i
	return -1


func _process(delta: float) -> void:
	time += delta
	flash = maxf(0.0, flash - delta)
	if not _ready_to_list():
		visible = false
		return
	var g: Node2D = story.game
	visible = story.phase >= 1 and not g.finished and not story.collapsing
	if not visible:
		return
	var target := 1.0 if not _covers_player() else 0.15
	panel_alpha = move_toward(panel_alpha, target, delta * 4.0)
	var list := _tasks()
	var cur := _current(list)
	change_t += delta
	if cur != last_current:
		if last_current != -1 and last_current < list.size():
			prev_title = list[last_current][0]
			change_t = 0.0
			flash = 1.2
		last_current = cur
	# Odalar arası yön: ışıltı rehberi sıradaki görevin odasına götürür.
	if cur != -1 and not g.player.input_locked:
		var t: Array = list[cur]
		var guide = story.guide
		guide.target_room = t[3]
		guide.target_node = t[2] if t[2] != null and is_instance_valid(t[2]) else null
		guide.target_offset = Vector2(0, -60)
		if guide.target_node == null:
			guide.target_point = t[4] if t.size() > 4 and t[4] != Vector2.ZERO else g.ROOM_CENTERS[t[3]]
	canvas.queue_redraw()


func _panel_rect() -> Rect2:
	return Rect2(PANEL_POS - Vector2(6, 6), Vector2(PANEL_W, PANEL_H))


# Karakterin gövdesi (başının üstü dahil) ya da ekrandaki bir konuşma balonu panelle kesişiyor mu?
func _covers_player() -> bool:
	var panel := _panel_rect().grow(8.0)
	var sp: Vector2 = story.to_screen(story.game.player.global_position)
	if panel.intersects(Rect2(sp - Vector2(45, 190), Vector2(90, 200))):
		return true
	for b in story.bubbles.values():
		if is_instance_valid(b) and b.visible and panel.intersects(Rect2(b.position - Vector2(210, 170), Vector2(420, 175))):
			return true
	return false


func _text(font: Font, pos: Vector2, s: String, size: int, col: Color, width := -1.0) -> void:
	canvas.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, 4, Color(0.03, 0.02, 0.02, 0.8 * col.a))
	canvas.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, col)


# Büyük görev yazısı: kalın koyu kontur (her zeminde okunur), gerekirse iki satıra kırılır.
func _big_text(font: Font, pos: Vector2, s: String, col: Color) -> void:
	var width := PANEL_W - 30.0
	canvas.draw_multiline_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, TASK_SIZE, 2, 7, Color(0.03, 0.02, 0.02, 0.85 * col.a))
	canvas.draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, TASK_SIZE, 2, col)


func _draw_panel() -> void:
	if not visible or not _ready_to_list():
		return
	var list := _tasks()
	var cur := _current(list)
	var font := ThemeDB.fallback_font
	var x := PANEL_POS.x
	var y := PANEL_POS.y
	var pa := panel_alpha
	var n := list.size()
	# Zemin yok: kalın konturlu yazılar + solda ince sıcak çizgi. Karakter üstüne gelince solar.
	var head := "TÜM GÖREVLER TAMAM" if cur == -1 else "GÖREV %d / %d" % [cur + 1, n]
	canvas.draw_rect(Rect2(x - 4, y - 2, 4, 76), Color(1, 0.78, 0.35, 0.9 * pa))
	_text(font, Vector2(x + 10, y + 16), head, HEAD_SIZE, Color(1, 0.84, 0.5, pa))
	# İlerleme noktaları: biten yeşil, şimdiki sarı (nabız), kalan soluk.
	var hw := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, HEAD_SIZE).x
	for i in n:
		var c := Color(1, 1, 1, 0.3)
		if list[i][1]:
			c = Color(0.55, 0.92, 0.55, 0.95)
		elif i == cur:
			c = Color(1, 0.86, 0.4, 0.7 + 0.3 * sin(time * 4.0))
		c.a *= pa
		var dot := Rect2(x + 24 + hw + i * 14, y + 5, 9, 9)
		canvas.draw_rect(dot.grow(1.5), Color(0.03, 0.02, 0.02, 0.7 * pa))
		canvas.draw_rect(dot, c)
	var ty := y + 50
	if change_t < OUT_TIME and prev_title != "":
		# Biten görev: yeşil tikle yukarı kayarak söner.
		var k := change_t / OUT_TIME
		_big_text(font, Vector2(x + 10, ty - 14 * k), "✓ " + prev_title, Color(0.55, 1, 0.55, (1.0 - k * k) * pa))
	elif cur != -1:
		var k := clampf((change_t - OUT_TIME) / IN_TIME, 0.0, 1.0) if prev_title != "" else 1.0
		var e := 1.0 - pow(1.0 - k, 3.0)
		_big_text(font, Vector2(x + 10 - 24 * (1.0 - e), ty), list[cur][0], Color(1, 0.97, 0.9, e * pa))
	if cur == -1:
		return
	var g: Node2D = story.game
	# Erzak görevi: önceki her şey bitti ve çanta alındıysa dört eşyanın her biri ayrı parıldar.
	if cur == SUPPLY_TASK:
		if story.world.has_item("quake_bag"):
			var k := 0
			for it in _missing_supplies():
				if it.room == g.current_room and it.visible:
					_mark_item(it, k)
				k += 1
		return
	# Diğer görevler: aynı odadaki hedef parıldar.
	var t: Array = list[cur]
	if t[3] != g.current_room:
		return
	if t[2] != null and is_instance_valid(t[2]) and t[2].visible:
		_mark_item(t[2], 0)
	elif t.size() > 4 and t[4] != Vector2.ZERO:
		_sparkle_at(t[4] + Vector2(0, -24), 24.0, 0)


# Eşyanın görünen gövdesinin ortasında, boyutuna göre parıltı.
func _mark_item(item: Node2D, k: int) -> void:
	var c := item_center(item)
	_sparkle_at(c[0], c[1], k)


# Eşyanın görünen gövdesinin ortası ve boyutuna göre parıltı yarıçapı (dünya birimi): [merkez, yarıçap].
static func item_center(item: Node2D) -> Array:
	var center := item.global_position
	var r := 24.0
	if item is Area2D:
		var sz: Vector2 = item.size
		center += item.draw_offset + Vector2(0, -sz.y * 0.5)
		r = maxf(sz.x, sz.y) * 0.45
	return [center, r]


# Başka katmanlar (ör. eğitim) için: eşya ekrandaysa kendi yerinde parıldar.
static func sparkle_item(ci: CanvasItem, story_node: Node, item: Node2D, k: int, t: float) -> void:
	var c := item_center(item)
	var sp: Vector2 = story_node.to_screen(c[0])
	var zoom: float = story_node.get_viewport().get_canvas_transform().get_scale().x
	sparkle(ci, sp, clampf(c[1] * zoom, SPARKLE_MIN, SPARKLE_MAX), k, t)


# Ufak parıltı: hafif nabız gibi hale + çevresinde sırayla göz kırpan dört köşeli yıldızcıklar.
# Hedef ekran dışındaysa ekran kenarında, hedef yönünde küçük bir parıltı kalır.
func _sparkle_at(world_point: Vector2, world_r: float, k: int) -> void:
	var sp: Vector2 = story.to_screen(world_point)
	var view := canvas.size
	# Üstte envanter/can çubuğu var: parıltı onların altında kalsın.
	var inner := Rect2(Vector2.ZERO, view).grow_individual(-40.0, -100.0, -40.0, -40.0)
	# İlk karede ya da çok küçük görünümde (bölünmüş ekran) tuval henüz boyutsuz olabilir.
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var zoom: float = story.get_viewport().get_canvas_transform().get_scale().x
	var r := clampf(world_r * zoom, SPARKLE_MIN, SPARKLE_MAX)
	# Ekrandaki hedef kendi yerinde parıldar (üstteki çubuklara yakın olsa bile); yalnız ekran dışındaysa kenara alınır.
	if not Rect2(Vector2.ZERO, view).grow(-6.0).has_point(sp):
		var edge := Vector2(clampf(sp.x, inner.position.x, inner.end.x), clampf(sp.y, inner.position.y, inner.end.y))
		sparkle(canvas, edge, SPARKLE_MIN, k, time)
		return
	sparkle(canvas, sp, r, k, time)


static func sparkle(ci: CanvasItem, sp: Vector2, r: float, k: int, t: float) -> void:
	var warm := Color(1.0, 0.72, 0.2)
	var pulse := 0.5 + 0.5 * sin(t * 3.0 + k * 1.3)
	# Belirgin ama yumuşak hale: içe doğru yoğunlaşan amber ışık (açık zeminde de seçilir).
	for i in 5:
		ci.draw_circle(sp, r * (1.05 - i * 0.18), Color(warm, 0.07 + 0.08 * pulse))
	# Dışa yayılan ışık halkası (her 1.6 sn'de bir): göz ucuyla bile fark edilir.
	var ring := fmod(t + k * 0.4, 1.6) / 1.6
	var ring_r := r * (0.5 + 0.85 * ring)
	ci.draw_arc(sp, ring_r, 0.0, TAU, 40, Color(0.45, 0.25, 0.05, 0.35 * (1.0 - ring)), 5.0)
	ci.draw_arc(sp, ring_r, 0.0, TAU, 40, Color(1.0, 0.85, 0.35, 0.8 * (1.0 - ring)), 2.5)
	for i in 6:
		var ang := t * 0.5 + i * TAU / 6.0 + k
		var p := sp + Vector2.from_angle(ang) * r * (0.6 + 0.3 * sin(t * 1.3 + i * 2.0))
		var tw := pow(maxf(0.0, sin(t * 2.6 + i * 1.7 + k * 0.9)), 2.0)
		if tw > 0.05:
			star(ci, p, 5.0 + 7.0 * tw, Color(1.0, 0.93, 0.55, tw))
	# Ortada sürekli parıldayan büyük yıldız.
	star(ci, sp + Vector2(r * 0.2, -r * 0.25), 7.0 + 4.0 * pulse, Color(1.0, 0.93, 0.6, 0.8 + 0.2 * pulse))


static func star(ci: CanvasItem, p: Vector2, s: float, c: Color) -> void:
	# Koyu ince gölge: açık zeminde de seçilsin.
	ci.draw_line(p - Vector2(s, 0) + Vector2(1, 1), p + Vector2(s, 0) + Vector2(1, 1), Color(0.3, 0.16, 0.03, c.a * 0.6), 3.0)
	ci.draw_line(p - Vector2(0, s) + Vector2(1, 1), p + Vector2(0, s) + Vector2(1, 1), Color(0.3, 0.16, 0.03, c.a * 0.6), 3.0)
	ci.draw_line(p - Vector2(s, 0), p + Vector2(s, 0), c, 2.0)
	ci.draw_line(p - Vector2(0, s), p + Vector2(0, s), c, 2.0)
	var d := s * 0.4
	ci.draw_line(p - Vector2(d, d), p + Vector2(d, d), Color(c, c.a * 0.6), 1.0)
	ci.draw_line(p - Vector2(d, -d), p + Vector2(d, -d), Color(c, c.a * 0.6), 1.0)
	ci.draw_circle(p, 1.4, c)
