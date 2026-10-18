extends Camera2D

var remaining: float = 0.0
var duration: float = 1.0
var strength: float = 0.0
var base_offset: Vector2
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var noise_t := 0.0
# Sürekli hafif titreme (piksel); büyük sarsıntılar arasında da devam eder.
var tremor := 0.0
# Genel deprem sarsıntısı çarpanı (0.6 = kontrollü his); hikâye anlık olarak artırabilir.
var intensity := 0.3


func _ready() -> void:
	base_offset = offset
	rng.randomize()
	noise.seed = rng.randi()
	noise.frequency = 1.0


func shake(seconds: float = 8.0, pixels: float = 14.0) -> void:
	duration = maxf(seconds, 0.001)
	remaining = duration
	strength = maxf(pixels, 0.0)


func stop_shake() -> void:
	remaining = 0.0
	offset = base_offset


func _process(delta: float) -> void:
	noise_t += delta * 22.0
	# Mini oyun açıkken deprem hiç hissedilmez: sarsıntı iptal, kamera sabit.
	var story = get_parent().get("story")
	if story != null and story.minigame_active():
		remaining = 0.0
		offset = base_offset
		return
	var idle := Vector2(noise.get_noise_2d(noise_t, 50.0), noise.get_noise_2d(50.0, noise_t)) * tremor * 1.6 * intensity
	if remaining <= 0.0:
		offset = base_offset + idle
		return
	remaining = maxf(remaining - delta, 0.0)
	# Zarf: hızlı yükseliş, ortada tepe, yavaş sönüm; gürültü ani sıçramalar yerine yer sarsıntısı verir.
	var progress := 1.0 - remaining / duration
	var envelope := minf(progress / 0.12, 1.0) * pow(remaining / duration, 0.7)
	var amplitude := strength * envelope * intensity
	offset = base_offset + Vector2(
		noise.get_noise_2d(noise_t, 0.0),
		noise.get_noise_2d(0.0, noise_t) * 0.7
	) * amplitude * 1.6 + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * amplitude * 0.25 + idle
	if remaining == 0.0:
		offset = base_offset + idle
