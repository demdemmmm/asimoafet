extends RefCounted

# Fragman oyuncuları: oyuncu kontrolüne bağlı olmayan, yalnız görsel öğeler.
# Cat: Osman, oyunun gerçek sprite sayfasıyla (CatSprite) oturur/bakar/koşar.

const CatSprite = preload("res://scripts/cat_sprite.gd")


class Cat extends Node2D:
	var anim := "sit"
	var dir := CatSprite.DOWN
	var t := 0.0
	var draw_offset := Vector2(0, -20)
	var kind := "cat"
	var run_tween: Tween

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func run_to(pos: Vector2, seconds: float) -> void:
		anim = "run"
		dir = CatSprite.dir_of(pos - global_position)
		if run_tween != null and run_tween.is_valid():
			run_tween.kill()
		run_tween = create_tween()
		run_tween.tween_property(self, "global_position", pos, seconds)
		run_tween.tween_callback(func(): visible = false)

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.6, 0.45))
		draw_circle(Vector2.ZERO, 12, Color(0, 0, 0, 0.22))
		draw_set_transform(Vector2.ZERO)
		match anim:
			"run":
				CatSprite.draw(self, "run", dir, t, 13.0, Vector2.ZERO, 1.7)
			"look":
				CatSprite.draw(self, "look", dir, t, 5.0, Vector2.ZERO, 1.7)
			_:
				CatSprite.draw(self, "sit", dir, minf(t, 0.95), 6.0, Vector2.ZERO, 1.7)


# Televizyon paraziti: ekran alanının üstünde karlı görüntü ve kayan bant (dünya uzayında).
class TvNoise extends Node2D:
	var area := Rect2()
	var strength := 0.0
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		if strength <= 0.0:
			return
		var rng := RandomNumberGenerator.new()
		rng.seed = int(t * 30.0)
		var cell := 3.0
		var y := area.position.y
		while y < area.end.y:
			var x := area.position.x
			while x < area.end.x:
				var g := rng.randf()
				draw_rect(Rect2(x, y, cell, cell), Color(g, g, g, strength * 0.85))
				x += cell
			y += cell
		var band := area.position.y + fmod(t * 60.0, area.size.y)
		draw_rect(Rect2(area.position.x, band, area.size.x, 4), Color(1, 1, 1, strength * 0.5))
