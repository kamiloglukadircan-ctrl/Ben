# TP-Link TD-W8970 v1 — UART Üzerinden OpenWrt Kurulum Rehberi

Bu doküman, cihaz elimize geçtiğinde UART (seri konsol) üzerinden güncel bir
OpenWrt sürümü yüklemek için izlenecek adımları içerir. Kaynak:
https://openwrt.org/toh/tp-link/td-w8970_v1

> **Önemli:** Bu cihazın v1/v1.2 sürümü Lantiq (VRX268/VR9) tabanlıdır ve
> desteklenir. **v3 sürümü Broadcom'dur ve OpenWrt desteklemez** — flaşlamadan
> önce cihazın etiketindeki sürümü (v1, v1.2, v3...) mutlaka doğrula.

## 1. Gerekli Malzemeler (Checklist)

- [ ] TP-Link TD-W8970 **v1 veya v1.2** (v3 DEĞİL)
- [ ] 3.3V TTL USB-seri (UART) adaptör (ör. CP2102, FT232RL, PL2303 — **5V değil, 3.3V** çıkışlı olmalı)
- [ ] Jumper kablolar (adaptörden J7 pinlerine bağlamak için)
- [ ] Lehim/pin başlık gerekebilir (J7 üzerinde header yoksa)
- [ ] Ethernet kablosu (bilgisayar ↔ router LAN portu)
- [ ] Terminal programı: `minicom`, `picocom` veya `screen` (Linux/Mac) ya da PuTTY (Windows)
- [ ] TFTP server yazılımı (Linux: `tftpd-hpa` / `dnsmasq --enable-tftp`; Windows: Tftpd64; Mac: `tftpd` yerleşik)
- [ ] Router kasasını açmak için tornavida (garanti kaybı riski var, bilgin olsun)

## 2. UART Bağlantısı (Donanım)

Konnektör: **J7** üzerinde, PCB üzerinde işaretli.

Pin sırası (yukarıdan aşağıya): **VCC(3.3V) — GND — Rx — Tx**

| USB-Seri Adaptör | Router J7 |
|---|---|
| GND | GND |
| RX | TX (router'ın Tx'i) |
| TX | RX (router'ın Rx'i) |
| VCC | **BAĞLAMA** (adaptörün 3.3V pinini J7'nin VCC'sine bağlamıyoruz — router zaten kendi gücünden besleniyor, sadece GND/RX/TX yeterli) |

> **Not:** GND noktası bazı revizyonlarda tam delinmemiş olabilir; lehimlemede
> zorlanırsan yakındaki "GND3" via noktasını kullan.

Seri port ayarları: **115200 baud, 8N1** (8 data bit, no parity, 1 stop bit), donanım/yazılım akış kontrolü kapalı.

## 3. Yazılım Hazırlığı (Cihaz Gelmeden Önce Yapılabilir)

### 3.1 Terminal programı testi
```bash
# Adaptör takıldığında hangi cihaz olarak göründüğünü kontrol et
ls /dev/ttyUSB*   # genelde /dev/ttyUSB0

# picocom ile bağlantı (örnek)
picocom -b 115200 /dev/ttyUSB0

# veya minicom ile
minicom -D /dev/ttyUSB0 -b 115200
```

### 3.2 TFTP server kurulumu (Linux örneği)
```bash
sudo apt install tftpd-hpa
sudo mkdir -p /srv/tftp
sudo chmod 777 /srv/tftp
sudo systemctl restart tftpd-hpa
```
Bilgisayarın Ethernet arayüzüne router ile aynı subnet'te **statik IP** ver
(örn. `192.168.1.2/24`), çünkü aşağıdaki U-Boot komutlarında bu IP kullanılıyor.

### 3.3 Doğru OpenWrt imajını indirme

ToH sayfasına göre bu cihaz için güncel desteklenen sürüm **25.12.2**.
Kesin indirme linkini almak için (bu ortamda openwrt.org'a erişim engelli
olduğundan tam dosya adını şimdi teyit edemedim):

1. https://firmware-selector.openwrt.org adresine git
2. Arama kutusuna **"tp-link_td-w8970-v1"** yaz
3. **Sysupgrade** imajını indir (dosya adı örn. `openwrt-25.12.2-lantiq-xrx200-tplink_tdw8970-v1-squashfs-sysupgrade.bin` şeklinde olacaktır — tam adı indirdiğinde göreceksin)
4. İndirilen dosyayı `/srv/tftp/` klasörüne kopyala ve TFTP'nin okuyabileceği kısa bir isimle de bir kopyasını oluştur, ör:
   ```bash
   cp openwrt-*-tplink_tdw8970*-sysupgrade.bin /srv/tftp/openwrt-tdw8970-sysupgrade.bin
   ```

> **Neden sysupgrade, factory değil?** U-Boot üzerinden doğrudan flash'a
> yazarken OEM firmware'in beklediği header'lar önemsizdir; ham
> kernel+rootfs içeren **sysupgrade** imajı bu amaç için doğru olandır.

## 4. Flash İşlemi — Adım Adım (Cihaz Elinde Olduğunda)

1. Router'ı UART adaptörüne ve Ethernet ile bilgisayara bağla, **henüz güç verme**.
2. Terminal programını aç (115200 8N1) ve bekle.
3. Router'a güç ver, açılış sırasında **`t` tuşuna basılı/ısrarla bas** — U-Boot komut satırına (`VR9 #`) düşeceksin. Zamanlama dar olabilir, birkaç deneme gerekebilir.
4. U-Boot'ta IP ayarlarını yap:
   ```
   setenv ipaddr 192.168.1.1
   setenv serverip 192.168.1.2
   setenv bootargs 'board=WD8970'
   ```
5. İmajı TFTP üzerinden RAM'e çek:
   ```
   tftpboot 0x81000000 openwrt-tdw8970-sysupgrade.bin
   ```
   Transfer tamamlanınca `Bytes transferred = ...` mesajını göreceksin — bu değeri (hex) not al, `$(filesize)` otomatik ayarlanır.
6. Rootfs/firmware alanını sil:
   ```
   sf erase 0x20000 0x7a0000
   ```
7. İndirilen imajı flash'a yaz:
   ```
   sf write 0x81000000 0x20000 0x$(filesize)
   ```
8. Yeniden başlat:
   ```
   reset
   ```
9. Cihaz OpenWrt ile açılmalı. Router varsayılan olarak `192.168.1.1` üzerinde LuCI/SSH ile erişilebilir olacak (`br-lan`).

## 5. İlk Boot Sonrası Kontroller

```bash
ssh root@192.168.1.1          # ilk girişte şifre yok, uci ile şifre koy
cat /proc/mtd                 # partition tablosunu doğrula
dmesg | grep -i eth           # ethernet linklerini kontrol et
```
- `passwd` ile root şifresi belirle.
- `opkg update && opkg install luci` (web arayüzü istersen).
- VDSL/DSL firmware'i gerekiyorsa (`vdsl_fw_install.sh` veya trunk'ta hazır `lantiq-vrx200-a.bin`/`-b.bin`), `/etc/config/network` üzerinden `annex`, `tone`, `xfer_mode` ayarlarını hattına göre yap.

## 6. Geri Dönüş / Kurtarma Planı (Önlem)

- **Flaşlamadan önce OEM firmware'i yedekle.** Eğer OEM firmware üzerinde
  serial ile shell'e erişimin varsa:
  ```
  # OEM shell üzerinde (mtd araçlarıyla) mevcut partition'ları dd ile yedekle
  ```
  Not: Kalibrasyon (radio/ART) partition'ı **kesinlikle silinmemeli** — WLAN
  ve MAC adresi burada saklanıyor.
- Bir şeyler ters giderse: **Failsafe mod** — güç verdikten sonraki
  30-45. saniye aralığında **WPS butonuna saniyede bir kez bas** (basılı tutma,
  her saniye bas-bırak). Cihaz `192.168.1.1` ile failsafe moda girer.
- Tam brick durumunda: Yeniden U-Boot üzerinden `tftpboot` + `sf erase` +
  `sf write` ile tekrar dene (U-Boot'a erişimin olduğu sürece kurtarılabilir).
  U-Boot'un kendisi bozulursa donanımsal SPI programlayıcı (BusPirate,
  Raspberry Pi SPI, Pomona clip) gerekir — bkz. sayfadaki "Debricking" bölümü.

## 7. Riskler / Dikkat Edilecekler

- Yanlış (v3 için olan) imajı yazmak cihazı brick edebilir — **model/versiyon
  etiketini** açtığında mutlaka doğrula.
- `sf erase`/`sf write` adreslerini **birebir yukarıdaki gibi** kullan;
  `radio` (kalibrasyon) partition'ının olduğu adrese (`0x7f0000` sonrası)
  asla dokunma.
- UART adaptörünün **3.3V** olduğundan emin ol — 5V adaptör router'ın seri
  pinlerine zarar verebilir.
- İlk denemede `t` tuşuna basarken U-Boot'u kaçırırsan, cihazı OEM firmware
  ile normal açılışa bırak ve tekrar dene; bu adım risksizdir.

---
*Bu doküman, openwrt.org ToH sayfasının (2026-09-24 tarihli) özetinden
hazırlanmıştır. Flash öncesi firmware-selector.openwrt.org üzerinden güncel
dosya adını ve sürüm notlarını mutlaka teyit et.*
