extends CanvasLayer

const CatSprite = preload("res://scripts/cat_sprite.gd")

# Birinci şahıs: yatağın altına bakış. Üstte yatak tabanı (tahtalar), altta perspektifli zemin;
# fener ışığı ortada; tozlar, kayıp çorap, eski ayakkabı kutusu; en dipte korkmuş kedi.
# Hikâye denetçisi alanları ayarlar: reveal (fener açılır), cat_forward (kedi yaklaşır),
# shake (sarsıntı), dark (kararma), flash (çarpma anı beyaz/kırmızı).

var reveal := 0.0
var cat_forward := 0.0
var shake := 0.0
var dark := 0.0
var flash := 0.0
var appear := 0.0
var time := 0.0
var lines: Array = []
# Üstte küçük yönerge (ör. "[E] Seslen 2/4").
var hint := ""
var canvas: Control
var cat_tex: Array = []
var falling: Array = []
# Yürüyüş: animasyon yalnız kedi gerçekten ilerlerken oynar (yerinde yürüme olmaz); adım saati
# hızla orantılı ilerler, dururken kedi ayakta etrafa bakınır.
var prev_forward := 0.0
var move_speed := 0.0
var walk_clock := 0.0


func _ready() -> void:
	layer = 27
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw.connect(_draw_view)
	add_child(canvas)
	for i in 3:
		cat_tex.append(load("res://assets/rubble/cat_%d.png" % i))


func _process(delta: float) -> void:
	time += delta
	if delta > 0.0:
		var rate := absf(cat_forward - prev_forward) / delta
		move_speed = lerpf(move_speed, rate, 1.0 - exp(-14.0 * delta))
	prev_forward = cat_forward
	if move_speed > 0.03:
		walk_clock += delta * clampf(move_speed / 0.35, 0.8, 2.2)
	appear = minf(1.0, appear + delta * 2.5)
	# Sarsıntıda yatak tabanından toz/kırıntı dökülür.
	if shake > 0.2 and randf() < shake * 0.9:
		falling.append({"pos": Vector2(randf_range(0.0, 1.0), 0.0), "v": randf_range(0.3, 0.7), "age": 0.0})
	for f in falling:
		f.age += delta
		f.pos.y += f.v * delta
	falling = falling.filter(func(f): return f.pos.y < 1.0)
	canvas.queue_redraw()


func _draw_view() -> void:
	var view := canvas.size
	var jolt := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 26.0 * shake * shake
	canvas.draw_rect(Rect2(Vector2.ZERO, view), Color.BLACK)
	var top := view.y * 0.3
	var horizon := view.y * 0.48
	var cx := view.x * 0.5
	var light := 0.12 + 0.88 * reveal
	# Zemin: tahtalar ufka doğru daralır.
	var floor_pts := PackedVector2Array([Vector2(0, view.y), Vector2(view.x, view.y), Vector2(cx + 300, horizon), Vector2(cx - 300, horizon)])
	for i in floor_pts.size():
		floor_pts[i] += jolt
	canvas.draw_colored_polygon(floor_pts, Color(0.33, 0.21, 0.13) * light)
	for k in range(-8, 9):
		var a := Vector2(cx + k * 37.5, horizon) + jolt
		var b := Vector2(cx + k * 180.0, view.y) + jolt
		canvas.draw_line(a, b, Color(0.18, 0.11, 0.07) * light, 2.0)
	for k in 6:
		var t := pow(float(k + 1) / 7.0, 1.6)
		var y := lerpf(horizon, view.y, t)
		var half := lerpf(300.0, view.x * 0.5, t)
		canvas.draw_line(Vector2(cx - half, y) + jolt, Vector2(cx + half, y) + jolt, Color(0.2, 0.12, 0.08) * light, 1.5)
	# Yatak tabanı: üstte kalın çerçeve + tahta çıtalar.
	canvas.draw_rect(Rect2(Vector2(-40, 0) + jolt, Vector2(view.x + 80, top)), Color(0.16, 0.1, 0.06) * maxf(light, 0.3))
	for k in 7:
		var x := view.x * (k + 0.5) / 7.0
		canvas.draw_rect(Rect2(Vector2(x - 60, top - 46) + jolt, Vector2(120, 34)), Color(0.42, 0.28, 0.15) * light)
		canvas.draw_line(Vector2(x - 56, top - 40) + jolt, Vector2(x + 56, top - 40) + jolt, Color(0.55, 0.38, 0.2) * light, 2.0)
	canvas.draw_rect(Rect2(Vector2(-40, top - 12) + jolt, Vector2(view.x + 80, 24)), Color(0.3, 0.19, 0.1) * light)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(0, top + 12), Vector2(view.x, top + 12), Vector2(cx + 300, horizon), Vector2(cx - 300, horizon)]), Color(0.08, 0.05, 0.03) * light)
	# Yatak altındaki eşyalar.
	_dust_bunny(Vector2(cx - 420, view.y * 0.78) + jolt, 34.0, light)
	_dust_bunny(Vector2(cx + 360, view.y * 0.62) + jolt, 22.0, light)
	_dust_bunny(Vector2(cx - 150, view.y * 0.56) + jolt, 14.0, light)
	var sock := PackedVector2Array([Vector2(cx + 160, view.y * 0.84), Vector2(cx + 260, view.y * 0.8), Vector2(cx + 280, view.y * 0.87), Vector2(cx + 230, view.y * 0.9), Vector2(cx + 170, view.y * 0.9)])
	for i in sock.size():
		sock[i] += jolt
	canvas.draw_colored_polygon(sock, Color(0.55, 0.2, 0.22) * light)
	canvas.draw_line(Vector2(cx + 165, view.y * 0.86) + jolt, Vector2(cx + 270, view.y * 0.83) + jolt, Color(0.85, 0.85, 0.8) * light, 4.0)
	var box := Rect2(Vector2(cx - 380, view.y * 0.5) + jolt, Vector2(170, 70))
	canvas.draw_rect(box, Color(0.5, 0.42, 0.3) * light)
	canvas.draw_rect(Rect2(box.position, Vector2(box.size.x, 16)), Color(0.6, 0.5, 0.36) * light)
	canvas.draw_rect(box, Color(0.25, 0.2, 0.14) * light, false, 3.0)
	# Kedi: dipte, gözleri fenerle parlar; çağırınca biraz yaklaşır.
	var depth := lerpf(0.0, 1.0, cat_forward)
	var cat_scale := lerpf(5.5, 9.0, depth)
	# Osman (sprite, kameraya doğru): önce oturup etrafa bakınır, çağrıldıkça yavaşça yürür,
	# son çağrıda koşarak gelir.
	var moving := move_speed > 0.03
	# Yürürken hafif sağa sola salınarak ilerler (adım saatine bağlı).
	var weave := sin(walk_clock * 3.2) * 10.0 * depth if moving else 0.0
	var cat_base := Vector2(cx + sin(time * 0.7) * 6.0 * (1.0 - depth) + weave, lerpf(horizon + 70, view.y * 0.8, depth)) + jolt
	var tremble := Vector2(randf_range(-1, 1), 0) * 3.0 * (0.4 + shake) * (0.4 if moving else 1.0)
	var anim := "sit"
	if moving:
		anim = "run" if move_speed > 0.6 or cat_forward >= 0.85 else "walk"
	elif cat_forward >= 0.05:
		anim = "look"
	var fps: float = {"sit": 1.5, "look": 2.5, "walk": 7.0, "run": 12.0}[anim]
	var t_anim: float = minf(time, 0.99 * 6.0 / 1.5) if anim == "sit" else (walk_clock if moving else time)
	CatSprite.draw(canvas, anim, CatSprite.DOWN, t_anim, fps, cat_base + tremble, cat_scale * 0.9, Color(light, light, light))
	if reveal < 0.6 and cat_forward < 0.3:
		# Karanlıkta parlayan gözler.
		var head := cat_base + tremble - Vector2(0, 32.0 * cat_scale * 0.9 * 0.62)
		for ex in [-3.0, 3.0]:
			var e := head + Vector2(ex * cat_scale * 0.9, 0)
			canvas.draw_circle(e, cat_scale * 1.0, Color(0.75, 1.0, 0.45, 0.3 + 0.3 * (1.0 - reveal)))
			canvas.draw_circle(e, cat_scale * 0.4, Color(1, 1, 0.8, 0.85))
	# Fener ışığı ve kenar karanlığı.
	for i in 22:
		var r := 180.0 + i * 34.0 * (0.6 + reveal * 0.6)
		canvas.draw_arc(Vector2(cx, view.y * 0.66) + jolt, r, 0, TAU, 96, Color(0, 0, 0, 0.09), 36.0)
	for f in falling:
		canvas.draw_rect(Rect2(Vector2(f.pos.x * view.x, lerpf(top, view.y, f.pos.y)) + jolt, Vector2(4, 4)), Color(0.75, 0.7, 0.6, 0.8 * light))
	# Konuşma satırları (alt orta).
	var font := ThemeDB.fallback_font
	var y := view.y - 70.0
	for line in lines:
		canvas.draw_string(font, Vector2(0, y), line[0], HORIZONTAL_ALIGNMENT_CENTER, view.x, 30, line[1])
		y -= 42.0
	if hint != "":
		var pulse := 0.6 + 0.4 * sin(time * 5.0)
		canvas.draw_string(font, Vector2(0, 54), hint, HORIZONTAL_ALIGNMENT_CENTER, view.x, 26, Color(1, 0.88, 0.55, pulse))
	if dark > 0.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, dark))
	if flash > 0.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0.9, 0.15, 0.1, flash))
	if appear < 1.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 1.0 - appear))


func _dust_bunny(p: Vector2, r: float, light: float) -> void:
	canvas.draw_circle(p, r, Color(0.45, 0.43, 0.42, 0.85) * light)
	for k in 7:
		var a := TAU * k / 7.0 + sin(time * 0.5 + k) * 0.1
		canvas.draw_line(p, p + Vector2.from_angle(a) * r * 1.3, Color(0.5, 0.48, 0.46, 0.7) * light, 2.0)


func say(text: String, color := Color.WHITE) -> void:
	lines.push_front([text, color])
	if lines.size() > 2:
		lines.pop_back()
