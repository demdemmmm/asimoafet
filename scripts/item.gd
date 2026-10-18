extends Area2D

const CatSprite = preload("res://scripts/cat_sprite.gd")

@export_enum("bed", "wardrobe", "fire", "nightstand", "tv", "coffee_table", "sofa", "alcohol", "chair", "table", "kitchen_counter", "side_table", "fridge", "mirror_cabinet", "puddle", "electrical_box", "bandage", "shower", "drill", "screwdriver", "nails", "toilet", "flashlight", "fire_extinguisher", "cat", "heater", "tv_unit", "armchair", "floor_lamp", "sink", "shower_curtain", "towels", "phone", "quake_bag", "mirror", "plant", "basket", "decor", "counter", "stove", "kitchen_sink", "food", "water_bottle", "whistle") var kind: String = "bed"
@export var caption := "Yatak"
@export var room: StringName = &"salon"
@export var size := Vector2(100, 80)
@export var solid := true
@export var weathered := false
@export var interaction_enabled := true
@export var pool_extent := Vector2.ZERO
# Birikintinin kaynağı (patlak boru) — su buradan damlayıp birikintiye akar.
@export var source_offset := Vector2.ZERO
@export var emits_light := false
@export var lamp_color := Color(1.0, 0.72, 0.4)
var pool_outline := PackedVector2Array()
var pool_hazard: Area2D
@export var collectible := false
@export var anchorable := false
@export var amount := 1
# Zemin izi derinliği (taban noktasından yukarı). Uzun eşyalarda (yatak, duş) artırılır.
@export var foot_depth := 32.0
# Masa/sehpa üstündeki eşyalar için görsel kaydırma; taban noktası sıralama için kalır.
@export var draw_offset := Vector2.ZERO
@export var lying := false
# PNG görselli eşyalar: boyut görselden (sprite_scale katı) hesaplanır, görsel taban noktasına oturur.
@export var texture_path := ""
@export var open_texture_path := ""
@export var lamp_radius_scale := 1.0
@export var lamp_energy := 1.0
var opened := false
var cabinet_mix := 0.0
var open_tex: Texture2D
var open_draw_size := Vector2.ZERO
var open_draw_offset := Vector2.ZERO
var cabinet_tween: Tween
@export var repaired_texture_path := ""
var repaired := false
var repaired_tex: Texture2D
@export var sprite_scale := 2.0
@export var sprite_rotation := 0.0
@export_file("*.png") var broken_texture_path := ""
var sprite_draw_size := Vector2.ZERO

var world: Node2D
var anchored := false
var fallen := false
var collected := false
var burning := false
var alarm_on := false
var nearby := false
var hazard_clock := 0.0
var alert_tex: Texture2D
var sprite_tex: Texture2D
var lamp_lights: Array[PointLight2D] = []
var light_on := true
# Telefon çalarken ahize titrer.
var ringing := false
# Deprem sonrası yatak odasında devrilen soba.
var toppled := false
# Yatak odasında kediyi alırken yıkılan dolaplar; vidalanınca (screws_shown=4) dayanır.
var trap := false
# Kedi yatağın altında saklanır: yalnız karanlıkta parlayan gözleri görünür.
var under_bed := false
# Banyo prizi: 0 duvarda (sağlam), 1 kopmuş ve kablolarıyla suya sarkmış.
var outlet_tear := 0.0
# Osman çağrıldıkça yatağın altından çıkar (0: içeride, 1: dışarıda, alınabilir); hop: küçük sıçrayış.
var approach := 0.0
var hop := 0.0
# Omuza atlayış: 0→1 boyunca yay çizerek jump_to (yerel) noktasına sıçrar.
var jump := 0.0
var jump_to := Vector2.ZERO
# Ev süsleri: decor türünün çizim biçimi (photo, painting, clock, shelf, bookshelf, vase, plant_big,
# calendar, round_table, fruit_bowl).
@export var style := ""
# Dolabın içinde (boş) deprem çantası var mı; açınca hikâyeye bildirilir.
var holds_bag := false
# Karanlıkta fener aranan yerler (çekmece, lavabo altı...); boşsa "" .
var search_spot := ""
# Su birikintisi: 0 = kuru (deprem öncesi), 1 = tamamen yayılmış.
var flood := 1.0
# Kırılan dolaptan etrafa saçılan tahta parçaları (devrildikten sonra yerde kalır).
var planks: Array = []
var screws_shown := 0
# Dolap devrilmesi: sallanma (wobble), düşüş (fall_k 0→1), kırık görsel ve altında kalma.
const BROKEN_TEX := "res://assets/bedroom/wardrobe_broken.png"
const CRUSH_TEX := "res://assets/bedroom/wardrobe_crushed_overlay.png"
const FALL_REACH := 64.0
var wobbling := false
var fall_k := 0.0
var crushed := false
var broken_tex: Texture2D
var crush_tex: Texture2D
# Sarsıntıda lamba titrer: flicker_left > 0 iken ışık rastgele yanıp söner.
var flicker_left := 0.0
var flicker_step := 0.0
var flicker_lit := true

@onready var alarm: AudioStreamPlayer2D = $alarm

func _ready() -> void:
	# Oturulamayan oturma eşyalarında [E] göstergesi çıkmasın.
	if kind in ["chair", "armchair", "sofa"]:
		interaction_enabled = false
	if interaction_enabled:
		add_to_group("interactables")
	else:
		monitoring = false
	add_to_group("world_items")
	collision_layer = 0
	collision_mask = 2
	z_index = 0
	# Kök, eşyanın taban noktasıdır. Çocuk görseller birlikte sıralanır.
	y_sort_enabled = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if texture_path != "":
		sprite_tex = _load_tex(texture_path)
		if sprite_tex != null:
			sprite_draw_size = Vector2(sprite_tex.get_size()) * sprite_scale
			size = Vector2(
				absf(cos(sprite_rotation)) * sprite_draw_size.x + absf(sin(sprite_rotation)) * sprite_draw_size.y,
				absf(sin(sprite_rotation)) * sprite_draw_size.x + absf(cos(sprite_rotation)) * sprite_draw_size.y)
	if open_texture_path != "":
		_load_open_texture()
	if repaired_texture_path != "":
		repaired_tex = _load_tex(repaired_texture_path)
	var reach := RectangleShape2D.new()
	reach.size = Vector2(maxf(size.x + 70, 100), 130)
	$interaction_shape.shape = reach
	$interaction_shape.position = Vector2(0, -12)
	$body.collision_layer = 1 if solid else 0
	$body.collision_mask = 0
	if solid:
		if kind == "kitchen_counter":
			_add_foot(Rect2(-size.x / 2, -size.y, size.x, 36))
			_add_foot(Rect2(-size.x / 2, -size.y + 36, 36, size.y - 36))
		elif kind in ["sofa", "armchair"] and sprite_tex != null:
			# Koltuk çarpışması görünen gövdesiyle birebir: PNG'nin dolu (şeffaf olmayan) alanı, ne az ne fazla.
			var used := sprite_tex.get_image().get_used_rect()
			var left := -sprite_draw_size.x * 0.5 + used.position.x * sprite_scale
			var top := -sprite_draw_size.y + used.position.y * sprite_scale
			_add_foot(Rect2(Vector2(left, top) + draw_offset, Vector2(used.size) * sprite_scale))
		else:
			_add_foot(Rect2(-size.x / 2, -foot_depth, size.x, foot_depth))
	body_entered.connect(_body_entered)
	body_exited.connect(_body_exited)
	if kind == "tv":
		_create_alarm()
		_load_alert()
	if kind == "floor_lamp" or emits_light:
		_create_lamp_light()
	if kind == "puddle" and pool_extent != Vector2.ZERO:
		_build_pool_hazard()


# Güvenlik: yalnız oyun paketindeki (res://) içe aktarılmış kaynaklar yüklenir; diskten ham dosya okunmaz.
func _load_tex(path: String) -> Texture2D:
	if not path.begins_with("res://assets/") or not path.ends_with(".png") \
			or path.contains("..") or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _load_open_texture() -> void:
	open_tex = _load_tex(open_texture_path)
	if open_tex == null or sprite_tex == null:
		return
	open_draw_size = Vector2(open_tex.get_size()) * sprite_scale
	var closed_used := sprite_tex.get_image().get_used_rect()
	var open_used := open_tex.get_image().get_used_rect()
	open_draw_offset.x = (-sprite_draw_size.x * 0.5 + closed_used.position.x * sprite_scale) - (-open_draw_size.x * 0.5 + open_used.position.x * sprite_scale)
	open_draw_offset.y = (-sprite_draw_size.y + closed_used.end.y * sprite_scale) - (-open_draw_size.y + open_used.end.y * sprite_scale)

func toggle_open() -> bool:
	if fallen or open_tex == null:
		return false
	opened = not opened
	if cabinet_tween != null and cabinet_tween.is_valid():
		cabinet_tween.kill()
	cabinet_tween = create_tween()
	cabinet_tween.tween_method(_set_cabinet_mix, cabinet_mix, 1.0 if opened else 0.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return true

func _set_cabinet_mix(value: float) -> void:
	cabinet_mix = value
	queue_redraw()


func set_repaired(value: bool) -> void:
	repaired = value
	if repaired and repaired_tex != null:
		sprite_tex = repaired_tex
	elif texture_path != "":
		sprite_tex = _load_tex(texture_path)
	if sprite_tex != null:
		sprite_draw_size = Vector2(sprite_tex.get_size()) * sprite_scale
	queue_redraw()


func _create_lamp_light() -> void:
	# Sıcak, yumuşak gece lambası ışığı: geniş ortam ışığı + abajurda parlak çekirdek.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.35, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	for spec in [[3.2, 1.35], [0.9, 1.6]]:
		var light := PointLight2D.new()
		light.texture = tex
		light.texture_scale = spec[0] * lamp_radius_scale
		light.energy = spec[1] * lamp_energy
		light.color = lamp_color
		light.position = draw_offset + Vector2(0, -size.y + 14)
		add_child(light)
		lamp_lights.append(light)


# Elektrik sistemine bağlanmak için: kesintide kapatılır.
func set_light(enabled: bool) -> void:
	light_on = enabled
	flicker_left = 0.0
	flicker_lit = true
	for light in lamp_lights:
		light.enabled = enabled
	queue_redraw()


func flicker(seconds: float) -> void:
	if lamp_lights.is_empty() or not light_on:
		return
	flicker_left = maxf(flicker_left, seconds)
	flicker_step = 0.0


func _update_flicker(delta: float) -> void:
	flicker_left = maxf(flicker_left - delta, 0.0)
	flicker_step -= delta
	if flicker_left == 0.0:
		flicker_lit = true
	elif flicker_step <= 0.0:
		# Kısa sönmeler ve titrek yanmalar: sönük kalma olasılığı ~%45.
		flicker_lit = randf() > 0.45
		flicker_step = randf_range(0.03, 0.14) if flicker_lit else randf_range(0.04, 0.22)
	for light in lamp_lights:
		light.enabled = flicker_lit
	queue_redraw()



func _add_foot(rect: Rect2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = rect.get_center()
	$body.add_child(collider)

func _body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		nearby = true
		queue_redraw()

func _body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		nearby = false
		queue_redraw()

func can_interact(body: Node2D) -> bool:
	# Osman'a yalnız yatağın sağ tarafından ulaşılır (sol tarafı duvara yakın, oradan erişilmez).
	if kind == "cat" and body.global_position.x < global_position.x + 45.0:
		return false
	return interaction_enabled and world != null and not collected and room == world.game.current_room \
		and visible and body.active and overlaps_body(body)

func interact(body: Node2D) -> void:
	if can_interact(body):
		world.interact_with(self, body)

func set_room_active(enabled: bool) -> void:
	visible = enabled and not collected
	if kind == "tv":
		alarm.stop()

# TV uyarısı yalnız görseldir: iki tonlu alarm telefon zili gibi duyulduğu için ses çalınmaz.
func set_alarm(enabled: bool) -> void:
	alarm_on = enabled
	alarm.stop()
	queue_redraw()

func collect() -> void:
	collected = true
	remove_from_group("interactables")
	hide()
	set_deferred("monitoring", false)
	queue_free()

func on_earthquake() -> void:
	if anchorable and not anchored:
		fallen = true
		_set_fallen_foot.call_deferred()
		if room == world.game.current_room and global_position.distance_to(world.game.player.global_position) < size.x * 0.6 + 24:
			world.game.player.take_damage(30)
	if kind == "fire":
		burning = not world.game.gas_off
	if kind == "puddle" and not world.leak_repaired:
		# Gevşek priz sarsıntıyla duvardan kopar; kabloları sarkıp yayılan suya değer.
		create_tween().tween_property(self, "outlet_tear", 1.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()

# Dolabı öne doğru devirir; crush ise altında kalan oyuncunun görseli eklenir.
func topple(crush: bool) -> void:
	if fallen or fall_k > 0.0:
		return
	wobbling = false
	crushed = crush
	broken_tex = _load_tex(broken_texture_path if not broken_texture_path.is_empty() else BROKEN_TEX)
	crush_tex = _load_tex(CRUSH_TEX) if crush else null
	var tween := create_tween()
	tween.tween_method(_set_fall, 0.0, 1.0, 0.28).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await tween.finished
	fallen = true
	_set_fallen_foot.call_deferred()
	_break_fx()
	queue_redraw()


# Kırılma: tahta kıymıkları ve toz patlaması; birkaç tahta parçası dolabın çevresine saçılır.
func _break_fx() -> void:
	var splinters := CPUParticles2D.new()
	splinters.one_shot = true
	splinters.explosiveness = 0.9
	splinters.amount = 46
	splinters.lifetime = 1.3
	splinters.local_coords = false
	splinters.direction = Vector2(0, -1)
	splinters.spread = 75.0
	splinters.initial_velocity_min = 120.0
	splinters.initial_velocity_max = 300.0
	splinters.gravity = Vector2(0, 620)
	splinters.angular_velocity_min = -540.0
	splinters.angular_velocity_max = 540.0
	splinters.scale_amount_min = 2.0
	splinters.scale_amount_max = 5.0
	var tones := Gradient.new()
	tones.colors = PackedColorArray([Color("6b4226"), Color("8a5a34"), Color("a36d42"), Color("4a2e1a")])
	tones.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	splinters.color_initial_ramp = tones
	splinters.position = Vector2(0, FALL_REACH * 0.5)
	splinters.z_index = 3
	add_child(splinters)
	splinters.emitting = true
	var dust := CPUParticles2D.new()
	dust.one_shot = true
	dust.explosiveness = 0.85
	dust.amount = 26
	dust.lifetime = 1.8
	dust.local_coords = false
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(50, 10)
	dust.spread = 180.0
	dust.initial_velocity_min = 20.0
	dust.initial_velocity_max = 70.0
	dust.gravity = Vector2(0, -20)
	dust.scale_amount_min = 8.0
	dust.scale_amount_max = 16.0
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(0.8, 0.74, 0.66, 0.45), Color(0.8, 0.74, 0.66, 0.0)])
	dust.color_ramp = fade
	dust.position = Vector2(0, FALL_REACH * 0.5)
	dust.z_index = 3
	add_child(dust)
	dust.emitting = true
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x * 7 + global_position.y)
	for k in 7:
		var ang := rng.randf_range(-PI * 0.9, PI * 0.9) + PI * 0.5
		var dist := rng.randf_range(50, 95)
		planks.append([Vector2.from_angle(ang) * dist + Vector2(0, FALL_REACH * 0.4), Vector2(rng.randf_range(10, 22), rng.randf_range(3, 5)), rng.randf_range(0, PI), rng.randf_range(0.8, 1.1)])


func _set_fall(k: float) -> void:
	fall_k = k
	queue_redraw()


# Dolabın yıkılınca kapladığı zemin (dünya koordinatı): tabanın önüne doğru.
func fall_area() -> Rect2:
	return Rect2(global_position + Vector2(-52, -size.y * 0.2), Vector2(104, size.y * 0.2 + FALL_REACH + 60))


func _broken_rect() -> Rect2:
	var bsize := Vector2(broken_tex.get_size()) * sprite_scale
	var top := FALL_REACH - (bsize.y if not broken_texture_path.is_empty() else 73.0 * sprite_scale)
	return Rect2(Vector2(-bsize.x * 0.5, top), bsize)


func _set_fallen_foot() -> void:
	for collider in $body.get_children():
		$body.remove_child(collider)
		collider.queue_free()
	if broken_tex != null and not broken_texture_path.is_empty():
		var used := broken_tex.get_image().get_used_rect()
		var bounds := Rect2(_broken_rect().position + Vector2(used.position) * sprite_scale, Vector2(used.size) * sprite_scale)
		_add_foot(Rect2(bounds.position + Vector2(0, bounds.size.y * 0.5), Vector2(bounds.size.x, bounds.size.y * 0.5)))
	elif broken_tex != null:
		_add_foot(Rect2(-46, 8, 92, 42))
	else:
		_add_foot(Rect2(-size.x / 2, -size.y * 0.35, size.x, size.y * 0.35))

func _load_alert() -> void:
	var path := "res://assets/tv_alert.png"
	alert_tex = _load_tex(path)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(_delta: float) -> void:
	if (kind == "puddle" or kind == "electrical_box") and visible:
		queue_redraw()
	if not lamp_lights.is_empty() and light_on:
		var t := Time.get_ticks_msec() / 1000.0
		lamp_lights[0].energy = (1.35 + sin(t * 2.3) * 0.04 + sin(t * 7.1) * 0.02) * lamp_energy
		if flicker_left > 0.0 or not flicker_lit:
			_update_flicker(_delta)
			if flicker_lit and flicker_left > 0.0:
				lamp_lights[0].energy *= randf_range(0.55, 1.15)
	if (kind == "tv" and alarm_on or kind == "phone" and ringing or wobbling or under_bed or kind == "flashlight" or kind == "heater") and visible:
		queue_redraw()

func _build_pool_hazard() -> void:
	# Görsel sınır ve Area2D aynı köşe noktalarını kullanır.
	var half := pool_extent * 0.5
	pool_outline.clear()
	for i in range(40):
		var angle := TAU * float(i) / 40.0
		var x := cos(angle)
		var y := sin(angle)
		var wave := 1.0 + 0.035 * sin(angle * 7.0)
		pool_outline.append(Vector2(signf(x) * sqrt(absf(x)) * half.x,
			signf(y) * sqrt(absf(y)) * half.y) * wave)
	pool_hazard = Area2D.new()
	pool_hazard.name = "water_hazard"
	pool_hazard.collision_layer = 0
	pool_hazard.collision_mask = 2
	var collision := CollisionPolygon2D.new()
	collision.name = "water_outline"
	collision.polygon = pool_outline
	pool_hazard.add_child(collision)
	add_child(pool_hazard)

func water_is_live() -> bool:
	return flood > 0.01 and world != null and world.electrical_fault and not world.game.electricity_off


func _draw_pool() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	_draw_cord(t)
	if flood <= 0.01:
		return
	draw_set_transform(Vector2(0, -pool_extent.y * 0.5 * (1.0 - flood)), 0.0, Vector2(0.3 + 0.7 * flood, flood))
	var live := water_is_live()
	if source_offset != Vector2.ZERO:
		# Lavabonun altındaki patlak borudan akan su ve damlalar.
		var top := Vector2(source_offset.x * 0.35, -pool_extent.y * 0.42)
		draw_line(source_offset, top, Color(0.45, 0.75, 0.9, 0.55), 5.0)
		draw_line(source_offset, top, Color(0.85, 0.95, 1.0, 0.5), 1.5)
		for i in 3:
			var k := fmod(t * 2.6 + i * 0.33, 1.0)
			draw_circle(source_offset.lerp(top, k), 2.2, Color(0.8, 0.93, 1.0, 0.8))
		draw_rect(Rect2(source_offset + Vector2(-6, -4), Vector2(12, 6)), Color("8a9296"))
		draw_line(source_offset + Vector2(-8, 1), source_offset + Vector2(8, -2), Color("4a5256"), 2.0)
	draw_colored_polygon(pool_outline, Color(0.30, 0.60, 0.72, 0.48))
	var edge := pool_outline.duplicate()
	edge.append(pool_outline[0])
	draw_polyline(edge, Color(0.34, 0.67, 0.80, 0.55), 2)
	for i in range(3):
		var center := Vector2(0, (i - 1) * pool_extent.y * 0.27)
		draw_set_transform(center, 0, Vector2(1, 0.55))
		var ripple := fmod(t * 0.55 + float(i) * 0.3, 1.0)
		draw_arc(Vector2.ZERO, 5 + ripple * 22, 0, TAU, 20, Color(0.85, 0.95, 1, 0.35 * (1.0-ripple)), 1.5)
		draw_set_transform(Vector2.ZERO)
	draw_set_transform(Vector2(0, -pool_extent.y * 0.5 * (1.0 - flood)), 0.0, Vector2(0.3 + 0.7 * flood, flood))
	if live:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(t * 12)
		for i in range(4):
			var point := Vector2(rng.randf_range(-20, 12), rng.randf_range(-65, 65))
			var bolt := PackedVector2Array([point])
			for j in range(3):
				point += Vector2(rng.randf_range(-5, 8), rng.randf_range(-8, 8))
				bolt.append(point)
			draw_polyline(bolt, Color(1.0, 0.95, 0.45, 0.95), 2.0)
	draw_set_transform(Vector2.ZERO)


# Lavabonun yanındaki prizden sarkan uzatma kablosu; çoklu priz suyun içinde. Elektrik varken kıvılcım.
func _draw_cord(t: float) -> void:
	if source_offset == Vector2.ZERO:
		return
	# Priz lavabonun solunda duvarda. Depremden önce yerinde; gevşek bağlantısı yüzünden sarsıntıda
	# duvardan kopar, kapak kablolarına asılı sallanır ve soyuk uçlar yayılan suya değer.
	var outlet := source_offset + Vector2(-44, -60)
	var k := clampf(outlet_tear, 0.0, 1.2)
	if k <= 0.0:
		draw_rect(Rect2(outlet - Vector2(7, 9), Vector2(14, 18)), Color("e9e6dc"))
		draw_rect(Rect2(outlet - Vector2(7, 9), Vector2(14, 18)), Color("9a968c"), false, 1.5)
		draw_rect(Rect2(outlet + Vector2(-3, -5), Vector2(2, 4)), Color("3a3a3a"))
		draw_rect(Rect2(outlet + Vector2(1, -5), Vector2(2, 4)), Color("3a3a3a"))
		return
	# Duvarda açılan delik ve kırık sıva.
	draw_rect(Rect2(outlet - Vector2(6, 8), Vector2(12, 16)), Color("2a2522"))
	draw_rect(Rect2(outlet - Vector2(8, 10), Vector2(16, 20)), Color("c9c2b2"), false, 1.5)
	var tip := Vector2(-6, -pool_extent.y * 0.18)
	var sway := sin(t * 2.2) * 2.0
	var colors := [Color("8a4b22"), Color("2f5fb3"), Color("b9c43a")]
	var ends: Array = []
	for w in 3:
		var end: Vector2 = outlet.lerp(tip + Vector2(-6 + w * 6, 0), k) + Vector2(sway * (0.5 + w * 0.2), 0)
		ends.append(end)
		var pts := PackedVector2Array()
		for i in 12:
			var u := i / 11.0
			# Kablolar duvardan çıkıp aşağı sarkar (hafif kavis), uçta suya değer.
			pts.append(outlet.lerp(end, u) + Vector2(sin(u * PI) * (-10.0 - w * 3.0) * k, 0))
		draw_polyline(pts, colors[w], 2.0)
		draw_circle(end, 1.6, Color("d98c3a"))
	# Kapak kablolara asılı, eğik sallanır.
	var plate_pos: Vector2 = outlet.lerp(ends[1], 0.45) + Vector2(-8 * k + sway, 0)
	draw_set_transform(plate_pos, 0.9 * k + sin(t * 2.2) * 0.12)
	draw_rect(Rect2(Vector2(-7, -9), Vector2(14, 18)), Color("e9e6dc"))
	draw_rect(Rect2(Vector2(-7, -9), Vector2(14, 18)), Color("9a968c"), false, 1.5)
	draw_rect(Rect2(Vector2(-3, -5), Vector2(2, 4)), Color("3a3a3a"))
	draw_rect(Rect2(Vector2(1, -5), Vector2(2, 4)), Color("3a3a3a"))
	draw_set_transform(Vector2.ZERO)
	var live := water_is_live()
	# Kopma anında kısa kıvılcım; su elektrikliyken uçlarda sürekli çakan arklar.
	if live or (k > 0.0 and k < 0.98):
		var rng := RandomNumberGenerator.new()
		rng.seed = int(t * 16.0)
		for e in ends:
			var p: Vector2 = e
			var bolt := PackedVector2Array([p])
			for j in 3:
				p += Vector2(rng.randf_range(-8, 8), rng.randf_range(-7, 7))
				bolt.append(p)
			draw_polyline(bolt, Color(1, 0.95, 0.5, 0.95), 1.5)

func _physics_process(delta: float) -> void:
	# Tehlike alanı yayılan suyla birlikte büyür; kuru zeminde çarpılma olmaz.
	if kind == "puddle" and pool_hazard != null:
		pool_hazard.position = Vector2(0, -pool_extent.y * 0.5 * (1.0 - flood))
		pool_hazard.scale = Vector2(0.3 + 0.7 * flood, maxf(flood, 0.001))
	if world == null or world.game.finished or room != world.game.current_room:
		return
	# Elektrikli su her zaman öldürür (Osman'dan sonraki 30 sn dahil).
	if kind == "puddle" and pool_hazard != null:
		if water_is_live():
			for body in pool_hazard.get_overlapping_bodies():
				if body.is_in_group("player") and body.active:
					world.message("Elektrikli suya bastın!")
					body.die()
		return
	if world.game.story.rescue_phase:
		return
	hazard_clock = maxf(0.0, hazard_clock - delta)
	var dangerous: bool = (kind == "fire" and burning) or \
		(kind == "puddle" and world.electrical_fault and not world.game.electricity_off)
	if dangerous and hazard_clock <= 0.0:
		var player = world.game.player
		var footprint := Rect2(Vector2(-size.x / 2, -32), Vector2(size.x, 44)).grow(10)
		if footprint.has_point(to_local(player.global_position)):
			hazard_clock = 1.0
			if kind == "puddle":
				world.message("Elektrikli suya bastın!")
				player.die()
			else:
				player.take_damage(20)
				world.message("Yangın!")

func _create_alarm() -> void:
	var sample_rate := 22050
	var samples := PackedByteArray()
	samples.resize(sample_rate * 2)
	for i in range(sample_rate):
		var tone := 800.0 if i < sample_rate / 2 else 1100.0
		var value := sin(TAU * tone * float(i) / sample_rate) * 4500.0
		samples.encode_s16(i * 2, int(value))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = samples
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = sample_rate
	alarm.stream = stream
	alarm.max_distance = 1200

func _draw() -> void:
	var w := size.x
	var h := size.y
	var rect := Rect2(-w / 2, -h, w, h)
	rect.position += draw_offset
	var wood := Color("967452")
	if fallen and broken_tex != null:
		# Kırık dolap öne yıkılmış yatar (görselin alt kenarı tabandan FALL_REACH ileride).
		var brect := _broken_rect()
		draw_texture_rect(broken_tex, brect, false)
		if crush_tex != null:
			draw_texture_rect(crush_tex, brect, false)
		for pl in planks:
			draw_set_transform(pl[0], pl[2])
			draw_rect(Rect2(-pl[1] * 0.5, pl[1]), Color("7a4c2c") * pl[3])
			draw_line(Vector2(-pl[1].x * 0.5, 0), Vector2(pl[1].x * 0.5, 0), Color("4a2e1a"), 1.0)
			draw_set_transform(Vector2.ZERO)
		return
	if fall_k > 0.0 and style == "bookshelf" and sprite_tex == null:
		var top := lerpf(-h, FALL_REACH * 0.3, fall_k)
		var bottom := lerpf(0.0, FALL_REACH + 20.0, fall_k)
		_draw_decor(Rect2(rect.position.x, top, w, maxf(bottom - top, 4.0)))
		return
	if fall_k > 0.0 and sprite_tex != null:
		# Düşüş: gövde öne doğru yatar (üst kenar tabana, alt kenar ileri kayar).
		var top := lerpf(-h, FALL_REACH * 0.3, fall_k)
		var bottom := lerpf(0.0, FALL_REACH + 20.0, fall_k)
		draw_texture_rect(sprite_tex, Rect2(rect.position.x, top, w, maxf(bottom - top, 4.0)), false)
		return
	if wobbling and sprite_tex != null:
		var t := Time.get_ticks_msec() / 1000.0
		draw_set_transform(Vector2.ZERO, sin(t * 24.0) * 0.05, Vector2.ONE)
		draw_texture_rect(sprite_tex, rect, false)
		draw_set_transform(Vector2.ZERO)
		return
	if fallen:
		var flat := Rect2(-w/2, -h*0.35, w, h*0.35)
		draw_rect(flat, wood)
		draw_rect(flat, Color("d45848"), false, 3)
		if nearby:
			draw_string(ThemeDB.fallback_font, Vector2(-w/2, 22), "Devrildi: " + caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		return
	match ("_sprite" if sprite_tex != null else kind):
		"_sprite":
			if open_tex != null:
				draw_texture_rect(sprite_tex, rect, false, Color(1, 1, 1, 1.0 - cabinet_mix))
				var open_rect := Rect2(Vector2(-open_draw_size.x * 0.5, -open_draw_size.y) + draw_offset + open_draw_offset, open_draw_size)
				draw_texture_rect(open_tex, open_rect, false, Color(1, 1, 1, cabinet_mix))
			else:
				draw_set_transform(rect.get_center(), sprite_rotation)
				draw_texture_rect(sprite_tex, Rect2(-sprite_draw_size * 0.5, sprite_draw_size), false, Color(0.86, 0.76, 0.61) if weathered else Color.WHITE)
				draw_set_transform(Vector2.ZERO)
			if kind == "floor_lamp" and light_on and flicker_lit:
				draw_circle(rect.position + Vector2(w / 2, 10), 14, Color(1, 0.85, 0.5, 0.35))
		"fire":
			draw_circle(Vector2(0, -8), 24, Color("524239"))
			if burning:
				draw_colored_polygon(PackedVector2Array([
					Vector2(-28, -4), Vector2(-18, -50), Vector2(-4, -32),
					Vector2(8, -74), Vector2(30, -4)]), Color("f27c38"))
				draw_circle(Vector2(4, -20), 13, Color("ffd66d"))
		"puddle":
			if not pool_outline.is_empty():
				_draw_pool()
				return
			# Düzensiz kenarlı, yarı saydam su birikintisi; parıltı ve halka dalgalarla.
			var t := Time.get_ticks_msec() / 1000.0
			var live: bool = world != null and world.electrical_fault and not world.game.electricity_off
			var blobs := [[Vector2(0, -12), w * 0.5, 0.36], [Vector2(-w * 0.3, -6), w * 0.24, 0.5],
				[Vector2(w * 0.32, -16), w * 0.2, 0.55], [Vector2(w * 0.12, -2), w * 0.26, 0.4],
				[Vector2(-w * 0.12, -20), w * 0.2, 0.45]]
			for layer in [[0.0, Color(0.12, 0.25, 0.32, 0.45)], [3.0, Color(0.36, 0.6, 0.74, 0.55)]]:
				for b in blobs:
					draw_set_transform(b[0], 0, Vector2(1, b[2]))
					draw_circle(Vector2.ZERO, maxf(2.0, b[1] - layer[0]), layer[1])
			draw_set_transform(Vector2.ZERO)
			draw_set_transform(Vector2(-w * 0.12, -16), 0, Vector2(1, 0.3))
			draw_arc(Vector2.ZERO, w * 0.16, PI * 1.1, PI * 1.6, 8, Color(1, 1, 1, 0.55), 2)
			draw_set_transform(Vector2(w * 0.2, -8), 0, Vector2(1, 0.3))
			draw_arc(Vector2.ZERO, w * 0.1, PI * 1.15, PI * 1.55, 6, Color(1, 1, 1, 0.4), 2)
			var ripple := fmod(t * 0.6, 1.0)
			draw_set_transform(Vector2(w * 0.05, -10), 0, Vector2(1, 0.36))
			draw_arc(Vector2.ZERO, 6 + ripple * w * 0.3, 0, TAU, 24, Color(0.85, 0.95, 1, 0.35 * (1.0 - ripple)), 1.5)
			draw_set_transform(Vector2.ZERO)
			if live:
				# Elektrik: titreyen kıvılcımlar ve mavi-sarı parlama.
				var seed_val := int(t * 12.0)
				var rng := RandomNumberGenerator.new()
				rng.seed = seed_val
				draw_set_transform(Vector2(0, -12), 0, Vector2(1, 0.36))
				draw_circle(Vector2.ZERO, w * 0.48, Color(0.6, 0.85, 1.0, 0.12 + 0.08 * sin(t * 20.0)))
				draw_set_transform(Vector2.ZERO)
				for i in 3:
					var p := Vector2(rng.randf_range(-w * 0.4, w * 0.4), rng.randf_range(-22, -2))
					var pts := PackedVector2Array([p])
					for j in 3:
						p += Vector2(rng.randf_range(-7, 7), rng.randf_range(-6, 6))
						pts.append(p)
					draw_polyline(pts, Color(1, 0.95, 0.45, 0.9), 2)
		"kitchen_counter":
			draw_colored_polygon(PackedVector2Array([
				Vector2(-w/2, -h), Vector2(w/2, -h), Vector2(w/2, -h+36),
				Vector2(-w/2+36, -h+36), Vector2(-w/2+36, 0), Vector2(-w/2, 0)]), Color("c4b59c"))
		"bed":
			draw_rect(rect, wood)
			draw_rect(Rect2(-w/2+6, -h+6, w-12, h-12), Color("638cab"))
			draw_rect(Rect2(-w/2+12, -h+12, w-24, 30), Color("e8e0cf"))
		"tv":
			draw_rect(rect, Color("263448"))
			var color := Color("e6ae54") if alarm_on else Color("527d89")
			if world != null and world.game.power_dead():
				color = Color("17202b")
			var screen := rect.grow(-7)
			draw_rect(screen, color)
			if alarm_on and alert_tex != null and not (world != null and world.game.power_dead()):
				# GIF içeriği (y 5-22) ekranı oranı koruyarak kaplar; taşan yanlar kırpılır.
				var f := (Time.get_ticks_msec() / 170) % 4
				var src := Rect2(0, 5, 32, 17)
				var crop_w := minf(src.size.x, src.size.y * screen.size.x / screen.size.y)
				var crop_h := minf(src.size.y, src.size.x * screen.size.y / screen.size.x)
				var region := Rect2(f * 32 + src.position.x + (src.size.x - crop_w) / 2.0,
					src.position.y + (src.size.y - crop_h) / 2.0, crop_w, crop_h)
				draw_texture_rect_region(alert_tex, screen, region)
		"phone":
			# Masa üstü çevirmeli telefon; çalarken ahize sallanır.
			var t := Time.get_ticks_msec() / 1000.0
			var jiggle := Vector2(sin(t * 60.0) * 1.5, -absf(sin(t * 30.0)) * 2.0) if ringing and fmod(t, 1.6) < 1.0 else Vector2.ZERO
			draw_set_transform(draw_offset)
			draw_colored_polygon(PackedVector2Array([Vector2(-13, 0), Vector2(13, 0), Vector2(9, -11), Vector2(-9, -11)]), Color("8e2a2a"))
			draw_circle(Vector2(0, -5), 4, Color("e8dcc4"))
			draw_circle(Vector2(0, -5), 1.5, Color("3a1414"))
			draw_set_transform(draw_offset + jiggle)
			draw_rect(Rect2(-14, -16, 28, 5), Color("6e1d1d"))
			draw_rect(Rect2(-15, -18, 6, 7), Color("7a2222"))
			draw_rect(Rect2(9, -18, 6, 7), Color("7a2222"))
			draw_set_transform(Vector2.ZERO)
		"decor":
			_draw_decor(rect)
		"counter", "kitchen_sink", "stove":
			_draw_kitchen(rect)
		"food":
			draw_set_transform(draw_offset)
			draw_rect(Rect2(-7, -16, 14, 16), Color("a9aeb2"))
			draw_rect(Rect2(-7, -12, 14, 8), Color("c8402f"))
			draw_rect(Rect2(-4, -10, 8, 4), Color("f3d47a"))
			draw_rect(Rect2(-7, -17, 14, 3), Color("d2d6d9"))
			draw_set_transform(Vector2.ZERO)
		"water_bottle":
			draw_set_transform(draw_offset)
			draw_rect(Rect2(-6, -24, 12, 20), Color(0.65, 0.85, 1.0, 0.8))
			draw_rect(Rect2(-6, -16, 12, 12), Color(0.35, 0.62, 0.95, 0.9))
			draw_rect(Rect2(-6, -20, 12, 4), Color("2a6fc9"))
			draw_rect(Rect2(-3, -29, 6, 5), Color("2a6fc9"))
			draw_line(Vector2(-3, -14), Vector2(-3, -6), Color(1, 1, 1, 0.6), 1.5)
			draw_set_transform(Vector2.ZERO)
		"whistle":
			draw_set_transform(draw_offset)
			draw_rect(Rect2(-9, -9, 13, 7), Color("e8a81a"))
			draw_circle(Vector2(5, -6), 5, Color("e8a81a"))
			draw_circle(Vector2(5, -6), 2, Color("3a2a0a"))
			draw_rect(Rect2(-12, -8, 4, 4), Color("f2c84a"))
			draw_arc(Vector2(-4, -14), 4, 0, TAU, 12, Color("c0392b"), 1.2)
			draw_set_transform(Vector2.ZERO)
		"mirror":
			# Lavabonun üstünde duvara asılı oval ayna.
			var c := rect.get_center()
			draw_set_transform(c, 0.0, Vector2(1.0, 0.8))
			draw_circle(Vector2.ZERO, 26, Color("6b4a2e"))
			draw_circle(Vector2.ZERO, 22, Color("a9cfe0"))
			draw_line(Vector2(-10, -12), Vector2(4, -18), Color(1, 1, 1, 0.6), 3.0)
			draw_line(Vector2(-14, -2), Vector2(-6, -8), Color(1, 1, 1, 0.4), 2.0)
			draw_set_transform(Vector2.ZERO)
		"basket":
			# Hasır çamaşır sepeti, üstünde havlu.
			draw_rect(Rect2(-18, -30, 36, 30), Color("c8a36a"))
			for i in 5:
				draw_line(Vector2(-18, -26 + i * 6), Vector2(18, -26 + i * 6), Color("a07f4c"), 1.5)
			draw_rect(Rect2(-20, -33, 40, 6), Color("8f6f3e"))
			draw_rect(Rect2(-12, -40, 22, 9), Color("e6a7b8"))
		"shower":
			draw_rect(rect, Color(0.5, 0.8, 0.85, 0.45))
			draw_rect(rect, Color("d1e1df"), false, 3)
			draw_line(Vector2(0, -h), Vector2.ZERO, Color.WHITE, 2)
		"mirror_cabinet":
			draw_rect(rect, wood)
			draw_rect(Rect2(-w/2+6, -h+6, w-12, h*0.65), Color("a9cddd"))
		"fridge":
			draw_rect(rect, Color("d2d9d8"))
			draw_line(Vector2(-w/2, -h*0.6), Vector2(w/2, -h*0.6), Color("667880"), 3)
			draw_line(Vector2(w/2-12, -h*0.4), Vector2(w/2-12, -h*0.2), Color("506473"), 4)
		"electrical_box":
			# Duvara monte: sağ kenarı duvara yaslı, arkasında montaj plakası.
			draw_rect(rect.grow(3), Color("3d4a52"))
			draw_rect(rect, Color("7c8d91"))
			for i in range(3):
				draw_rect(Rect2(-w/2+10+i*18, -h+18, 10, 25), Color("e7b858"))
		"bandage":
			# Duvardaki ilk yardım dolabı: beyaz kutu, kırmızı artı, kapak çizgisi.
			var c := rect.get_center()
			draw_rect(rect, Color("e8e0cf"))
			draw_rect(rect, Color("9c9384"), false, 2.0)
			draw_line(c + Vector2(-8, 0), c + Vector2(8, 0), Color("c83a3a"), 5)
			draw_line(c + Vector2(0, -8), c + Vector2(0, 8), Color("c83a3a"), 5)
		"alcohol":
			draw_set_transform(draw_offset)
			if lying:
				draw_rect(Rect2(-h/2, -w, h*0.7, w), Color("769465"))
				draw_rect(Rect2(-h/2 + h*0.7, -w*0.75, h*0.3, w/2), Color("b7c6a2"))
			else:
				draw_rect(Rect2(-w/4, -h, w/2, h*0.3), Color("b7c6a2"))
				draw_rect(Rect2(-w/2, -h*0.7, w, h*0.7), Color("769465"))
			draw_set_transform(Vector2.ZERO)
		"drill":
			# Akülü matkap: sarı gövde, siyah sap, gri uç.
			draw_set_transform(draw_offset)
			draw_rect(Rect2(-11, -16, 18, 8), Color("e0b020"))
			draw_rect(Rect2(-11, -16, 18, 8), Color("5a4510"), false, 1.0)
			draw_rect(Rect2(7, -14, 6, 4), Color("8a8f93"))
			draw_line(Vector2(13, -12), Vector2(18, -12), Color("c9ced1"), 1.5)
			draw_rect(Rect2(-8, -8, 7, 8), Color("2a2a2a"))
			draw_rect(Rect2(-10, -2, 11, 3), Color("3d3d3d"))
			draw_set_transform(Vector2.ZERO)
		"nails":
			# Vida kutusu: karton kutu + üstte vidalar.
			draw_set_transform(draw_offset)
			draw_rect(Rect2(-8, -10, 16, 10), Color("b08850"))
			draw_rect(Rect2(-8, -10, 16, 10), Color("5e4423"), false, 1.0)
			for k in 3:
				draw_line(Vector2(-5 + k * 5, -10), Vector2(-5 + k * 5, -15), Color("c9ced1"), 1.5)
				draw_circle(Vector2(-5 + k * 5, -15), 1.6, Color("dfe3e5"))
			draw_set_transform(Vector2.ZERO)
		"screwdriver":
			draw_rect(rect, Color("d5ad58"))
			draw_line(Vector2(-w/2+4, -h/2) + draw_offset, Vector2(w/2-4, -h/2) + draw_offset, Color("dbe2e3"), 4)
		"toilet":
			draw_rect(Rect2(-w/2, -h, w, h*0.4), Color("eef2f2"))
			draw_set_transform(Vector2(0, -h*0.35), 0, Vector2(1, 1.25))
			draw_circle(Vector2.ZERO, w*0.42, Color("dfe7e8"))
			draw_circle(Vector2.ZERO, w*0.26, Color("9fc3cc"))
			draw_set_transform(Vector2.ZERO)
		"flashlight":
			# Kafa lambası: yatık siyah esnek kayış halkası ve önünde lamba gövdesi.
			draw_set_transform(draw_offset + Vector2(0, -h * 0.5), 0.0, Vector2(1.0, 0.55))
			draw_arc(Vector2.ZERO, w * 0.48, 0.0, TAU, 28, Color("141414"), 4.0)
			draw_set_transform(Vector2.ZERO)
			draw_set_transform(draw_offset)
			draw_rect(Rect2(-6, -h * 0.5 - 1, 12, 9), Color("1f1f22"))
			draw_rect(Rect2(-6, -h * 0.5 - 1, 12, 2), Color("55585c"))
			draw_circle(Vector2(0, -h * 0.5 + 4), 2.6, Color("ffe08a"))
			draw_set_transform(Vector2.ZERO)
		"fire_extinguisher":
			draw_rect(Rect2(-w/2, -h*0.85, w, h*0.85), Color("cf2f2f"))
			draw_rect(Rect2(-w/4, -h, w/2, h*0.15), Color("1f1f1f"))
		"cat" when under_bed:
			# Yatağın altındaki karanlık boşluk ve parlayan iki göz (ara ara kırpar).
			draw_set_transform(Vector2(0, -12), 0.0, Vector2(1, 0.35))
			draw_circle(Vector2.ZERO, 26, Color(0, 0, 0, 0.55))
			draw_set_transform(Vector2.ZERO)
			var t := Time.get_ticks_msec() / 1000.0
			var out := Vector2(approach * 78.0, 0)
			if approach < 0.3:
				if fmod(t, 3.4) > 0.16:
					for ex in [-5.0, 5.0]:
						draw_circle(out + Vector2(ex, -13), 3.2, Color(0.6, 1.0, 0.35, 0.35))
						draw_circle(out + Vector2(ex, -13), 1.6, Color(0.85, 1.0, 0.6))
			elif jump > 0.0:
				# Son anda acele: oyuncuya doğru koşar.
				var pos := out.lerp(jump_to, jump)
				CatSprite.draw(self, "run", CatSprite.dir_of(jump_to - out), t, 13.0, pos, 1.7)
			elif approach < 0.75:
				# Çekingen: önce etrafa bakınır, sonra yavaş adımlarla çıkar.
				var anim := "look" if fmod(t, 2.4) < 1.0 else "walk"
				CatSprite.draw(self, anim, CatSprite.RIGHT, t, 4.0 if anim == "walk" else 3.0, out + Vector2(0, -hop * 4.0), 1.7)
			else:
				CatSprite.draw(self, "run", CatSprite.RIGHT, t, 12.0, out + Vector2(0, -hop * 4.0), 1.7)
		"cat":
			# Depremden önce yatağın üstünde uzanmış uyur (yatma animasyonunun son karesi, ara ara kıpırdar).
			var tt := Time.get_ticks_msec() / 1000.0
			var lay_frame := 7 if fmod(tt, 6.0) > 0.8 else 6
			CatSprite.draw(self, "lay", CatSprite.RIGHT, float(lay_frame), 1.0, Vector2(0, -40), 1.7)
		"heater":
			# Piksel sanat elektrikli soba (krom ızgara, akkor çubuklar); 2x ölçek.
			if heater_tex == null:
				heater_tex = _load_tex("res://assets/bedroom/heater.png")
			if heater_tex != null:
				var hs := Vector2(heater_tex.get_size()) * 2.0
				var glow := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)
				if toppled:
					# Yan yatmış soba: gövde yere paralel, akkor çubuklar yukarı bakar ve daha kızgın.
					draw_set_transform(Vector2(-hs.y * 0.5, -hs.x * 0.5), PI * 0.5)
					draw_texture_rect(heater_tex, Rect2(Vector2(-hs.x * 0.5, -hs.y), hs), false, Color(1.15, 1.0, 0.9))
					draw_set_transform(Vector2.ZERO)
					draw_circle(Vector2(0, -hs.x * 0.5), hs.y * 0.45, Color(1.0, 0.45, 0.15, 0.10 + 0.05 * glow))
				else:
					draw_circle(Vector2(0, -hs.y * 0.55), hs.x * 0.55, Color(1.0, 0.55, 0.2, 0.06 + 0.03 * glow))
					draw_texture_rect(heater_tex, Rect2(Vector2(-hs.x * 0.5, -hs.y), hs), false)
		"sofa":
			draw_rect(rect, Color("5b8682"))
			draw_rect(Rect2(-w/2+12, -h+25, w-24, h-32), Color("83a6a0"))
		_:
			draw_rect(rect, wood)
			draw_rect(Rect2(-w/2, -h, w, 15), Color("c2a47d"))
			if kind == "wardrobe":
				draw_line(Vector2(0, -h+15), Vector2.ZERO, Color("574634"), 2)
	if weathered:
		_draw_weathering()
	if kind == "flashlight" and world != null and world.game.lights_out:
		# Karanlıkta fenerin camında ara ara parlayan yansıma: kolay fark edilsin.
		var tg := fmod(Time.get_ticks_msec() / 1000.0, 1.6)
		draw_circle(rect.get_center(), 14.0, Color(1, 0.95, 0.7, 0.08))
		if tg < 0.5:
			var a := sin(tg / 0.5 * PI)
			var c2 := rect.get_center() + Vector2(size.x * 0.3, -2)
			draw_line(c2 - Vector2(8, 0) * a, c2 + Vector2(8, 0) * a, Color(1, 0.97, 0.8, a), 1.5)
			draw_line(c2 - Vector2(0, 8) * a, c2 + Vector2(0, 8) * a, Color(1, 0.97, 0.8, a), 1.5)
			draw_circle(c2, 2.5 * a, Color(1, 1, 0.9, a))

	if fallen:
		draw_line(Vector2(-w/2, -h), Vector2(w/2, 0), Color("d45848"), 5)
	if anchored and kind == "wardrobe":
		_draw_wall_screws(rect)
	elif anchored:
		draw_circle(Vector2(w/2-8, -h+8), 5, Color("77c392"))
	if visible and world != null and world.game.player.focus == self:
		# Yalnız odaktaki eşyanın yazısı, eşyanın üstünde ortalı ve okunur arka planla.
		var label := "[E] " + caption
		var font := ThemeDB.fallback_font
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var top := minf(rect.position.y, -h) - 10.0
		draw_rect(Rect2(-tw / 2.0 - 5, top - 15, tw + 10, 20), Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(-tw / 2.0, top), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

# Küçük piksel kedi (turuncu tekir), sağa bakar; kuyruk sallanır.
func _draw_pixel_cat(o: Vector2, t: float) -> void:
	var fur := Color("d98b3a")
	var dark := Color("a8601f")
	var px := func(x: float, y: float, w: float, h: float, c: Color) -> void:
		draw_rect(Rect2(o + Vector2(x, y) * 2.0, Vector2(w, h) * 2.0), c)
	draw_set_transform(o + Vector2(0, -1), 0.0, Vector2(1, 0.3))
	draw_circle(Vector2.ZERO, 16, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	var tail := int(sin(t * 5.0) * 1.5)
	px.call(-9, -7 + tail, 2, 4, dark)
	px.call(-8, -6, 11, 5, fur)
	px.call(-6, -6, 2, 5, dark)
	px.call(-2, -6, 2, 5, dark)
	px.call(-7, -1, 2, 1, dark)
	px.call(1, -1, 2, 1, dark)
	px.call(2, -10, 6, 5, fur)
	px.call(2, -12, 2, 2, dark)
	px.call(6, -12, 2, 2, dark)
	px.call(5, -9, 1, 1, Color("3a5a1a"))
	px.call(7, -8, 1, 1, Color("2a1a14"))


# --- Ev süsleri -------------------------------------------------------------------

func _frame(r: Rect2, wood: Color) -> void:
	draw_rect(r.grow(3), Color(0, 0, 0, 0.25))
	draw_rect(r, wood)
	draw_rect(r, wood.darkened(0.4), false, 1.5)


# Görseli olan süsler: PNG'nin yalnız dolu bölgesi çizilir. [yol, ölçek, hiza (alt: taban ortası / orta)]
const DECOR_SPRITES := {
	"guitar": ["res://assets/decor/guitar.png", 1.25, "bottom"],
	"trash_bin": ["res://assets/decor/trash_bin.png", 1.0, "bottom"],
	"calendar": ["res://assets/decor/calendar.png", 1.15, "center"],
	# Piksel sanat saksı bitkileri (oda renklerine göre); 2x tam sayı ölçek, pikseller keskin kalır.
	"plant_salon": ["res://assets/plants/plant_salon.png", 2.0, "bottom"],
	"plant_bedroom": ["res://assets/plants/plant_bedroom.png", 2.0, "bottom"],
	"plant_kitchen": ["res://assets/plants/plant_kitchen.png", 2.0, "bottom"],
	"plant_bath": ["res://assets/plants/plant_bath.png", 2.0, "bottom"],
	"sill_geranium": ["res://assets/plants/sill_geranium.png", 2.0, "bottom"],
	"herb_basil": ["res://assets/plants/herb_basil.png", 2.0, "bottom"],
	"plant_big": ["res://assets/plants/plant_salon.png", 2.0, "bottom"],
}
var decor_sprite: Texture2D
var heater_tex: Texture2D
var decor_region := Rect2()


func _draw_decor(rect: Rect2) -> void:
	var c := rect.get_center()
	if DECOR_SPRITES.has(style):
		if decor_sprite == null:
			decor_sprite = _load_tex(DECOR_SPRITES[style][0])
			if decor_sprite != null:
				decor_region = Rect2(decor_sprite.get_image().get_used_rect())
		if decor_sprite != null:
			var k: float = DECOR_SPRITES[style][1]
			var sz := decor_region.size * k
			if DECOR_SPRITES[style][2] == "bottom":
				draw_set_transform(Vector2(c.x, rect.end.y), sprite_rotation)
				draw_texture_rect_region(decor_sprite, Rect2(Vector2(-sz.x * 0.5, -sz.y), sz), decor_region)
				draw_set_transform(Vector2.ZERO)
			else:
				draw_texture_rect_region(decor_sprite, Rect2(c - sz * 0.5, sz), decor_region)
			return
	match style:
		"photo", "photo_wide":
			# Aile fotoğrafı: ahşap çerçeve, açık fon, gülümseyen üç kişi.
			var size := Vector2(30, 36) if style == "photo" else Vector2(46, 32)
			var r := Rect2(c - size * 0.5, size)
			_frame(r, Color("7a4f2c"))
			var inner := r.grow(-4)
			draw_rect(inner, Color("cfe0e6"))
			draw_rect(Rect2(inner.position.x, inner.end.y - inner.size.y * 0.35, inner.size.x, inner.size.y * 0.35), Color("9cc07a"))
			var people := [[-0.28, Color("c0392b"), 1.0], [0.0, Color("2f6fb0"), 0.8], [0.28, Color("e0b020"), 0.62]] if style == "photo_wide" else [[-0.2, Color("8e44ad"), 1.0], [0.2, Color("2f6fb0"), 0.9]]
			for pp in people:
				var px: float = c.x + inner.size.x * pp[0]
				var h: float = inner.size.y * 0.55 * pp[2]
				draw_rect(Rect2(px - 3.5, inner.end.y - h, 7, h * 0.6), pp[1])
				draw_circle(Vector2(px, inner.end.y - h - 3), 3.5, Color("e0b090"))
				draw_rect(Rect2(px - 3.5, inner.end.y - h - 7, 7, 3), Color("4a3020"))
			draw_line(inner.position + Vector2(2, 2), inner.position + Vector2(8, 2), Color(1, 1, 1, 0.6), 1.0)
		"ataturk":
			# Yaldız çerçeveli Atatürk portresi (piksel): koyu fon, geriye taranmış saç, açık mavi gözler,
			# siyah takım elbise, beyaz gömlek ve kravat.
			var art := [
				"..............",
				"....HHHHHH....",
				"...HHHHHHHH...",
				"...HhHHHHHh...",
				"...SSSSSSSS...",
				"...bbSSSSbb...",
				"...SESSSSES...",
				"..sSSSSnSSSs..",
				"...SSSSnSSS...",
				"...SSmmmmSS...",
				"....sSSSSs....",
				".....sSSs.....",
				"...KKWWWWKK...",
				"..KKKKWTWKKKK.",
				".KKKkKWTWKkKKK",
				"KKKKkKKTKKkKKK",
				"KKKKKKKKKKKKKK",
				"KKKKKKKKKKKKKK",
				"KKKKKKKKKKKKKK"]
			var pal := {".": Color("2b3442"), "H": Color("c19a62"), "h": Color("8f6d40"), "S": Color("e9c4a2"),
				"s": Color("c99a78"), "b": Color("6b4a2a"), "E": Color("6a9fd0"), "n": Color("cf9f7e"),
				"m": Color("a8705a"), "W": Color("f2f0ea"), "T": Color("3a2626"), "K": Color("1c1c22"), "k": Color("383844")}
			var cell := 2.0
			var art_size := Vector2(14, 19) * cell
			var r := Rect2(c - art_size * 0.5, art_size)
			# Kalın yaldız çerçeve: dış koyu kenar, altın gövde, iç gölge.
			draw_rect(r.grow(7), Color("3a2a12"))
			draw_rect(r.grow(6), Color("c9a24a"))
			draw_rect(Rect2(r.grow(6).position, Vector2(r.grow(6).size.x, 2)), Color("efd27e"))
			draw_rect(r.grow(2), Color("8a6a24"))
			draw_rect(r.grow(1), Color("4a3612"))
			for y in art.size():
				var row: String = art[y]
				for x in row.length():
					draw_rect(Rect2(r.position + Vector2(x, y) * cell, Vector2(cell, cell)), pal[row[x]])
			# Camda hafif parıltı.
			draw_line(r.position + Vector2(3, 3), r.position + Vector2(10, 3), Color(1, 1, 1, 0.18), 1.0)
		"painting":
			# Yaldız çerçeveli manzara tablosu: gün batımı, tepeler, göl.
			var r := Rect2(c - Vector2(30, 21), Vector2(60, 42))
			_frame(r, Color("b8902f"))
			var inner := r.grow(-5)
			for i in 6:
				draw_rect(Rect2(inner.position.x, inner.position.y + i * inner.size.y / 12.0, inner.size.x, inner.size.y / 12.0 + 1), Color("f6c27a").lerp(Color("e07a5f"), i / 6.0))
			draw_circle(Vector2(inner.end.x - 12, inner.position.y + inner.size.y * 0.42), 5, Color("fff0b0"))
			draw_colored_polygon(PackedVector2Array([Vector2(inner.position.x, inner.end.y - 10), Vector2(inner.position.x + 18, inner.position.y + 16), Vector2(inner.position.x + 34, inner.end.y - 12), Vector2(inner.end.x, inner.position.y + 20), Vector2(inner.end.x, inner.end.y), Vector2(inner.position.x, inner.end.y)]), Color("5b7a4a"))
			draw_rect(Rect2(inner.position.x, inner.end.y - 6, inner.size.x, 6), Color("4f7fa8"))
		"clock":
			# Canlı duvar saati: gerçek saate göre akrep/yelkovan.
			draw_circle(c + Vector2(2, 2), 16, Color(0, 0, 0, 0.25))
			draw_circle(c, 16, Color("6b4226"))
			draw_circle(c, 13, Color("f1e6cc"))
			for h in 12:
				var a := TAU * h / 12.0
				draw_line(c + Vector2.from_angle(a) * 10, c + Vector2.from_angle(a) * 12, Color("4a3020"), 1.5 if h % 3 == 0 else 1.0)
			var tm := Time.get_time_dict_from_system()
			var ma: float = TAU * (tm.minute / 60.0) - PI * 0.5
			var ha: float = TAU * ((tm.hour % 12) / 12.0 + tm.minute / 720.0) - PI * 0.5
			draw_line(c, c + Vector2.from_angle(ha) * 6, Color("2a1a10"), 2.0)
			draw_line(c, c + Vector2.from_angle(ma) * 10, Color("2a1a10"), 1.5)
			draw_line(c, c + Vector2.from_angle(TAU * (tm.second / 60.0) - PI * 0.5) * 11, Color("b0302a"), 1.0)
			draw_circle(c, 1.5, Color("2a1a10"))
		"shelf":
			# Duvar rafı: renkli kitap sırtları, küçük saksı ve kavanoz.
			draw_rect(Rect2(c.x - 34, c.y + 8, 68, 5), Color("6b4226"))
			var cols := [Color("c0392b"), Color("2f6fb0"), Color("27ae60"), Color("e0b020"), Color("8e44ad")]
			for i in 5:
				var hgt := 16.0 + (i % 3) * 3
				draw_rect(Rect2(c.x - 32 + i * 7, c.y + 8 - hgt, 6, hgt), cols[i])
			draw_rect(Rect2(c.x + 8, c.y - 1, 10, 9), Color("b5653a"))
			draw_circle(Vector2(c.x + 13, c.y - 5), 6, Color("4f9a45"))
			draw_rect(Rect2(c.x + 22, c.y - 6, 10, 14), Color(0.8, 0.9, 0.95, 0.7))
		"bookshelf":
			# Duvara yaslı kitaplık: 3 raf dolusu kitap; eskiyse soluk renkler, çizikler, toz ve örümcek ağı.
			var aged := weathered
			draw_rect(rect, Color("5e4630") if aged else Color("6b4226"))
			draw_rect(rect, Color("3e2414"), false, 2.0)
			var cols2 := [Color("c0392b"), Color("2f6fb0"), Color("27ae60"), Color("e0b020"), Color("8e44ad"), Color("d35400"), Color("16a085")]
			if aged:
				for ci in cols2.size():
					cols2[ci] = cols2[ci].lerp(Color("8a7a66"), 0.45)
			for row in 3:
				var y := rect.position.y + 6 + row * (rect.size.y - 10) / 3.0
				var x := rect.position.x + 5
				var i := row * 2
				while x < rect.end.x - 8:
					var bw := 4.0 + (i % 3)
					var bh := (rect.size.y - 10) / 3.0 - 4 - (i % 2) * 3
					draw_rect(Rect2(x, y + ((rect.size.y - 10) / 3.0 - 4 - bh), bw, bh), cols2[i % cols2.size()])
					x += bw + 1
					i += 1
				draw_rect(Rect2(rect.position.x + 3, y + (rect.size.y - 10) / 3.0 - 4, rect.size.x - 6, 3), Color("3e2414"))
			if aged:
				# Devrilmiş bir kitap, yan yüzde çizikler, üst köşede örümcek ağı ve toz.
				draw_set_transform(Vector2(rect.end.x - 14, rect.position.y + 30), 0.5)
				draw_rect(Rect2(-3, -9, 6, 14), Color("8a6a5a"))
				draw_set_transform(Vector2.ZERO)
				for k in 4:
					var sy := rect.position.y + 14 + k * 17.0
					draw_line(Vector2(rect.position.x + 2, sy), Vector2(rect.position.x + 2 + 6, sy + 3), Color(0.85, 0.75, 0.6, 0.35), 1.0)
				var corner := rect.position + Vector2(2, 2)
				for k in 4:
					draw_line(corner, corner + Vector2.from_angle(k * 0.4) * 16.0, Color(0.9, 0.9, 0.9, 0.35), 0.8)
				draw_arc(corner, 8.0, 0.0, 1.3, 6, Color(0.9, 0.9, 0.9, 0.3), 0.8)
				draw_arc(corner, 13.0, 0.0, 1.3, 6, Color(0.9, 0.9, 0.9, 0.25), 0.8)
				draw_rect(Rect2(rect.position.x, rect.position.y - 2, rect.size.x, 2), Color(0.75, 0.72, 0.68, 0.5))
		"vase":
			# Çiçekli vazo.
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - 6, c.y + 10), Vector2(c.x + 6, c.y + 10), Vector2(c.x + 8, c.y), Vector2(c.x + 4, c.y - 6), Vector2(c.x - 4, c.y - 6), Vector2(c.x - 8, c.y)]), Color("4f8fbf"))
			for f in [[-8, -20, Color("e74c3c")], [0, -24, Color("f1c40f")], [8, -19, Color("e84393")], [-3, -16, Color("ffffff")]]:
				draw_line(Vector2(c.x, c.y - 6), Vector2(c.x + f[0], c.y + f[1]), Color("3f7d3a"), 1.5)
				draw_circle(Vector2(c.x + f[0], c.y + f[1]), 3.5, f[2])
		"books_stack":
			# Üst üste kitaplar.
			var cols := [Color("8e3b3b"), Color("3b5f8e"), Color("c9a24a"), Color("4f7a46")]
			for i in 4:
				draw_rect(Rect2(c.x - 12 + (i % 2) * 2, rect.end.y - 5 - i * 5, 22 - (i % 2) * 3, 5), cols[i])
				draw_rect(Rect2(c.x - 12 + (i % 2) * 2, rect.end.y - 5 - i * 5, 22 - (i % 2) * 3, 1), Color(1, 1, 1, 0.25))
		"shoe_rack":
			# Kapı yanında alçak ayakkabılık ve üstünde iki çift ayakkabı.
			draw_rect(Rect2(c.x - 22, rect.end.y - 14, 44, 14), Color("7a5634"))
			draw_rect(Rect2(c.x - 22, rect.end.y - 8, 44, 2), Color("5a3e24"))
			draw_rect(Rect2(c.x - 18, rect.end.y - 20, 14, 6), Color("2c2c34"))
			draw_rect(Rect2(c.x + 4, rect.end.y - 20, 14, 6), Color("9a3a2a"))
		"cat_bowl":
			# Osman'ın mama ve su kabı.
			draw_set_transform(Vector2(c.x - 8, rect.end.y - 4), 0.0, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, 9, Color("c0392b"))
			draw_circle(Vector2.ZERO, 6, Color("8a5a2a"))
			draw_set_transform(Vector2(c.x + 10, rect.end.y - 4), 0.0, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, 9, Color("2e86c1"))
			draw_circle(Vector2.ZERO, 6, Color("aed6f1"))
			draw_set_transform(Vector2.ZERO)
		"slippers":
			for i in 2:
				draw_set_transform(Vector2(c.x - 7 + i * 13, rect.end.y - 5), 0.15 * (i * 2 - 1), Vector2(1.0, 0.5))
				draw_circle(Vector2.ZERO, 6, Color("d98fa0"))
				draw_circle(Vector2(0, -2), 4, Color("f2c4ce"))
			draw_set_transform(Vector2.ZERO)
		"guitar":
			# Duvara yaslı gitar.
			draw_set_transform(Vector2(c.x, rect.end.y), -0.18)
			draw_rect(Rect2(-2, -58, 4, 30), Color("5a3e24"))
			draw_rect(Rect2(-3, -62, 6, 6), Color("2c2018"))
			draw_circle(Vector2(0, -18), 11, Color("b5651d"))
			draw_circle(Vector2(0, -8), 12, Color("b5651d"))
			draw_circle(Vector2(0, -15), 3, Color("2c2018"))
			draw_set_transform(Vector2.ZERO)
		"trash_bin":
			draw_rect(Rect2(c.x - 9, rect.end.y - 22, 18, 22), Color("7f8c8d"))
			draw_rect(Rect2(c.x - 11, rect.end.y - 24, 22, 4), Color("5d6d6e"))
			for i in 3:
				draw_line(Vector2(c.x - 5 + i * 5, rect.end.y - 19), Vector2(c.x - 5 + i * 5, rect.end.y - 3), Color("6c7a7b"), 1.0)
		"toilet_paper":
			draw_rect(Rect2(c.x - 1, rect.end.y - 28, 2, 28), Color("9aa3a8"))
			for i in 2:
				draw_circle(Vector2(c.x, rect.end.y - 8 - i * 9), 5, Color("f4f1ea"))
				draw_circle(Vector2(c.x, rect.end.y - 8 - i * 9), 1.5, Color("c9c2b2"))
		"scale":
			draw_rect(Rect2(c.x - 13, rect.end.y - 9, 26, 9), Color("ecf0f1"))
			draw_rect(Rect2(c.x - 6, rect.end.y - 8, 12, 4), Color("2c3e50"))
		"bath_mat":
			draw_rect(Rect2(c.x - 32, rect.end.y - 14, 64, 14), Color("6fa8a0"))
			for i in 6:
				draw_rect(Rect2(c.x - 30 + i * 11, rect.end.y - 12, 5, 10), Color("8cc4bb"))
		"spice_rack":
			# Duvarda baharat rafı.
			draw_rect(Rect2(c.x - 23, rect.end.y - 3, 46, 3), Color("7a5634"))
			var jars := [Color("c0392b"), Color("f1c40f"), Color("27ae60"), Color("8e5a2a"), Color("e67e22")]
			for i in 5:
				draw_rect(Rect2(c.x - 21 + i * 9, rect.end.y - 13, 7, 10), jars[i])
				draw_rect(Rect2(c.x - 21 + i * 9, rect.end.y - 14, 7, 2), Color("ecf0f1"))
		"calendar":
			var r := Rect2(c - Vector2(16, 20), Vector2(32, 40))
			draw_rect(r.grow(2), Color(0, 0, 0, 0.2))
			draw_rect(r, Color("f4f1ea"))
			draw_rect(Rect2(r.position, Vector2(r.size.x, 10)), Color("c0392b"))
			for row in 4:
				for col in 5:
					draw_rect(Rect2(r.position + Vector2(3 + col * 6, 14 + row * 6), Vector2(4, 4)), Color("b8b3a8") if (row * 5 + col) != 12 else Color("c0392b"))
		"round_table":
			# Yuvarlak yan sehpa ve üstünde küçük abajur.
			draw_set_transform(Vector2(c.x, rect.end.y - 26), 0.0, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, 18, Color("8a5a34"))
			draw_circle(Vector2.ZERO, 15, Color("a36d42"))
			draw_set_transform(Vector2.ZERO)
			draw_rect(Rect2(c.x - 2, rect.end.y - 24, 4, 24), Color("6b4226"))
			draw_rect(Rect2(c.x - 8, rect.end.y - 2, 16, 2), Color("6b4226"))
			draw_rect(Rect2(c.x - 1.5, rect.end.y - 44, 3, 16), Color("c9a24a"))
			var lit := emits_light and light_on and flicker_lit
			if lit:
				draw_circle(Vector2(c.x, rect.end.y - 48), 16, Color(1, 0.82, 0.45, 0.22))
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - 10, rect.end.y - 42), Vector2(c.x + 10, rect.end.y - 42), Vector2(c.x + 6, rect.end.y - 56), Vector2(c.x - 6, rect.end.y - 56)]), Color("fff1c8") if lit else Color("cfc2a4"))
		"shards":
			# Yere düşüp kırılmış tabak ve bardak parçaları.
			var rng := RandomNumberGenerator.new()
			rng.seed = int(position.x * 13 + position.y)
			for k in 9:
				var p := c + Vector2(rng.randf_range(-22, 22), rng.randf_range(-8, 8))
				var r := rng.randf_range(2.0, 5.0)
				var col := Color("f2efe6") if k % 3 != 0 else Color("6f9fc8")
				draw_colored_polygon(PackedVector2Array([p + Vector2(-r, 0), p + Vector2(0, -r * 0.6), p + Vector2(r, r * 0.2), p + Vector2(r * 0.2, r * 0.6)]), col)
		"fruit_bowl":
			draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
			draw_circle(Vector2.ZERO, 12, Color("d8d2c4"))
			draw_set_transform(Vector2.ZERO)
			for f in [[-6, -3, Color("e74c3c")], [2, -5, Color("f39c12")], [7, -2, Color("27ae60")], [-1, -1, Color("e74c3c")]]:
				draw_circle(c + Vector2(f[0], f[1]), 4, f[2])


# Mutfak dolapları: tezgâh (çekmece/kapak), ocak (4 göz + fırın camı), eviye (lavabo + musluk).
func _draw_kitchen(rect: Rect2) -> void:
	draw_rect(rect, Color("e9e2d2"))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 10)), Color("8a7a66"))
	draw_rect(Rect2(rect.position + Vector2(0, 10), Vector2(rect.size.x, 3)), Color(0, 0, 0, 0.2))
	var doors := maxi(1, int(rect.size.x / 34.0))
	var dw := rect.size.x / doors
	for i in doors:
		var d := Rect2(rect.position.x + i * dw + 3, rect.position.y + 16, dw - 6, rect.size.y - 20)
		draw_rect(d, Color("d8cfbc"))
		draw_rect(d, Color("a99f8c"), false, 1.5)
		draw_rect(Rect2(d.get_center().x - 5, d.position.y + 5, 10, 2), Color("7a6f5c"))
	match kind:
		"stove":
			for k in 4:
				var b := rect.position + Vector2(rect.size.x * (0.28 + 0.44 * (k % 2)), 5 + 0.0)
				draw_set_transform(b, 0.0, Vector2(1.0, 0.45))
				draw_circle(Vector2.ZERO, 7, Color("2a2a2a"))
				draw_arc(Vector2.ZERO, 5, 0, TAU, 16, Color("555555"), 1.5)
				draw_set_transform(Vector2.ZERO)
			var glass := Rect2(rect.position + Vector2(8, 20), Vector2(rect.size.x - 16, rect.size.y - 30))
			draw_rect(glass, Color("2b2b2b"))
			draw_rect(Rect2(glass.position + Vector2(4, 4), Vector2(glass.size.x * 0.4, 3)), Color(1, 1, 1, 0.15))
		"kitchen_sink":
			var basin := Rect2(rect.get_center().x - 18, rect.position.y + 1, 36, 8)
			draw_rect(basin, Color("b9c2c7"))
			draw_rect(basin.grow(-2), Color("8e989d"))
			draw_line(Vector2(rect.get_center().x, rect.position.y - 8), Vector2(rect.get_center().x, rect.position.y + 2), Color("c9cfd2"), 3.0)
			draw_line(Vector2(rect.get_center().x, rect.position.y - 8), Vector2(rect.get_center().x + 8, rect.position.y - 8), Color("c9cfd2"), 3.0)


# Duvara vidalı dolap: köşelerde L-bağlantı plakası ve vida başları (screws_shown kadar).
func _draw_wall_screws(rect: Rect2) -> void:
	var inner := Rect2(rect.position + Vector2(18, 10), rect.size - Vector2(38, 30))
	var corners := [inner.position, Vector2(inner.end.x, inner.position.y),
		Vector2(inner.position.x, inner.end.y), inner.end]
	for i in mini(screws_shown, 4):
		var c: Vector2 = corners[i]
		draw_rect(Rect2(c - Vector2(6, 6), Vector2(12, 12)), Color("9aa3a8"))
		draw_rect(Rect2(c - Vector2(6, 6), Vector2(12, 12)), Color("4b5257"), false, 1.5)
		draw_circle(c, 3.2, Color("d7dcdf"))
		draw_line(c + Vector2(-2.2, -2.2), c + Vector2(2.2, 2.2), Color("3a3f43"), 1.4)
		draw_line(c + Vector2(-2.2, 2.2), c + Vector2(2.2, -2.2), Color("3a3f43"), 1.4)
		# Delinmiş ahşap tozu.
		draw_circle(c + Vector2(4, 6), 1.5, Color(0.85, 0.75, 0.55, 0.8))


# Tesisat kutusundan sarkan, ucu soyulmuş kablo suya değer; elektrik varken kıvılcım çıkar.
func _draw_loose_cable() -> void:
	var start := Vector2(size.x * 0.25, -size.y * 0.3)
	var tip := Vector2(48, 30)
	var pts := PackedVector2Array()
	for i in 9:
		var k := i / 8.0
		pts.append(start.lerp(tip, k) + Vector2(0, sin(k * PI) * 14.0))
	draw_polyline(pts, Color("1d1d1d"), 4.0)
	draw_polyline(pts, Color("3a3a3a"), 2.0)
	draw_line(tip, tip + Vector2(6, 2), Color("d98a3d"), 2.5)
	var live: bool = world != null and world.electrical_fault and not world.game.electricity_off
	if live:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(Time.get_ticks_msec() / 60)
		for k in 3:
			var p := tip + Vector2(6, 2)
			var bolt := PackedVector2Array([p])
			for j in 3:
				p += Vector2(rng.randf_range(-6, 8), rng.randf_range(-6, 6))
				bolt.append(p)
			draw_polyline(bolt, Color(1, 0.95, 0.5, 0.9), 1.5)


func _draw_weathering() -> void:
	var areas: Array[Rect2] = []
	if kind == "kitchen_counter":
		areas = [Rect2(-size.x/2+5, -size.y+5, size.x-10, 25),
			Rect2(-size.x/2+5, -size.y+40, 25, size.y-45)]
	else:
		areas = [Rect2(-size.x/2+6, -size.y+7, size.x-12, minf(22, size.y*0.4))]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(position.x * 31 + position.y * 17)
	for area in areas:
		for i in range(7):
			var point := area.position + Vector2(rng.randf_range(2, area.size.x-4), rng.randf_range(2, area.size.y-4))
			var length := minf(rng.randf_range(3, 12), area.end.x-point.x)
			draw_line(point, point + Vector2(length, 0), Color(0.89, 0.75, 0.52, 0.38), 1.0)
		for i in range(3):
			var knot := area.position + Vector2(rng.randf_range(3, area.size.x-3), rng.randf_range(3, area.size.y-3))
			draw_circle(knot, 1.5, Color(0.24, 0.17, 0.11, 0.3))
