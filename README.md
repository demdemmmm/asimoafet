# One More Time

**Aynı gece. Aynı felaket. Farklı kararlar.**

One More Time (Asimo Afet), deprem temalı, zaman döngüsüne ve oyuncunun seçimlerine dayanan, çok sonlu bir 2D hikâye oyunudur. Her döngüde geçmişte yaşadıklarını hatırlayan bir adam, sevdiklerini kurtarmaya çalışır. Kimi kurtaracağın ve ne kadar hazırlıklı olduğun hikâyenin sonucunu değiştirir.

Bu repo oyunun Godot kaynak kodlarını, sahnelerini, görsel ve ses kaynaklarını, fragman araçlarını ve oynanabilir Windows paketini içerir.

## Windows'ta oynamak

1. Repoyu **GitHub Desktop ile klonla** ve indirme işleminin tamamlanmasını bekle.
2. Klonlanan reponun `Windows` klasörünü aç.
3. `AsimoAfet.exe` dosyasını çalıştır. `AsimoAfet.pck` dosyası aynı klasörde kalmalıdır.
4. Başlangıç ekranında **PLAY** düğmesine tıkla veya **Enter** tuşuna bas.

Hazır oyun paketi **Windows x64** içindir; oynamak için Godot kurmak gerekmez. Ayrıntılar ve indirme sorunlarının çözümü: [Windows kullanım rehberi](Windows/README.md).

## Godot'ta geliştirmek

Geliştirme ve açılış kontrollerinde **Godot 4.6.2** kullanıldı.

1. Repoyu klonla.
2. Godot Project Manager'da **Import / İçe Aktar** ile kökteki `project.godot` dosyasını seç.
3. Kaynakların içe aktarılmasını bekle ve **F5** ile projeyi başlat. Ana sahne `main.tscn` dosyasıdır.

Kaynak projeyi düzenlemek için `Windows` paketini açman gerekmez. Mac ve Windows dışa aktarma ayarları `export_presets.cfg` içindedir; çalıştırılabilir paket üretmek için kullandığın Godot sürümüyle eşleşen export templates gerekir.

## Kontroller

| İşlem | Kontrol |
| --- | --- |
| Hareket | WASD veya ok tuşları |
| Koşma | Hareket ederken sol Shift |
| Çömelme | C'yi basılı tut; öğreticide C'ye tek basış yeterlidir |
| Yakındaki nesneyle etkileşim | E veya sol tık |
| Envanteri açma/kapatma | F; fareyle açmak için sol üstteki `[F]` etiketi |
| Envanterde eşya seçme | Sol/sağ ok veya A/D; fareyle yuvaya tıkla |
| Eşyayı ele alma/elinden bırakma | Açık envanterde E / Enter / sol tık; ayrıca 1–5 veya hızlı eşya yuvaları |
| Eşyayı yere bırakma | Açık envanterde Q veya yuvaya sağ tık |
| Bandaj kullanma | B, bandajın varsa ve canın eksikse |
| Envanteri kapatma | F / Esc, KAPAT düğmesi veya panel dışına tıklama |
| Yeniden başlatma | İlgili son ekranında R |

Diyaloglar ve mini oyunlar kendi ekranlarında ek yönergeler gösterir. Matkap ve yangın tüpünde E yerine sol tık basılı tutulabilir. Enkazdaki sargı mini oyununda A ve D sırayla kullanılır. Hareket, koşma ve çömelme klavyeyle yapılır.

## Dosya düzeni

| Konum | İçerik |
| --- | --- |
| `project.godot` | Godot projesinin giriş dosyası |
| `main.gd`, `main.tscn` | Ana dünya ve oyun sahnesi |
| `player.gd`, `player.tscn` | Oyuncu karakteri ve hareket kontrolleri |
| `interaction.gd`, `camerashake.gd` | Etkileşim alanları ve kamera sarsıntısı |
| `scripts/` | Hikâye, envanter, öğretici, deprem ve mini oyun kodları |
| `scenes/` | Mobilya, eşya ve etkileşim sahneleri |
| `assets/` | Görseller, sprite sayfaları, dokular ve ses kaynakları |
| `trailer/` | Fragman sahneleri, kodları ve kayıt araçları |
| `export_presets.cfg` | Mac ve Windows dışa aktarma ayarları |
| `Windows/` | Oynanabilir Windows x64 paketi ve kullanım rehberi |
| `FARE_KONTROLLERI.txt` | Fare kontrollerinin kısa açıklaması |

## Büyük dosyalar ve Git LFS

`Windows/AsimoAfet.exe`, **Git LFS** ile takip edilir. Klonlama sonrasında EXE yerine yalnızca `version https://git-lfs.github.com/spec/v1` ile başlayan küçük bir metin dosyası varsa gerçek oyun dosyası henüz indirilmemiştir.

Komut satırını kullanıyorsan önce [Git LFS'yi kur](https://docs.github.com/en/repositories/working-with-files/managing-large-files/installing-git-large-file-storage), ardından:

```sh
git lfs install
git clone https://github.com/demdemmmm/asimoafet.git
cd asimoafet
git lfs pull
```

Repo zaten klonlandıysa repo klasöründe `git lfs pull` çalıştırman yeterlidir. GitHub'ın **Code → Download ZIP** arşivinde EXE yerine LFS işaretçisi bulunabilir; Windows paketi için yukarıdaki klonlama yöntemini kullan. [GitHub'ın arşiv ve LFS açıklaması](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/managing-git-lfs-objects-in-archives-of-your-repository)

Godot'un ürettiği `.godot/` önbelleği, çalışma günlükleri ve yerel yedek klasörleri Git'e eklenmez. `.uid` ve `.import` dosyaları kaynak kimliklerini ve içe aktarma ayarlarını korumak için repoda tutulur.

## Geliştirme notları

Geliştiricinin belirlediği oyun fikri, zaman döngüsü ve afet teması; hikâye, mekanikler ve sahne düzeniyle birlikte geliştirilmiştir. Süreçte **ChatGPT/Codex ve Claude** araçlarından destek alınmıştır:

- Hikâye akışı, diyaloglar ve alternatif sonlar.
- GDScript kodları, oyun mekanikleri ve hata ayıklama.
- Sahne düzeni, ışıklandırma, görsel yerleşimi ve çarpışma alanları.
- Fragman akışı, kamera hareketleri ve zamanlama.

Görsellerin tamamı yapay zekâ üretimi değildir; hazır veya geliştirici tarafından sağlanan görseller de kullanılmıştır.
