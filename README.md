# One More Time

## Projeyi geliştirmek

Bu repo güncel Godot kaynaklarını, sahneleri, görselleri, sesi ve Windows oyun paketini içerir.

1. Repoyu GitHub Desktop ile klonla. `Windows/AsimoAfet.exe` dosyası Git LFS ile tutulur.
2. Godot **4.6.2** ile kök dizindeki `project.godot` dosyasını içe aktar/aç.
3. Oyunu başlatmak için **F5** kullan; ana sahne `main.tscn` dosyasıdır.

### Dosya düzeni

| Konum | İçerik |
| --- | --- |
| `project.godot` | Godot projesinin giriş dosyası |
| `main.gd`, `main.tscn` | Ana oyun akışı ve sahnesi |
| `player.gd`, `player.tscn` | Karakter ve hareket kontrolleri |
| `interaction.gd`, `camerashake.gd` | Etkileşimler ve kamera sarsıntısı |
| `scripts/` | Hikâye, envanter, öğretici, deprem ve mini oyun kodları |
| `scenes/` | Mobilya, eşya ve etkileşim sahneleri |
| `assets/` | Oyunun PNG/SVG görselleri ve ses dosyaları |
| `trailer/` | Fragman sahneleri, kodları ve kayıt araçları |
| `export_presets.cfg` | Mac ve Windows dışa aktarma ayarları |
| `Windows/` | Oynanabilir Windows x64 paketi ve kullanım talimatları |

### Windows'ta oynamak

`Windows` klasörünü indir/klonla ve `AsimoAfet.exe` dosyasını çalıştır.
`AsimoAfet.pck` dosyası EXE ile aynı klasörde kalmalıdır.
EXE indirirken Git LFS dosyasının tamamının indiğinden emin ol; küçük bir metin işaretçisi oyun değildir.

Godot'un oluşturduğu `.godot/` önbelleği, çalışma günlükleri ve yerel yedek klasörleri Git'e eklenmez.
`.uid` ve `.import` dosyaları ise kaynakların kimliklerini ve içe aktarma ayarlarını korumak için repoda tutulur.

## Oyun hakkında

Game jam etkinlik

 Zaman, Seçim, Vicdan
Aynı gece. Aynı felaket. Farklı kararlar.
Büyük bir depremin ardından kendini tekrar tekrar aynı gecede bulan bir adam, her döngüde geçmişte yaşadıklarını hatırlayarak sevdiklerini kurtarmaya çalışır.
Ancak zaman geri alınabilse de her kararın bir sonucu vardır. Kimi kurtaracağın, nelerden vazgeçeceğin ve ne kadar hazırlıklı olduğun tamamen senin seçimlerine bağlı.
ASIMO AFET, zaman döngüsü, psikolojik gerilim ve afet bilincini birleştiren, oyuncunun vicdanını sorgulayan, çok sonlu bir 2D hikâye oyunudur.
Peki sen, her şeyi yeniden yaşama şansın olsaydı neyi değiştirirdin?


ASIMO AFET, deprem bilinci oluşturmayı amaçlayan, zaman döngüsü ve oyuncu seçimlerine dayalı, çok sonlu bir 2D hikâye oyunudur. Oyunun geliştirme sürecinde ChatGPT (GPT Pro) ve Claude Pro yapay zekâ araçlarından destek alınmıştır.
1. Hikâye ve Senaryo Geliştirme
Oyunun ana fikri, zaman döngüsü, afet teması ve oyuncunun vicdani seçimleri geliştirici tarafından belirlenmiştir.
Yapay zekâ şu alanlarda destek sağlamıştır:
- Senaryo fikirlerinin geliştirilmesi ve olayların birbirine bağlanması.
- Karakterler arasındaki diyalogların hazırlanması.
- Farklı zaman döngülerine göre konuşmaların çeşitlendirilmesi.
- Oyuncunun kararlarına bağlı alternatif hikâye akışlarının planlanması.
- Sinematik sahnelerin ve final fikirlerinin geliştirilmesi.
2. Programlama ve Oyun Mekanikleri
Claude Pro, Godot oyun motorunda GDScript kodlarının geliştirilmesi ve düzenlenmesi amacıyla kullanılmıştır.
Yapay zekâ desteği alınan başlıca sistemler:
- Karakter hareketleri ve etkileşim mekanikleri.
- Zaman döngüsü ve yeniden başlama sistemi.
- Deprem animasyonları ve kamera sarsıntıları.
- Envanter ve nesne toplama sistemi.
- Elektrik ve dolap sabitleme mini oyunları.
- Diyalog sistemi ve zamanlayıcılar.
- Fener ve ortam aydınlatması.
- Oyuncu seçimlerine bağlı olayların yönetilmesi.
3. Görsel Tasarım ve Sahne Düzenleme
Yapay zekâ, oyunun görsel tasarımını planlama ve mevcut görselleri sahnelere uyarlama süreçlerinde kullanılmıştır.
Bu kapsamda:
- Salon, mutfak, banyo ve yatak odalarının düzenlenmesi.
- Mobilyaların konumlandırılması ve ölçeklendirilmesi.
- Zemin ve duvar kaplamalarının uygulanması.
- Görsel katmanların ve çarpışma alanlarının düzenlenmesi.
- Işıklandırma ve atmosfer efektlerinin geliştirilmesi.
Not: Oyunda kullanılan bütün görsellerin yapay zekâ tarafından üretildiği söylenemez. Hazır veya geliştirici tarafından sağlanan görseller de kullanılmıştır.
4. Hata Ayıklama ve Optimizasyon
Yapay zekâ araçlarından oyun geliştirme sırasında karşılaşılan teknik problemlerin çözümünde yararlanılmıştır.
Örneğin:
- Tam ekran ölçeklendirme sorunları.
- Hatalı mobilya yerleşimleri.
- Animasyon ve seslerin yanlış zamanda tetiklenmesi.
- Olaylar arasındaki koşul çakışmaları.
- Karakter etkileşimleri ve zaman döngüsü hataları.
5. Fragman ve Tanıtım
Oyunun tanıtım fragmanının geliştirilmesinde de yapay zekâ desteğinden yararlanılmıştır.
- Fragmanın senaryosu ve sahne sıralaması planlanmıştır.
- Godot içerisinde sinematik fragman mimarisi hazırlanması için Claude kullanılmıştır.
- Kamera hareketleri, sahne geçişleri ve ses zamanlamaları üzerinde çalışılmıştır.
- Oyunun zaman döngüsü, seçimler ve afet bilinci temalarını öne çıkaran tanıtım metinleri hazırlanmıştır.
