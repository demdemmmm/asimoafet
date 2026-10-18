extends Area2D

signal used(kind: int)

enum Kind { SWITCH, GAS, TV, EXIT }

@export var kind: Kind = Kind.TV
@export var caption: String = ""
var completed: bool = false
var nearby: bool = false


func _ready() -> void:
	add_to_group("interactables")
	# İpucu yazısı karakterin önünde çizilsin (kapı dibinde dururken üstü kapanmasın).
	z_index = 5
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	var shape := RectangleShape2D.new()
	shape.size = Vector2(120, 80)
	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	collider.shape = shape
	add_child(collider)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func setup(new_kind: Kind, new_caption: String, location: Vector2) -> void:
	kind = new_kind
	caption = new_caption
	position = location
	queue_redraw()


func interact(body: Node2D) -> void:
	if not body.is_in_group("player") or not overlaps_body(body):
		return
	if not body.get("active"):
		return
	if kind == Kind.SWITCH or kind == Kind.GAS:
		if completed:
			return
		completed = true
		queue_redraw()
	used.emit(kind)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		nearby = true
		queue_redraw()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		nearby = false
		queue_redraw()


func _draw() -> void:
	if kind == Kind.EXIT or kind == Kind.GAS:
		# Kapı duvarda çizilir; gaz vanası geçici kutusu yok: yalnız odaktayken ipucu.
		var player := get_tree().get_first_node_in_group("player")
		if player != null and player.get("focus") == self:
			var label := "[E] KAPI" if kind == Kind.EXIT else ("Gaz kapalı" if completed else "[E] Gaz vanası")
			# Yazı kapının hemen dibinde (kapı alt kenarı ~28 px yukarıda).
			draw_rect(Rect2(-46, -26, 92, 22), Color(0, 0, 0, 0.6))
			draw_string(ThemeDB.fallback_font, Vector2(-46, -9), label, HORIZONTAL_ALIGNMENT_CENTER, 92, 15, Color.WHITE)
		return
	var color := Color("#5ebc79") if completed else Color("#55bfd0")
	draw_rect(Rect2(-50, -20, 100, 40), color)
	if nearby:
		draw_rect(Rect2(-54, -24, 108, 48), Color("#f7cf68"), false, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(-60, 46), "TAMAM" if completed else "[E]", HORIZONTAL_ALIGNMENT_CENTER, 120, 16, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(-45, 6), caption, HORIZONTAL_ALIGNMENT_CENTER, 90, 18, Color("#12202d"))
