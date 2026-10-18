extends Camera2D

# Fragman kamerası: oyunun kendi kamerasından bağımsızdır. Konum ve yakınlık Tween ile yumuşak
# değişir; hedefler sahnedeki gerçek düğümlerdir. Oda dışı boşluk görünmesin diye konum, odanın
# kadrajına (main._room_frame) sıkıştırılır. Yakınlık odanın "cover" yakınlığına göre çarpandır.

var game: Node2D
var focus := Vector2.ZERO
var zoom_mult := 1.0
var follow_target: Node2D
var follow_offset := Vector2.ZERO
var shake_strength := 0.0
var shake_left := 0.0
var shake_total := 1.0
var noise := FastNoiseLite.new()
var t := 0.0
var move_tween: Tween
var zoom_tween: Tween


func setup(g: Node2D) -> void:
	game = g
	noise.seed = 7
	noise.frequency = 1.0
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	position_smoothing_enabled = false
	ignore_rotation = true
	focus = game.player.global_position


func _cover_zoom() -> float:
	var frame: Rect2 = game._room_frame(game.current_room)
	var view := get_viewport_rect().size
	return maxf(view.x / frame.size.x, view.y / frame.size.y)


# Odaya kesme: odayı etkinleştirir (yalnız o oda çizilir) ve kamerayı hedefe anında koyar.
func cut_to(room: StringName, target, mult := 1.0) -> void:
	if game.current_room != room:
		game._enter_room(room)
	_kill_tweens()
	follow_target = null
	focus = _point(target)
	zoom_mult = mult
	_apply()


func focus_on_target(target, mult := -1.0, seconds := 1.5, trans := Tween.TRANS_SINE) -> void:
	move_to(_point(target), seconds, trans)
	if mult > 0.0:
		zoom_to(mult, seconds, trans)


func move_to(pos: Vector2, seconds := 1.5, trans := Tween.TRANS_SINE) -> void:
	follow_target = null
	if move_tween != null and move_tween.is_valid():
		move_tween.kill()
	move_tween = create_tween()
	move_tween.tween_property(self, "focus", pos, seconds).set_trans(trans).set_ease(Tween.EASE_IN_OUT)


func zoom_to(mult: float, seconds := 1.5, trans := Tween.TRANS_SINE) -> void:
	if zoom_tween != null and zoom_tween.is_valid():
		zoom_tween.kill()
	zoom_tween = create_tween()
	zoom_tween.tween_property(self, "zoom_mult", mult, seconds).set_trans(trans).set_ease(Tween.EASE_IN_OUT)


func follow(node: Node2D, offset := Vector2(0, -40)) -> void:
	if move_tween != null and move_tween.is_valid():
		move_tween.kill()
	follow_target = node
	follow_offset = offset


# Kontrollü sarsıntı: piksel cinsinden genlik, yumuşak sönümlü.
func shake(strength: float, seconds: float) -> void:
	shake_strength = strength
	shake_left = seconds
	shake_total = maxf(seconds, 0.01)


func reset_camera() -> void:
	_kill_tweens()
	follow_target = null
	shake_left = 0.0
	zoom_mult = 1.0
	focus = game.player.global_position
	_apply()


func _kill_tweens() -> void:
	for tw in [move_tween, zoom_tween]:
		if tw != null and tw.is_valid():
			tw.kill()


func _point(target) -> Vector2:
	if target is Node2D:
		return target.global_position + Vector2(0, -40)
	return target


func _process(delta: float) -> void:
	t += delta
	if follow_target != null and is_instance_valid(follow_target):
		focus = follow_target.global_position + follow_offset
	shake_left = maxf(0.0, shake_left - delta)
	_apply()
	# Oyunun kendi kamerası oda değişiminde öne geçer; fragman kamerası her karede geri alır.
	if not is_current() and game.is_visible_in_tree():
		make_current()


func _apply() -> void:
	var z := _cover_zoom() * zoom_mult
	zoom = Vector2.ONE * z
	var frame: Rect2 = game._room_frame(game.current_room)
	var half := get_viewport_rect().size / (2.0 * z)
	var p := focus
	p.x = clampf(p.x, frame.position.x + half.x, maxf(frame.position.x + half.x, frame.end.x - half.x))
	p.y = clampf(p.y, frame.position.y + half.y, maxf(frame.position.y + half.y, frame.end.y - half.y))
	var off := Vector2.ZERO
	if shake_left > 0.0:
		var env := shake_left / shake_total
		off = Vector2(noise.get_noise_2d(t * 18.0, 0.0), noise.get_noise_2d(0.0, t * 18.0) * 0.7) * shake_strength * env * 1.8
	global_position = p + off / z
