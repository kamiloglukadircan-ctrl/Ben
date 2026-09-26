# Humax HTR-1000S — Firmware Analiz Bulguları

NAND dökümü (`S34ML01G200BHI00@BGA63_2147`, 128MB) analizinden çıkan sonuçlar.

## 1. Byte-order sorunu (çözüldü)

Programlayıcı çipi **32-bit kelime ters (swap32)** okumuş. Ham dökümde SquashFS
magic'i `sqsh` görünüyor; her 4 baytlık grup ters çevrilince (`swap32`) standart
`hsqs` (little-endian SquashFS 4.0) oluyor.

- **RootFS**: SquashFS 4.0, gzip, 128KB blok, 3016 inode, ~15.88 MB, Kasım 2014
- **Ofset**: temiz dökümde `0x441000`
- **Veri blokları**: swap32 ile sorunsuz açılıyor (147+ blok, 16 MIPS ELF binary kurtarıldı)
- **Metadata tabloları (son ~52KB)**: bu dökümde hasarlı (inode/dizin/fragment
  tabloları hiçbir dönüşümle açılmıyor, kısmen 0xFF/silinmiş) → dosya ağacı/isimler
  tam kurtarılamadı, ama dosya **içerikleri** kurtarıldı.

> Not: Metadata hasarı bu okumaya özel olabilir. Çipi **byte-swap kapalı** (doğru
> endian) yeniden okumak muhtemelen direkt açılabilir temiz bir döküm verir.

## 2. Sistem profili

- **SoC**: Broadcom BCM7358 (MIPS, big-endian)
- **Init**: BusyBox 1.18.5, `/etc/inittab` + `/etc/init.d/rcS` → `S90settop`
- **Uygulama**: `/usr/bin/humaxtv`
- **Pazar/dil**: Almanca arayüz (Alman pazarı cihazı)
- **Kullanıcılar**: root, operator, sshd, daemon, www-data (`/etc/passwd`; şifreler
  `/etc/shadow`'da)

## 3. UART / root shell (Yol A)

`/etc/inittab` seri konsolun neden kapalı olduğunu gösteriyor:

```
# Put a getty on the serial port
# if debug
#ttyS0::respawn:/bin/sh                                      <- KAPALI (debug)
# else release
/dev/null::respawn:/sbin/getty /dev/null                     <- release: /dev/null'a yönlendirilmiş
#::respawn:/sbin/getty -n -L /sbin/autologin 115200 ttyS0    <- KAPALI
#::respawn:/sbin/getty -n -L 115200 --autologin root ttyS0   <- KAPALI (otomatik root)
```

**Root shell almak için**: release firmware'de UART getty bilerek `/dev/null`'a
yönlendirilmiş. Aktifleştirmek için inittab'daki `ttyS0::respawn:/bin/sh` ya da
`--autologin root ttyS0` satırını açmak gerekiyor. Bu, firmware'i düzenleyip geri
yazmayı (veya init'i çalışma anında değiştirmeyi) gerektirir.

## 4. Şifreleme / CAS

- **Çift CAS**: **Irdeto** + **Nagravision** (+ CI+ modülü desteği)
- Broadcom **Nexus** güvenli API'si: `NEXUS_Smartcard_*`, donanım descrambler
- CAS dosyaları: `/var/lib/humaxtv/cas/iruc/IrUC_PSFile_1` (Irdeto UC kalıcı dosya)
- Gömülü X.509 sertifikaları mevcut (`-----BEGIN CERTIFICATE-----`)
- Anahtar yönetimi büyük olasılıkla BCM7358 OTP/güvenli bölgede (donanımsal) —
  yazılımda düz anahtar bulunmadı (beklenen; CAS güvenliği donanıma bağlı)

## 5. Kanal veritabanı (asıl hedef)

`S90settop` başlatma betiğinden:

```
mount -t ubifs -o sync ubi1:dbdata   /var/lib/humaxtv         # ANA kanal DB
mount -t ubifs -o sync ubi1:dbbackup /var/lib/humaxtv_backup  # yedek
mount -t ubifs -o sync ubi1:dbuser   /var/lib/humaxtv_user    # kullanıcı ayarları
```

**Kanal listesi `ubi1:dbdata` UBIFS biriminde** — rootfs SquashFS'inde değil,
NAND'in ayrı bir **UBI partition**'ında. Kanal düzenleme/aktarma için hedeflenecek
yer burasıdır. UBI, OOB metadata'sına bağlı olduğundan, bu partition'ı okumak için
OOB'lu ham döküm ve `ubireader`/`ubidump` araçları gerekir.

## 6. Sonraki adımlar

| Hedef | Yapılacak |
|-------|-----------|
| Temiz rootfs | Çipi byte-swap kapalı yeniden oku → standart `unsquashfs` |
| Root shell (UART) | inittab'daki `ttyS0::respawn:/bin/sh` satırını aç, firmware'i geri yaz |
| Kanal düzenleme | OOB'lu ham dökümden `ubi1:dbdata` UBIFS'ini `ubireader` ile çıkar |
| CAS analizi | Kurtarılan MIPS ELF'lerini (humaxtv, cas modülleri) IDA/Ghidra ile incele |
