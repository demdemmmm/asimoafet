extends RefCounted

# Osman'ın sprite sayfası (32×32 kareler). Sütun blokları: oturma, etrafa bakma, yatma, yürüme,
# koşma, koşma 2 (her blok 4 kare genişliğinde). Satırlar: 8 yön × 2 satır (ilk satır 4 kare,
# devamı ikinci satırda). Yön sırası: aşağı, sol-aşağı, sol, sol-yukarı, yukarı, sağ-yukarı, sağ, sağ-aşağı.
const SHEET := "res://assets/cat/osman_sheet.png"
const ANIMS := {"sit": [0, 6], "look": [1, 5], "lay": [2, 8], "walk": [3, 4], "run": [4, 5], "run2": [5, 8]}
const DOWN := 0
const LEFT := 2
const UP := 4
const RIGHT := 6

static var _tex: Texture2D


static func texture() -> Texture2D:
	if _tex == null:
		_tex = load(SHEET)
	return _tex


# Hareket vektöründen 8 yönlü satır indeksi.
static func dir_of(v: Vector2) -> int:
	if v.length() < 0.001:
		return DOWN
	var k := posmod(int(round(v.angle() / (PI * 0.25))), 8)
	return [6, 7, 0, 1, 2, 3, 4, 5][k]


static func region(anim: String, dir: int, frame: int) -> Rect2:
	var a: Array = ANIMS[anim]
	var i: int = posmod(frame, a[1])
	return Rect2(a[0] * 128 + (i % 4) * 32, 32 + (dir * 2 + i / 4) * 32, 32, 32)


# feet: kedinin yere bastığı nokta; kare tabanı biraz altta kalır.
static func draw(ci: CanvasItem, anim: String, dir: int, t: float, fps: float, feet: Vector2, scale: float, mod := Color.WHITE) -> void:
	var tex := texture()
	if tex == null:
		return
	var size := 32.0 * scale
	ci.draw_texture_rect_region(tex, Rect2(feet - Vector2(size * 0.5, size * 0.94), Vector2(size, size)),
		region(anim, dir, int(t * fps)), mod)
