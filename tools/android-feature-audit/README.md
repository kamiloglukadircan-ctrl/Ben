# Android özellik denetimi (Vivo Y21s için hazırlandı)

`audit.sh`, bağlı telefonun hangi özelliklerinin **açık, kapalı veya kısıtlı**
olduğunu root gerektirmeden, sadece ADB ile okur. Telefonda hiçbir ayarı
değiştirmez.

## Hazırlık
1. Bilgisayara `adb` kurun (Android SDK platform-tools).
2. Telefonda: Ayarlar → Telefon hakkında → Yazılım sürümü'ne 7 kez dokunun.
3. Geliştirici seçenekleri → **USB hata ayıklama** açın, kabloyu takın, "izin ver" deyin.
4. `adb devices` cihazı `device` olarak göstermeli.

## Çalıştırma
```bash
./audit.sh            # ./audit-<model>-<tarih>/ klasörü oluşturur
```
Önce `OZET.txt` dosyasına bakın; ayrıntılar ham dosyalarda.

## Sonuçları okumak
| Bölüm | Neye bakılır |
|---|---|
| Donanım özellikleri | `YOK` ise sistem o donanımı bildirmiyor. NFC çipi yoksa yazılımla açılamaz. |
| Kamera | `supportedHardwareLevel`: 2=LEGACY, 0=LIMITED ise GCam/RAW desteği zayıf olur. |
| VoLTE/VoWiFi | `mtk_*_support` prop'ları donanım/ROM desteğini, `carrier_config` operatörün izin verip vermediğini gösterir. |
| Kapalı prop'lar | Değeri `0/false` olan `*support*`/`*enable*` anahtarlar ROM'da bilerek kapatılmış özelliklere işaret eder. |
| Devre dışı / kaldırılmış paketler | Sistemde duran ama kapatılmış uygulamalar. |
| device_config | Google/sistem özellik bayraklarından `false` olanlar. |
| Bootloader | `flash.locked=1` ve `verifiedbootstate=green` ise kilitli; `ro.*` prop'lar root olmadan değiştirilemez. |

Not: `ro.*` prop'lar salt okunurdur; kapalı görünen bir özelliği "açmak"
genellikle root veya ROM değişikliği gerektirir. Bu da garanti kaybı ve
telefonun açılmaz hale gelmesi (brick) riski taşır.
