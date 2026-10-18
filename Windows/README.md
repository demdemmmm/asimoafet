# One More Time — Windows

Bu klasör oyunun **Windows x64** sürümünü içerir. Oynamak için Godot kurmak gerekmez.

## Başlatma

1. Repoyu GitHub Desktop ile klonla ve indirme işleminin bitmesini bekle.
2. Bu klasördeki `AsimoAfet.exe` dosyasını çalıştır.
3. Başlangıç ekranında **PLAY** düğmesine tıkla veya **Enter** tuşuna bas.

`AsimoAfet.exe` ve `AsimoAfet.pck` aynı klasörde kalmalıdır. Oyunu başka bir bilgisayara aktarırken ikisini birlikte kopyala.

## Dosyalar

| Dosya | Görevi |
| --- | --- |
| `AsimoAfet.exe` | Windows çalıştırılabilir dosyası; Git LFS ile indirilir |
| `AsimoAfet.pck` | Sahne, kod ve kaynakları içeren oyun veri paketi |
| `NASIL ACILIR.txt` | Başlatma talimatlarının kısa metin sürümü |
| `FARE_KONTROLLERI.txt` | Fareyle etkileşim ve envanter kontrolleri |

## İndirme veya açılış sorunu

- **EXE çok küçük veya bir metin dosyası gibi görünüyor:** Git LFS dosyası indirilmemiş olabilir. Repo klasöründe `git lfs pull` çalıştır. Git LFS kurulu değilse [resmî kurulum rehberini](https://docs.github.com/en/repositories/working-with-files/managing-large-files/installing-git-large-file-storage) kullan.
- **Oyun veri paketini bulamıyor:** `AsimoAfet.pck` dosyasının EXE ile aynı klasörde ve adının değiştirilmemiş olduğunu kontrol et.
- **Dosyalar bir ZIP içindeyse:** Oyun dosyalarını önce bir klasöre çıkar, sonra EXE'yi çalıştır. EXE'nin Git LFS işaretçisi değil, tam indirilmiş dosya olduğunu kontrol et.
- **macOS kullanıyorsan:** Bu EXE Windows içindir. Kaynak projeyi açmak için [Godot geliştirme adımlarını](../README.md#godotta-geliştirmek) izle.

Tüm klavye/fare kontrolleri ve kaynak proje hakkında bilgi: [ana README](../README.md#kontroller).
