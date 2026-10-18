extends "res://scripts/story.gd"

# Fragman için hikâye: oyunun bütün görsel/ses sistemleri (balonlar, yangın, fener, deprem tepkileri)
# aynen çalışır; yalnız oyuncuya bağlı akış (giriş sahnesi, telefon, faz sayacı) devre dışıdır.
# Olayları fragman yönetmeni zaman çizelgesinden tetikler.


func _intro() -> void:
	game.status.text = ""
	game.player.input_locked = true


func _update_phases(_delta: float) -> void:
	pass


# Fragmanda kesmeler odaları serbestçe değiştirir: ön kapı enkazı tetiklenmez.
func _block_front_door() -> void:
	front_blocked = true
