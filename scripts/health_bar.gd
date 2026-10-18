extends Control

# Can göstergesi (sayı yerine): piksel kalp + 10 bölmeli çubuk. Hasar alınca bölmeler beyaz parlar,
# can azalınca kalp nabız gibi atar.

const SEGMENTS := 10
const HEART := [
	".##.##.",
	"#######",
	"#######",
	".#####.",
	"..###..",
	"...#...",
]

var player: Node2D
var shown := 100.0
var flash := 0.0
var time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(8, 72)
	size = Vector2(320, 34)
	shown = float(player.health)
	player.health_changed.connect(_on_health_changed)


func _on_health_changed(value: int) -> void:
	shown = float(value)
	flash = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	time += delta
	flash = maxf(0.0, flash - delta * 2.5)
	shown = float(player.health)
	queue_redraw()


func _draw() -> void:
	var ratio := float(player.health) / float(player.max_health)
	var beat := 1.0 + (0.12 * maxf(0.0, sin(time * (6.0 if ratio < 0.35 else 2.0))) if ratio < 0.6 else 0.0)
	var px := 3.0 * beat
	var heart_origin := Vector2(4, 16) - Vector2(3.5, 3.0) * px
	for y in HEART.size():
		for x in HEART[y].length():
			if HEART[y][x] == "#":
				var col := Color("e0383f") if not (x == 1 and y == 1) else Color("ff9a9e")
				draw_rect(Rect2(heart_origin + Vector2(x, y) * px + Vector2(10, 0), Vector2(px, px)), col)
	var bar := Rect2(Vector2(44, 6), Vector2(240, 20))
	draw_rect(bar.grow(3), Color(0, 0, 0, 0.55))
	var seg_w := bar.size.x / SEGMENTS
	var lit: float = shown / float(player.max_health) * SEGMENTS
	for i in SEGMENTS:
		var r := Rect2(bar.position + Vector2(i * seg_w + 1, 1), Vector2(seg_w - 2, bar.size.y - 2))
		draw_rect(r, Color(0.22, 0.08, 0.08))
		var fill := clampf(lit - i, 0.0, 1.0)
		if fill > 0.0:
			var c := Color("d6343b").lerp(Color("ff7a5c"), 0.25 * sin(time * 2.0 + i * 0.5) + 0.25)
			if ratio < 0.35:
				c = c.lerp(Color.WHITE, 0.15 * (0.5 + 0.5 * sin(time * 8.0)))
			draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), c.lerp(Color.WHITE, flash * 0.7))
			draw_rect(Rect2(r.position, Vector2(r.size.x * fill, 3)), Color(1, 1, 1, 0.25))
