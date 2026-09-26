# Humax QEMU Kiti

Çalışan bir **MIPS big-endian Linux** ortamını (OpenWrt Malta — W9970 benzeri
"donor" çekirdek) QEMU'da boot eder ve hasarlı NAND dökümünden **kurtardığımız
gerçek Humax parçalarını** (init scriptleri, binary'ler) içine bağlar.

## Ne veriyor

- QEMU'da çalışan MIPS big-endian Linux root kabuğu (senin W9970 donor fikrin)
- `/mnt/humax` altında kurtarılan gerçek Humax içeriği:
  - `etc/inittab` — UART'ın nasıl kapatıldığı (yorumlu `ttyS0::respawn:/bin/sh`)
  - `etc/init.d/S90settop` — kanal DB mount'ları (`ubi1:dbdata`)
  - `etc/passwd` — kullanıcı hesapları
  - `binaries/` — 147 kurtarılan blok (16 MIPS ELF parçası, `libnexus` dahil)
  - `scripts/tum_okunabilir_metin.txt` — tüm okunabilir metin

## Ne değil

Bu **tam Humax sistemi değil.** Dökümün metadata tabloları (inode/dizin)
hasarlı olduğu için tam dosya ağacı çıkarılamadı. Bu, çalışan bir MIPS
ortamı + kurtardığımız gerçek Humax parçaları. Tam sistem için temiz bir
NAND dökümü (doğru byte-order ile yeniden okuma) gerekir.

## Kullanım (Lenovo / Linux Mint)

```bash
cd ~/Ben && git pull
cd tools/firmware-rehost/qemu-kit
./run-humax-qemu.sh
```

Script otomatik: qemu kurar, MIPS big-endian donor kernel'i indirir, kurtarılan
içeriği disk imajına koyar, QEMU'yu başlatır.

Boot bitince (OpenWrt kabuğu) QEMU içinde:

```sh
mkdir -p /mnt/humax
mount -t ext2 /dev/sda /mnt/humax
cat /mnt/humax/etc/inittab              # UART satırları
cat /mnt/humax/etc/init.d/S90settop     # kanal DB mount'ları
ls -la /mnt/humax/binaries/             # kurtarılan binary'ler
```

QEMU'dan çıkış: `Ctrl-A` sonra `X`.

## Tam Humax için sonraki adım

Çipi **doğru byte-order** ile yeniden oku (mevcut döküm 4-byte ters + son
bölge hasarlı). Temiz döküm gelince `unsquashfs` ile tam rootfs açılır,
bu kitteki disk imajının yerine konur ve gerçek Humax chroot'u çalışır.
