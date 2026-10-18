extends Node2D

# Yatak odası yangını: devrilen elektrikli sobadan odanın alt kısmına yayılmış alev kümeleri.
# Her alevin şiddeti (0-1) vardır; püskürtülmeyen alev yavaşça yeniden büyür, sıfıra inen söner
# ve buhar çıkarır. Hepsi sönünce all_out yayınlanır. Alevlerin yanında durmak can yakar.
signal all_out

const ROOM := &"yatak_odasi"
const SPRAY_RANGE := 210.0
const SPRAY_HALF_ANGLE := deg_to_rad(30.0)
const REGROW := 0.05
const MIX_RATE := 22050
# Ateş duvarının oda-yerel x merkezi (yatak x 100 ile kapı x 600 arası).
const WALL_X := 302.0
# Yayılma: alevler sobadan uzaklıklarına göre sırayla tutuşur (px/sn), yeni alev yavaşça büyür.
const SPREAD_SPEED := 16.0
const KINDLE_GROW := 0.22
var age := 0.0

var game: Node2D
var fires: Array[Dictionary] = []
var lights: Array[PointLight2D] = []
# Her ışığın parlaklığını belirleyen alev aralığı (fires içinde [başlangıç, bitiş)).
var light_ranges: Array[Vector2i] = []
var active := false
var hurt_clock := 0.0
var soft_tex: Texture2D
var roar: AudioStreamPlayer
var add_material := CanvasItemMaterial.new()


func _ready() -> void:
	y_sort_enabled = true
	add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	soft_tex = _soft_texture()
	roar = AudioStreamPlayer.new()
	roar.stream = _build_roar()
	roar.volume_db = -40.0
	add_child(roar)


func ignite(source := Vector2.ZERO) -> void:
	if active:
		return
	active = true
	age = 0.0
	var origin: Vector2 = game.ROOMS[ROOM].position
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# Ateş duvarı: kapı ile kedinin yatağı arasında, duvardan duvara iki sütun alev
	# (oda-yerel koordinat); devrilen sobanın çevresinde yoğun küme.
	var points: Array[Vector2] = []
	for column in [WALL_X - 18.0, WALL_X + 18.0]:
		var y := 40.0
		while y < 318.0:
			points.append(Vector2(column + rng.randf_range(-6, 6), y + rng.randf_range(-5, 5)))
			y += 33.0
	for p in [Vector2(WALL_X + 52, 300), Vector2(WALL_X + 70, 326), Vector2(WALL_X + 40, 330)]:
		points.append(p)
	if source == Vector2.ZERO:
		source = origin + Vector2(WALL_X + 52, 300)
	for p in points:
		_add_fire(origin + p, rng.randf_range(0.8, 1.0))
		var f: Dictionary = fires[-1]
		f.delay = (origin + p).distance_to(source) / SPREAD_SPEED
		# Sobanın dibindekiler kendiliğinden tutuşur; diğerleri ancak yanında yanan alev varsa.
		f.force = (origin + p).distance_to(source) < 45.0
		f.max = f.intensity
		f.lit = false
		f.intensity = 0.0
		f.node.visible = false
		for key in ["smoke", "flames", "core", "embers"]:
			f[key].emitting = false
	# Kümelere ortak, titreyen turuncu ışık (her 4 alev bir ışık).
	for i in range(0, fires.size(), 8):
		var light := PointLight2D.new()
		light.texture = soft_tex
		light.texture_scale = 8.5
		light.color = Color(1.0, 0.55, 0.22)
		light.energy = 0.0
		light.range_item_cull_mask = 1
		var sum := Vector2.ZERO
		var n := 0
		for j in range(i, mini(i + 8, fires.size())):
			sum += fires[j].pos
			n += 1
		light.global_position = sum / n + Vector2(0, -24)
		add_child(light)
		lights.append(light)
		light_ranges.append(Vector2i(i, mini(i + 8, fires.size())))
	roar.play()


# Tüpsüz yakalanan oyuncuyu köşeye sıkıştırır: duvardan yatağa doğru her aralıkta yeni bir alev
# sütunu tutuşur; alevler sonunda oyuncuya ulaşır.
func close_in(to_x := 20.0, step := 46.0, interval := 3.2) -> void:
	var origin: Vector2 = game.ROOMS[ROOM].position
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var k := 1
	var x := WALL_X - 18.0 - step
	while x > to_x:
		var first := fires.size()
		var y := 30.0
		while y < 320.0:
			_add_fire(origin + Vector2(x + rng.randf_range(-7, 7), y + rng.randf_range(-6, 6)), rng.randf_range(0.8, 1.0))
			var f: Dictionary = fires[-1]
			f.delay = age + 2.0 + k * interval + absf(y - 180.0) / 300.0
			f.force = true
			f.max = f.intensity
			f.lit = false
			f.intensity = 0.0
			f.node.visible = false
			for key in ["smoke", "flames", "core", "embers"]:
				f[key].emitting = false
			y += 34.0
		var light := PointLight2D.new()
		light.texture = soft_tex
		light.texture_scale = 8.5
		light.color = Color(1.0, 0.55, 0.22)
		light.energy = 0.0
		light.range_item_cull_mask = 1
		light.global_position = origin + Vector2(x, 180)
		add_child(light)
		lights.append(light)
		light_ranges.append(Vector2i(first, fires.size()))
		k += 1
		x -= step


func _add_fire(pos: Vector2, intensity: float) -> void:
	var node := Node2D.new()
	node.position = pos
	add_child(node)
	# Çizim sırası: duman arkada, sonra alev gövdesi, sıcak çekirdek, kıvılcımlar.
	var smoke := _emitter(node, 5, 2.8, Vector2(0, -46), Vector2(10, 4), Vector2(0, -34), Vector2(10, 22),
		Vector2(1.6, 3.2), _ramp([Color(0.09, 0.08, 0.08, 0.0), Color(0.08, 0.07, 0.07, 0.26), Color(0.05, 0.05, 0.05, 0.0)], [0.0, 0.3, 1.0]), false)
	smoke.scale_amount_curve = _grow_curve(0.5, 1.6)
	# Alev dilleri: dar tabandan hızla yükselip incelen, sarıdan koyu kırmızıya dönen parçacıklar.
	var flames := _emitter(node, 16, 0.65, Vector2(0, -6), Vector2(10, 3), Vector2(0, -230), Vector2(30, 70),
		Vector2(0.6, 1.1), _ramp([Color(1.0, 0.82, 0.38, 0.85), Color(1.0, 0.55, 0.12, 0.8), Color(0.85, 0.22, 0.04, 0.5), Color(0.25, 0.04, 0.01, 0.0)], [0.0, 0.2, 0.55, 1.0]), true)
	flames.scale_amount_curve = _grow_curve(1.0, 0.15)
	flames.spread = 8.0
	var core := _emitter(node, 6, 0.4, Vector2(0, -5), Vector2(6, 2), Vector2(0, -150), Vector2(20, 40),
		Vector2(0.35, 0.6), _ramp([Color(1.0, 0.95, 0.7, 0.8), Color(1.0, 0.75, 0.3, 0.6), Color(1.0, 0.45, 0.1, 0.0)], [0.0, 0.4, 1.0]), true)
	core.scale_amount_curve = _grow_curve(1.0, 0.3)
	var embers := _emitter(node, 3, 1.5, Vector2(0, -20), Vector2(12, 6), Vector2(0, -40), Vector2(30, 80),
		Vector2(0.06, 0.12), _ramp([Color(1, 0.9, 0.5, 1), Color(1, 0.45, 0.1, 0.9), Color(0.6, 0.1, 0.0, 0.0)], [0.0, 0.6, 1.0]), true)
	embers.spread = 35.0
	# Alevler dumanın önünde çizilir (alttaki alevlerin dumanı üsttekileri boğmasın).
	for p in [flames, core, embers]:
		p.z_index = 1
	embers.angular_velocity_min = 0.0
	embers.angular_velocity_max = 0.0
	fires.append({"node": node, "pos": pos, "smoke": smoke, "flames": flames, "core": core, "embers": embers,
		"intensity": intensity, "out": false, "hit": false})
	_apply_intensity(fires[-1])


func _emitter(parent: Node2D, amount: int, lifetime: float, offset: Vector2, extents: Vector2, gravity: Vector2,
	speed: Vector2, particle_scale: Vector2, ramp: Gradient, additive: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = offset
	p.amount = amount
	p.lifetime = lifetime
	p.randomness = 0.5
	p.preprocess = lifetime
	p.texture = soft_tex
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = extents
	p.direction = Vector2(0, -1)
	p.spread = 12.0
	p.gravity = gravity
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	p.scale_amount_min = particle_scale.x
	p.scale_amount_max = particle_scale.y
	p.color_ramp = ramp
	p.local_coords = false
	if additive:
		p.material = add_material
	# Performans: alev parçacıkları ayrı ışık katmanında (2); fenerin ışığı onları yeniden çizmez,
	# yalnız yangının kendi ışıkları etkiler.
	p.light_mask = 2
	parent.add_child(p)
	return p


func _ramp(colors: Array, offsets: Array) -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	return g


func _grow_curve(start: float, finish: float) -> Curve:
	var c := Curve.new()
	c.max_value = maxf(2.0, maxf(start, finish))
	c.add_point(Vector2(0, start))
	c.add_point(Vector2(1, finish))
	return c


func _apply_intensity(f: Dictionary) -> void:
	var k: float = f.intensity
	f.node.scale = Vector2.ONE * (0.35 + 0.65 * k)
	f.flames.modulate.a = clampf(0.3 + k, 0.0, 1.0)
	f.core.modulate.a = clampf(k * 1.3, 0.0, 1.0)


func burning_count() -> int:
	var n := 0
	for f in fires:
		if not f.out and f.get("lit", true):
			n += 1
	return n


func _burning_near(pos: Vector2, radius: float) -> bool:
	for f in fires:
		if f.get("lit", true) and not f.out and f.pos.distance_to(pos) < radius:
			return true
	return false


# Henüz tutuşmamış alevi iptal eder (görünmez, sayılmaz).
func _cancel(f: Dictionary) -> void:
	f.lit = true
	f.out = true
	f.intensity = 0.0


func _pending() -> bool:
	for f in fires:
		if not f.get("lit", true):
			return true
	return false


func nearest_burning(from: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for f in fires:
		if not f.out and f.get("lit", true) and f.pos.distance_squared_to(from) < best_d:
			best_d = f.pos.distance_squared_to(from)
			best = f.pos
	return best


# Püskürtme konisi içindeki alevleri söndürür; isabet varsa true döner.
func spray(origin: Vector2, dir: Vector2, delta: float) -> bool:
	var hit_any := false
	for f in fires:
		if f.out or not f.get("lit", true):
			continue
		var v: Vector2 = f.pos + Vector2(0, -12) - origin
		var d := v.length()
		if d > SPRAY_RANGE or absf(dir.angle_to(v)) > SPRAY_HALF_ANGLE:
			continue
		f.hit = true
		hit_any = true
		f.intensity -= delta * (2.0 - d / SPRAY_RANGE * 0.8)
		if f.intensity <= 0.0:
			_extinguish(f)
		else:
			_apply_intensity(f)
	return hit_any


func _extinguish(f: Dictionary) -> void:
	f.out = true
	f.intensity = 0.0
	for key in ["flames", "core", "embers"]:
		f[key].emitting = false
	# Sönen alevden beyaz buhar yükselir, sonra kesilir.
	var steam: CPUParticles2D = f.smoke
	steam.color_ramp = _ramp([Color(0.9, 0.9, 0.92, 0.0), Color(0.85, 0.86, 0.9, 0.5), Color(0.8, 0.8, 0.85, 0.0)], [0.0, 0.2, 1.0])
	steam.amount = 16
	get_tree().create_timer(1.8).timeout.connect(func() -> void:
		if is_instance_valid(steam):
			steam.emitting = false)
	if burning_count() == 0:
		# Hepsi söndü: yanan komşusu kalmayan (zorunlu olmayan) bekleyen alevler de iptal.
		for other in fires:
			if not other.get("lit", true) and not other.get("force", false):
				_cancel(other)
	if burning_count() == 0 and not _pending():
		active = false
		roar.stop()
		for light in lights:
			create_tween().tween_property(light, "energy", 0.0, 1.2)
		all_out.emit()


func _process(delta: float) -> void:
	var here: bool = game.current_room == ROOM
	if here != visible:
		visible = here
		# Başka odadayken parçacık simülasyonu tamamen durur (performans).
		for f in fires:
			f.node.process_mode = Node.PROCESS_MODE_INHERIT if here else Node.PROCESS_MODE_DISABLED
	for light in lights:
		light.enabled = visible
	if not active:
		roar.stop()
		return
	var t := Time.get_ticks_msec() / 1000.0
	age += delta
	for f in fires:
		if not f.get("lit", true):
			if age < f.delay:
				continue
			if not f.get("force", false) and not _burning_near(f.pos, 80.0):
				# Yayılma yalnız yanan alevden olur: çevresi söndürüldüyse bu alev hiç tutuşmaz.
				if burning_count() == 0:
					_cancel(f)
				continue
			# Tutuşma: küçük bir alevle başlar.
			f.lit = true
			f.intensity = 0.08
			f.node.visible = true
			for key in ["smoke", "flames", "core", "embers"]:
				f[key].emitting = true
			_apply_intensity(f)
		if not f.out:
			if not f.hit:
				var rate: float = KINDLE_GROW if f.intensity < f.get("max", 1.0) * 0.9 else REGROW
				f.intensity = minf(1.0, f.intensity + delta * rate)
				_apply_intensity(f)
			f.hit = false
	for i in lights.size():
		var sum := 0.0
		var n := 0
		for j in range(light_ranges[i].x, light_ranges[i].y):
			sum += fires[j].intensity
			n += 1
		var flicker := 0.85 + 0.1 * sin(t * 13.0 + i * 1.7) + 0.08 * sin(t * 29.0 + i * 3.1) + randf_range(-0.05, 0.05)
		lights[i].energy = 2.1 * (sum / maxf(n, 1)) * flicker
	# Uğultu: yangına yakınlık ve kalan alev sayısıyla yükselir.
	var player: Node2D = game.player
	var d := player.global_position.distance_to(nearest_burning(player.global_position))
	var near := clampf(1.0 - d / 700.0, 0.0, 1.0) * clampf(float(burning_count()) / 8.0, 0.3, 1.0)
	roar.volume_db = lerpf(-40.0, -4.0, near) if game.current_room == ROOM or near > 0.5 else -40.0
	if not roar.playing:
		roar.play()


func _physics_process(delta: float) -> void:
	if not active or game.finished or game.current_room != ROOM:
		return
	# Aleve basan oyuncu tutuşur (yanma, çığlık ve hasar hikâye denetçisinde).
	var player: Node2D = game.player
	for f in fires:
		if not f.out and f.get("lit", true) and f.intensity > 0.3 and player.global_position.distance_to(f.pos) < 18.0 + 12.0 * f.intensity:
			game.story.touch_fire()
			return


func _soft_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	return tex


func _build_roar() -> AudioStreamWAV:
	# Yangın uğultusu: alçak geçiren gürültü + rastgele çatırtılar (2 sn döngü).
	var count := MIX_RATE * 2
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var low := 0.0
	var crack := 0.0
	for i in count:
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.03
		if rng.randf() < 0.0012:
			crack = rng.randf_range(0.3, 0.8)
		crack *= 0.985
		var s := low * 2.2 + rng.randf_range(-1.0, 1.0) * crack
		# Döngü başı/sonu yumuşak birleşsin.
		var edge := minf(1.0, minf(float(i), float(count - i)) / 800.0)
		data.encode_s16(i * 2, int(clampf(s * edge, -1.0, 1.0) * 26000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	return stream
