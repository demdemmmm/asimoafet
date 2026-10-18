extends Node2D

signal leak_fixed
signal item_collected(kind: String)

var game: Node2D
var inventory: Dictionary = {}
# Envanter: 5 yuva. Çanta varken erzak (yiyecek, su, düdük, sargı bezi) çantaya girer, yuva harcamaz;
# kedi omuzda taşınır. Yalnız elde (equipped) olan alet kullanılır: fener ışık verir, matkap vidalar,
# yangın tüpü püskürtür.
signal equipment_changed
const SLOTS := 5
const BAG_KINDS := ["food", "water_bottle", "whistle", "bandage"]
const NO_SLOT := ["cat"]
const TOOLS := ["flashlight", "drill", "nails", "fire_extinguisher"]
const NAMES := {"flashlight": "Kafa lambası", "drill": "Matkap", "nails": "Vidalar", "fire_extinguisher": "Yangın tüpü",
	"quake_bag": "Deprem çantası", "food": "Konserve", "water_bottle": "Su", "whistle": "Düdük", "bandage": "Sargı bezi", "cat": "Osman"}
var slot_order: Array = []
var drop_count := 0
var equipped := ""
var inventory_ui: CanvasLayer
var electrical_fault := true
# Kaçak kalıcı onarıldı mı (elektriğin açık/kapalı olmasından bağımsız).
var leak_repaired := false
var shelter: Area2D
var panel_item: Area2D
# Elektriği tesisat panelinin şalteriyle biz kestik mi (onarım bitince geri kaldırılır).
var panel_cut_power := false
var inventory_label: Label
var overlay: Control
var panel: Control

# Yerleşim oda-yerel koordinattır (oda sol üst köşesi = 0,0); değer eşyanın taban noktasıdır.
# Yeni eşya eklemek için ilgili odaya satır eklemek yeterlidir; diğer eşyalar yerinde kalır.
# Mutfak köşesi salonun sol üstünde; giriş ve oda kapıları açık tutulur.
const SALON_TV_X := 470.0
# Oturma grubu TV'ye yakın: sehpa tabanı (oda-yerel y); koltuklar buna göre dizilir.
const SALON_TABLE_Y := 155.0
const WARDROBE_WALL_Y := 46.0
const PHONE_TABLE := Vector2(215, 330)
const LAYOUT := {
	&"salon": [
		# Salon (655 x 491, oda-yerel). Bölgeler: A TV/eğlence (üst-sağ), B oturma (TV ekseni),
		# C giriş/geçiş (kapı x 292-364 sütunu ve yan kapılar y 174-318 bandı), D depolama (üst-sol duvar).
		# Konumlar SALON_TV_X / oturma ölçülerinden türetilir; tek kaynak budur.
		# Dolaplar arka duvara yaslı (taban y 46: görünen alt kenar duvar çizgisinin 34 px önünde).
		["wardrobe", Vector2(55, WARDROBE_WALL_Y)],
		# Telefon masası: sol alt köşe, kapı sütununun (x 292-364) solunda. Masa siper değil; E telefona gider.
		["table", PHONE_TABLE, {"interaction_enabled": false}],
		["chair", PHONE_TABLE + Vector2(-70, -6)], ["chair", PHONE_TABLE + Vector2(70, -6)],
		["phone", PHONE_TABLE + Vector2(0, 1), {"draw_offset": Vector2(0, -50)}],
		# Matkap ve vidalar telefon masasında, telefonun iki yanında (dolap sabitleme için ikisi de gerekir).
		["drill", PHONE_TABLE + Vector2(-32, 1), {"draw_offset": Vector2(0, -50), "size": Vector2(24, 16)}],
		["nails", PHONE_TABLE + Vector2(32, 1), {"draw_offset": Vector2(0, -50), "size": Vector2(16, 12), "caption": "Vidalar", "amount": 2}],
		["tv_unit", Vector2(SALON_TV_X, 80)],
		["tv", Vector2(SALON_TV_X, 81), {"draw_offset": Vector2(0, -44)}],
		["floor_lamp", Vector2(SALON_TV_X + 88, 80)],
		# Şebeke (sigorta) kutusu salonda, TV'nin sağında duvarda: kaçak buradan giderilir.
		# Sigorta kutusu duvarda asılı (taban duvar çizgisinde, görsel duvar yüzüne kaydırılır).
		["electrical_box", Vector2(616, 4), {"caption": "Sigorta kutusu", "draw_offset": Vector2(0, -30)}],
		# Ev süsleri: tablo, aile fotoğrafları, duvar saati, kitaplık, büyük bitki, yan sehpa, vazo.
		["decor", Vector2(420, 2), {"style": "photo_wide", "draw_offset": Vector2(0, -38)}],
		["decor", Vector2(327.6, 1), {"style": "clock", "draw_offset": Vector2(0, -118)}],
		# Kitaplık pencere (x 112-208) ile kapı (x 292-364) arasındaki duvar boşluğunda.
		["bookshelf", Vector2(250, WARDROBE_WALL_Y)],
		["decor", Vector2(618, 340), {"style": "plant_salon", "size": Vector2(28, 20), "solid": true}],
		# Pencere önlerinde kırmızı sardunyalar (pencere alt kenarına oturur).
		["decor", Vector2(160, 2), {"style": "sill_geranium", "draw_offset": Vector2(0, -64)}],
		["decor", Vector2(512.2, 2), {"style": "sill_geranium", "draw_offset": Vector2(0, -64)}],
		# Lambalı yan sehpa pencerenin altında (dolap ile kitaplık arası); banyo kapısının önünü kapatmaz.
		["decor", Vector2(160, 64), {"style": "round_table", "size": Vector2(40, 60), "solid": true, "emits_light": true, "lamp_radius_scale": 0.75}],
		["coffee_table", Vector2(SALON_TV_X, SALON_TABLE_Y)],
		# Sehpanın üstünde çiçekli vazo.
		["decor", Vector2(SALON_TV_X, SALON_TABLE_Y + 1), {"style": "vase", "draw_offset": Vector2(0, -24), "size": Vector2(24, 30), "caption": "Vazo"}],
		# Doluluk (etkileşimsiz, katı olmayan süsler; kapı ve etkileşim noktalarının önünde değil).
		["decor", Vector2(197, 60), {"style": "books_stack", "size": Vector2(26, 20)}],
		["decor", Vector2(392, 52), {"style": "shoe_rack", "size": Vector2(44, 22)}],
		["decor", Vector2(36, 344), {"style": "cat_bowl", "size": Vector2(34, 12)}],
		# Manzara tablosu sol pencere ile kapı arasında, kitaplığın üstündeki boş duvarda (pencereye binmez).
		["decor", Vector2(250, 2), {"style": "painting", "draw_offset": Vector2(0, -80), "size": Vector2(44, 34)}],
		# Çiftli koltuk TV ekseninde, sehpanın hemen önünde (görünen üst kenar y-86, sehpadan 14 px).
		["sofa", Vector2(SALON_TV_X, SALON_TABLE_Y + 100)],
		# Tekli koltuk ayrı durur: sehpanın solunda, TV'ye çapraz bakan L düzeni.
		# Çiftli koltuğun görünen sol kenarı (x-49) − 18 px boşluk − yarı genişlik (31).
		["armchair", Vector2(SALON_TV_X - 98, SALON_TABLE_Y + 58)]],
	&"yatak_odasi": [
		# Yatak sol üst köşede, kedi üstünde. Yatağın yanındaki dolap (trap) kediyi alırken
		# sarsıntıda başına yıkılır — matkap+vidayla sabitlenmedikçe. Deprem çantası sol dolabın üstünde.
		["bed", Vector2(64, 150)], ["cat", Vector2(70, 152), {"caption": "Osman"}],
		["wardrobe", Vector2(172, WARDROBE_WALL_Y), {"trap": true, "holds_bag": true}],
		# Komodin ve başucu lambası yatağın ayak ucunda (yatağa ve kediye giden yol açık kalır).
		["nightstand", Vector2(64, 192)], ["bedside_lamp", Vector2(64, 193), {"lamp_energy": 0.5}],
		["wardrobe", Vector2(470, WARDROBE_WALL_Y)],
		["decor", Vector2(64, 2), {"style": "photo_wide", "draw_offset": Vector2(0, -52)}],
		["decor", Vector2(40, 312), {"style": "plant_bedroom", "size": Vector2(22, 18), "solid": true}],
		["decor", Vector2(390, 2), {"style": "painting", "draw_offset": Vector2(0, -98), "size": Vector2(40, 30)}],
		["decor", Vector2(40, 236), {"style": "slippers", "size": Vector2(30, 14)}],
		# Gitar sol alttaki saksı bitkisine yaslı: tabanı saksının sağında, sapı yapraklara eğik.
		["decor", Vector2(72, 316), {"style": "guitar", "size": Vector2(26, 60), "sprite_rotation": -0.32}],
		["decor", Vector2(220, 318), {"style": "books_stack", "size": Vector2(26, 20)}],
		["fire_extinguisher", Vector2(536, 72)],
		["heater", Vector2(370, 300), {"emits_light": true, "lamp_color": Color(1.0, 0.58, 0.28), "lamp_radius_scale": 0.42, "lamp_energy": 0.75}]],
	&"banyo": [
		# Banyo (480 x 420). Arka duvar: lavabo + üstünde ayna (patlayan boru suyu buradan kapıya yayılır),
		# havluluk ve ilk yardım dolabı duvarda, klozet, köşede saksı. Lavabonun solundaki gevşek priz
		# depremde duvardan kopar, kabloları suya sarkar → su elektrikli (kaçak onarıldıysa priz yerinde kalır).
		["sink", Vector2(150, 22), {"search_spot": "lavabo altı", "emits_light": true, "lamp_energy": 0.25, "lamp_radius_scale": 0.8, "lamp_color": Color(0.76, 0.88, 1.0)}],
		["mirror", Vector2(150, 23), {"draw_offset": Vector2(0, -58)}],
		["towels", Vector2(226, 4), {"draw_offset": Vector2(0, -6)}],
		["bandage", Vector2(95, 30), {"draw_offset": Vector2(0, -58)}],
		["toilet", Vector2(255, 46), {"search_spot": "rezervuar"}],
		["decor", Vector2(40, 320), {"style": "plant_bath", "size": Vector2(18, 16), "solid": true}],
		["puddle", Vector2(92, 205), {"pool_extent": Vector2(84, 200), "source_offset": Vector2(56, -179), "interaction_enabled": false, "show_behind_parent": true}],
		# Çekmeceli dolap sağ arka köşede, duvarlara bitişik (arkasında karakterin sıkışacağı boşluk yok).
		["bathroom_cabinet", Vector2(349, 30), {"search_spot": "çekmece"}],
		# Fener dolabın üstünde, açıkça görünür; karanlıkta parıldar.
		["flashlight", Vector2(349, 31), {"draw_offset": Vector2(0, -46)}],
		# Küvet sağ alt köşede (perdesiz).
		["shower", Vector2(318, 330)],
		["basket", Vector2(140, 328), {"interaction_enabled": true, "search_spot": "çamaşır sepeti"}],
		["decor", Vector2(32, 70), {"style": "trash_bin", "size": Vector2(22, 26)}],
		["decor", Vector2(212, 56), {"style": "toilet_paper", "size": Vector2(14, 30)}],
		["decor", Vector2(220, 300), {"style": "scale", "size": Vector2(30, 14)}],
		["decor", Vector2(318, 262), {"style": "bath_mat", "size": Vector2(70, 22)}]],
	# Mutfak (655 x 300, salonun altında). Arka duvar: tezgâh, ocak, eviye, buzdolabı; ortada yemek
	# masası. Konserve ve su tezgâhta, düdük buzdolabının üstünde (deprem çantası için).
	&"mutfak": [
		# Tezgâh sırası sol duvardan başlar ve aralıksız uzanır (iç kenar 12): tezgâh 12-132, ocak 132-196,
		# eviye 196-276, tezgâh 276-380. Kapı açıklığı 380-476 tamamen boş; buzdolabı sağ duvara yaslı (478-528).
		["counter", Vector2(72, 66)], ["stove", Vector2(164, 66)], ["kitchen_sink", Vector2(236, 66)],
		["counter", Vector2(328, 66), {"size": Vector2(104, 62)}],
		["fridge", Vector2(503, 72), {"anchorable": false}],
		["food", Vector2(84, 67), {"draw_offset": Vector2(0, -52)}],
		["water_bottle", Vector2(340, 67), {"draw_offset": Vector2(0, -52)}],
		["whistle", Vector2(503, 73), {"draw_offset": Vector2(0, -104)}],
		["table", Vector2(260, 186), {"interaction_enabled": false}],
		["decor", Vector2(260, 187), {"style": "fruit_bowl", "draw_offset": Vector2(0, -50)}],
		["chair", Vector2(200, 178)], ["chair", Vector2(320, 178)],
		["decor", Vector2(170, 2), {"style": "shelf", "draw_offset": Vector2(0, -78)}],
		["decor", Vector2(330, 2), {"style": "clock", "draw_offset": Vector2(0, -84)}],
		# Atatürk portresi: raf ile saat arasındaki boş duvarda.
		["decor", Vector2(258, 2), {"style": "ataturk", "draw_offset": Vector2(0, -78), "size": Vector2(40, 52), "caption": "Atatürk portresi"}],
		["decor", Vector2(452, 2), {"style": "calendar", "draw_offset": Vector2(0, -86)}],
		["decor", Vector2(500, 236), {"style": "plant_kitchen", "size": Vector2(28, 20), "solid": true}],
		# Tezgâhta fesleğen (eviye ile su şişesi arası).
		["decor", Vector2(300, 67), {"style": "herb_basil", "draw_offset": Vector2(0, -52)}],
		["decor", Vector2(32, 236), {"style": "trash_bin", "size": Vector2(22, 26)}],
		["decor", Vector2(80, 2), {"style": "spice_rack", "draw_offset": Vector2(0, -92), "size": Vector2(46, 18)}],
		["decor", Vector2(420, 236), {"style": "cat_bowl", "size": Vector2(34, 12)}]]
}

# Senaryo olaylarının sabit konumları (oda-yerel). Döngüler arasında değişmez;
# yeni olaylar buraya yeni anahtar eklenerek tanımlanır.
const EVENT_POINTS := {
	&"salon": {
		&"entry_spawn": Vector2(327.6, 117), &"phone_call": PHONE_TABLE,
		&"brick_fall": Vector2(327.6, 273), &"front_door": Vector2(327.6, 0),
		&"tv": Vector2(SALON_TV_X, 80), &"night_lamp": Vector2(SALON_TV_X + 88, 80),
		&"tools": Vector2(205, 72), &"gas_valve": Vector2(40, 330)},
	&"yatak_odasi": {
		&"cat_on_bed": Vector2(64, 105), &"door_fire": Vector2(500, 240),
		&"fire_source": Vector2(370, 300), &"extinguisher": Vector2(536, 72)},
	&"banyo": {
		&"toilet_door": Vector2(255, 120), &"door_cable": Vector2(62, 168),
		&"burst_pipe": Vector2(150, 70), &"puddle": Vector2(92, 205),
		&"fuse_box": Vector2(34, 150),
		&"flashlight": Vector2(349, 237)}
}

const EVENT_ZONES := {
	&"salon": {
		&"tutorial": Rect2(244.4, 39, 166.4, 195),
		&"bathroom_approach": Rect2(473.2, 152.1, 166.4, 187.2)},
	&"yatak_odasi": {
		&"wardrobe_fall": Rect2(120, 16, 206, 154),
		&"door_fire": Rect2(420, 168, 118, 144)},
	&"banyo": {
		&"electrified_water": Rect2(50, 105, 84, 200),
		&"toilet_cubicle": Rect2(220, 12, 70, 130)}
}

func get_event_point(room_id: StringName, id: StringName) -> Vector2:
	return game.ROOMS[room_id].position + EVENT_POINTS[room_id][id]

func get_event_zone(room_id: StringName, id: StringName) -> Rect2:
	var zone: Rect2 = EVENT_ZONES[room_id][id]
	return Rect2(game.ROOMS[room_id].position + zone.position, zone.size)

func _ready() -> void:
	y_sort_enabled = true
	for room_id in LAYOUT:
		var bounds: Rect2 = game.ROOMS[room_id]
		for entry in LAYOUT[room_id]:
			var scene: PackedScene = load("res://scenes/" + entry[0] + ".tscn") as PackedScene
			if scene == null:
				push_error("Eşya sahnesi yüklenemedi: " + entry[0])
				continue
			var item := scene.instantiate() as Area2D
			if item == null:
				push_error("Geçersiz eşya sahnesi: " + entry[0])
				continue
			item.world = self
			item.room = room_id
			item.position = bounds.position + entry[1]
			if entry.size() > 2:
				for key in entry[2]:
					item.set(key, entry[2][key])
			add_child(item)
	game.earthquake_started.connect(_on_earthquake)
	game.player.health_changed.connect(_health_changed)
	_build_interface()
	_update_inventory()

func find_item(kind: String) -> Area2D:
	for item in get_children():
		if item is Area2D and item.kind == kind and not item.collected:
			return item
	return null

func set_room(id: StringName) -> void:
	for item in get_children():
		if item is Area2D:
			item.set_room_active(item.room == id)

func message(text: String) -> void:
	if not game.finished:
		game.status.text = text

func has_item(id: String, count: int = 1) -> bool:
	return count > 0 and int(inventory.get(id, 0)) >= count

func occupies_slot(id: String) -> bool:
	if id in NO_SLOT:
		return false
	return not (id in BAG_KINDS and has_item("quake_bag"))

func can_add(id: String) -> bool:
	if has_item(id) or not occupies_slot(id):
		return true
	return slot_order.size() < SLOTS

func _rebuild_slots() -> void:
	var kept := []
	for id in slot_order:
		if has_item(id) and occupies_slot(id):
			kept.append(id)
	for id in inventory:
		if occupies_slot(id) and not (id in kept):
			kept.append(id)
	slot_order = kept

func add_item(id: String, count: int = 1) -> void:
	if count <= 0:
		return
	inventory[id] = int(inventory.get(id, 0)) + count
	_rebuild_slots()
	# Alınan alet ele geçer (vidalar yalnız el boşsa).
	if id in TOOLS and (equipped == "" or id != "nails"):
		equip(id, true)
	_update_inventory()

func equip(id: String, quiet := false) -> void:
	if id != "" and not has_item(id):
		return
	equipped = "" if equipped == id else id
	if not quiet:
		message(("Elinde: " + NAMES.get(equipped, equipped)) if equipped != "" else "Elin boş.")
	equipment_changed.emit()
	_update_inventory()

func drop(id: String) -> void:
	if id == "quake_bag":
		message("Çantayı bırakamam, içinde erzak var!")
		return
	var count := int(inventory.get(id, 0))
	if count <= 0:
		return
	var item := spawn_item(id, game.player.global_position + game.player.facing * 24.0 + Vector2(0, 4))
	if item == null:
		message("Eşya yere bırakılamadı.")
		return
	item.amount = count
	inventory.erase(id)
	if equipped == id:
		equipped = ""
		equipment_changed.emit()
	_rebuild_slots()
	drop_count += 1
	message(NAMES.get(id, id) + " yere bırakıldı.")
	_update_inventory()

func spawn_item(kind: String, pos: Vector2) -> Area2D:
	# Güvenlik: sahne yolu yalnız bilinen, bırakılabilir eşya türlerinden kurulur.
	if not (kind in TOOLS or kind in BAG_KINDS):
		return null
	var path := "res://scenes/%s.tscn" % kind
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var item := scene.instantiate() as Area2D
	if item == null:
		return null
	item.world = self
	item.room = game.current_room
	item.position = pos
	add_child(item)
	item.set_room_active(true)
	return item

func consume(id: String, count: int = 1) -> bool:
	if count <= 0 or not has_item(id, count):
		return false
	inventory[id] -= count
	if inventory[id] <= 0:
		inventory.erase(id)
		if equipped == id:
			equipped = ""
			equipment_changed.emit()
	_rebuild_slots()
	_update_inventory()
	return true

func interact_with(item: Area2D, player: CharacterBody2D) -> void:
	if game.finished or panel.visible:
		return
	if item.kind == "cat":
		game.story.interact_osman(item)
		return
	if item.collectible:
		# Matkap ve vidalar ancak dolabın altında kalıp döngüye dönünce (dersini alınca) alınır.
		if not can_add(item.kind):
			message("Envanter dolu! [F] envanteri aç, [Q] ile bir şey bırak.")
			return
		add_item(item.kind, item.amount)
		message(item.caption + " toplandı.")
		item.collect()
		item_collected.emit(item.kind)
		return
	if item.search_spot != "" and game.story.search_active():
		game.story.search(item)
		return
	if game.story.try_anchor(item):
		return
	if item.open_texture_path != "":
		# Duvara gömülü dolaplar (anchorable = false) sabitlenmez ve devrilmez.
		if item.anchorable and Input.is_physical_key_pressed(KEY_SHIFT):
			_anchor_item(item)
		elif item.toggle_open():
			message(("Dolap açıldı." if item.opened else "Dolap kapandı.") + (" Shift+E: duvara sabitle." if item.anchorable else ""))
			if item.opened and item.holds_bag:
				game.story.found_bag(item)
		else:
			message("Devrilen dolap açılamaz.")
		return
	if item.anchorable:
		_anchor_item(item)
		return
	match item.kind:
		"phone":
			game.story.answer_phone()
		"fire_extinguisher":
			game.story.take_extinguisher(item)
		"electrical_box":
			if leak_repaired:
				# Onarımdan sonra kutu yalnız sigortayı açar/kapatır.
				set_power(game.electricity_off)
				message("Sigortayı açtın: elektrik geldi." if not game.electricity_off else "Sigortayı kapattın: elektrik kesildi.")
			else:
				open_minigame(item)
		"tv":
			if game.power_dead():
				message("TV kapalı: elektrik kesildi.")
			else:
				message("TV: Deprem uyarısı! Çök-kapan-tutun." if item.alarm_on else "Gece yayını... sıradan bir film.")
		"table", "coffee_table":
			shelter = null if shelter == item else item
			message("Çök-kapan-tutun: masadan uzaklaşma." if shelter != null else "Siperden çıktın.")
		"bed":
			message("Yatak: başını koru; camlardan ve sabitlenmemiş eşyalardan uzak dur.")
		"fire":
			message("Yangından uzak dur. Gaz vanasını kapat." if item.burning else "Yangın kaynağı şu an sönük.")
		"puddle":
			message("Su elektrik taşıyor! Tesisat kutusundan elektriği kes." if electrical_fault and not game.electricity_off else "Elektrik kesildi; su birikintisi güvenli.")
		"nightstand":
			message("Komodin boş.")
		"sofa":
			message("Koltuk sağlam; depremde masa yanında siper al.")
		"chair", "side_table", "kitchen_counter":
			message(item.caption + ": geçiş yolunu açık tut.")
		"shower":
			message("Duşakabin: camlardan uzak dur.")

func _anchor_item(item: Area2D) -> void:
	if item.anchored:
		message(item.caption + " duvara sabit.")
	elif item.fallen:
		message("Devrilen eşya bu döngüde sabitlenemez.")
	elif not (has_item("drill") or has_item("screwdriver")) or not has_item("nails"):
		message("Sabitlemek için matkap veya tornavida ve 1 çivi gerekir.")
	else:
		consume("nails")
		item.anchored = true
		item.queue_redraw()
		message(item.caption + " sabitlendi.")

func _on_earthquake() -> void:
	electrical_fault = not leak_repaired
	for item in get_children():
		if item is Area2D:
			item.on_earthquake()

func set_power(on: bool) -> void:
	game.electricity_off = not on
	if on:
		for item in get_children():
			if item is Area2D:
				if (item.kind == "floor_lamp" or item.emits_light) and not game.lights_out:
					item.set_light(true)
				item.queue_redraw()
	else:
		on_power_off()

func on_power_off() -> void:
	for item in get_children():
		if item is Area2D:
			if item.kind == "tv":
				item.set_alarm(false)
			elif item.kind == "floor_lamp" or item.emits_light:
				item.set_light(false)
			item.queue_redraw()

func on_gas_off() -> void:
	for item in get_children():
		if item is Area2D and item.kind == "fire":
			item.burning = false
			item.queue_redraw()

func is_sheltered() -> bool:
	return is_instance_valid(shelter) and shelter.room == game.current_room \
		and shelter.global_position.distance_to(game.player.global_position) <= 100.0

func _physics_process(_delta: float) -> void:
	if shelter != null and not is_sheltered():
		shelter = null
	if panel != null and panel.visible and (game.finished or not game.player.active):
		close_minigame()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("use_bandage") and not game.finished and not panel.visible:
		if game.player.health >= game.player.max_health:
			message("Canın dolu.")
		elif consume("bandage"):
			game.player.heal(40)
			message("Sargı bezi kullanıldı: +40 can.")
		else:
			message("Sargı bezi yok.")
		get_viewport().set_input_as_handled()

func _build_interface() -> void:
	inventory_label = Label.new()
	inventory_label.name = "inventory"
	inventory_label.position = Vector2(32, 126)
	inventory_label.visible = false
	inventory_label.add_theme_font_size_override("font_size", 16)
	game.get_node("HUD").add_child(inventory_label)
	var health_bar := preload("res://scripts/health_bar.gd").new()
	health_bar.player = game.player
	game.get_node("HUD").add_child(health_bar)
	inventory_ui = preload("res://scripts/inventory_ui.gd").new()
	inventory_ui.world = self
	add_child(inventory_ui)
	var canvas := CanvasLayer.new()
	canvas.name = "electrical_minigame"
	canvas.layer = 30
	add_child(canvas)
	overlay = Control.new()
	canvas.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = preload("res://scenes/wiring_puzzle.tscn").instantiate()
	overlay.add_child(panel)
	panel.solved.connect(_on_wiring_solved)
	panel.cancelled.connect(close_minigame)
	panel.failed.connect(_on_wiring_failed)
	# Akım varken kabloya dokunma: can gitmez, yalnız kısa uyarı (cızırtı paneldedir).
	panel.shocked.connect(func(): message("Ah! Çarpıldım... Önce şalteri kapatmalıyım."))
	panel.breaker_pulled.connect(func():
		panel_cut_power = true
		set_power(false)
		message("Şalteri indirdin: elektrik kesildi. Şimdi kabloları bağla."))
	panel.hide()
	get_viewport().size_changed.connect(_layout_minigame)
	_layout_minigame()

func _layout_minigame() -> void:
	if panel == null:
		return
	var viewport_size := get_viewport_rect().size
	var factor := minf(1.45, minf((viewport_size.x - 40.0) / 800.0, (viewport_size.y - 40.0) / 480.0))
	factor = maxf(factor, 0.1)
	panel.scale = Vector2.ONE * factor
	panel.position = (viewport_size - Vector2(800, 480) * factor) * 0.5

func open_minigame(item: Area2D) -> void:
	if game.finished or not game.player.active:
		return
	panel_item = item
	if not game.electricity_off:
		panel_cut_power = false
	panel.live = not game.electricity_off
	panel.reset_puzzle()
	_layout_minigame()
	game.player.input_locked = true
	game.player.velocity = Vector2.ZERO
	panel.show()

func close_minigame() -> void:
	panel.cancel_drag()
	panel.hide()
	panel_item = null
	game.player.input_locked = false

func _on_wiring_solved() -> void:
	if game.finished or not game.player.active or not is_instance_valid(panel_item):
		close_minigame()
		return
	var repaired_box: Area2D = panel_item
	close_minigame()
	repaired_box.set_repaired(true)
	leak_repaired = true
	electrical_fault = false
	# Onarım bitti: şalteri bu panelde indirdiysek geri kaldırılır (deprem karartması varsa ışıklar yanmaz).
	if panel_cut_power and game.electricity_off:
		panel_cut_power = false
		set_power(true)
		message("Kablolar bağlandı, şalter geri kalktı. Kaçak giderildi; banyo güvenli.")
	else:
		message("Kablolar bağlandı. Kaçak giderildi; banyo güvenli.")
	leak_fixed.emit()

func _on_wiring_failed() -> void:
	# Akım varken yanlış uç: çarpılıp ölür, döngü başa döner.
	close_minigame()
	game.story.shock_death()

func _health_changed(_value: int) -> void:
	_update_inventory()

func _update_inventory() -> void:
	if inventory_label == null:
		return
	inventory_label.text = "Elde: %s   |   [F] Envanter (%d/%d)" % [
		NAMES.get(equipped, "—") if equipped != "" else "—", slot_order.size(), SLOTS]
