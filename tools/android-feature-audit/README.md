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

## Bilgisayarsız: Termux'tan
Termux normal bir uygulama yetkisiyle çalışır. Tek başına sadece `getprop` ve
kısmen `pm` çalışır; `dumpsys`, `settings`, `device_config` izin hatası verir.
Tam sonuç için telefonun **kendine** kablosuz hata ayıklama ile bağlanın
(Android 11+, root gerekmez):

```bash
pkg update && pkg install android-tools git
```
1. Telefon bir Wi-Fi ağına bağlı olsun (internet gerekmez).
2. Geliştirici seçenekleri → **Kablosuz hata ayıklama** → aç →
   "Eşleştirme kodu ile cihaz eşleştir". Ekranı bölün (Termux + Ayarlar)
   ya da kodu not alıp hızlıca Termux'a geçin.
3. Termux'ta (portlar ekranda yazar, eşleştirme portu ile bağlantı portu farklıdır):
   ```bash
   adb pair 127.0.0.1:<eşleştirme_portu> <6_haneli_kod>
   adb connect 127.0.0.1:<bağlantı_portu>
   adb devices          # "device" görünmeli
   ```
4. Betiği çalıştırın:
   ```bash
   ./audit.sh ~/storage/shared/audit   # termux-setup-storage sonrası Dosyalar'da görünür
   ```

adb bağlı değilse betik otomatik olarak sınırlı yerel modda çalışır.

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
