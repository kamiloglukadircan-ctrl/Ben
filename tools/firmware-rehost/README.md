# Firmware Rehosting Toolkit

Kapalı UART portlu gömülü cihazların (ör. Humax IRHD-5000S) firmware'ini
sanal ortamda (QEMU) yeniden barındırarak (rehosting) analiz etmek için
araç takımı.

## Teknik: Alien Kernel Emülasyonu

Aynı CPU mimarisini (MIPS) paylaşan bir "donor" cihazın (ör. TD-W9970)
çekirdeğini QEMU'da boot edip, hedef cihazın (Humax) dosya sistemini
`chroot` ile bağlarız. Sonuç: havya kullanmadan, UART pinleriyle
boğuşmadan root shell.

```
┌─────────────────────────────────────────────┐
│  Mac Terminal                               │
│  ┌────────────────────────────────────────┐ │
│  │  QEMU  (Malta MIPS)                    │ │
│  │  ┌──────────────────────────────────┐  │ │
│  │  │  OpenWrt Kernel (donor)          │  │ │
│  │  │  ┌────────────────────────────┐  │  │ │
│  │  │  │  chroot /mnt/humax        │  │  │ │
│  │  │  │  ┌──────────────────────┐ │  │  │ │
│  │  │  │  │ Humax RootFS         │ │  │  │ │
│  │  │  │  │ /bin /etc /usr /lib  │ │  │  │ │
│  │  │  │  │ AES, init.d, config  │ │  │  │ │
│  │  │  │  └──────────────────────┘ │  │  │ │
│  │  │  └────────────────────────────┘  │  │ │
│  │  └──────────────────────────────────┘  │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

## Ön Koşullar

```bash
# macOS
brew install binwalk qemu squashfs

# Linux
sudo apt install binwalk qemu-system-mips squashfs-tools
```

## Kullanım (4 Adım)

### 1. NAND Döküm Analizi

Ham NAND dökümünü tarar, dosya sistemi imzalarını (SquashFS, JFFS2, kernel)
ve ofsetlerini bulur.

```bash
cd tools/firmware-rehost
./scripts/01-nand-analyze.sh config/humax-5000s.env
```

### 2. RootFS Çıkarma

Bulunan SquashFS'i dökümden çıkarıp bir dizine açar.

```bash
./scripts/02-extract-rootfs.sh config/humax-5000s.env
# veya manuel ofset ile:
./scripts/02-extract-rootfs.sh config/humax-5000s.env 0x1A0000
```

### 3. QEMU Rehosting (Frankenstein)

OpenWrt Malta kernel'ini QEMU'da boot eder, Humax rootfs'ini 9P ile paylaşır,
chroot ile root shell açar.

```bash
./scripts/03-qemu-rehost.sh config/humax-5000s.env
```

### 4. Kriptografi Analizi

Çıkarılmış rootfs üzerinde AES kütüphaneleri, sertifikalar, init betikleri
ve şifreleme mekanizmalarını tarar.

```bash
./scripts/04-analyze-crypto.sh config/humax-5000s.env
```

## QEMU'da Ne Çalışır, Ne Çalışmaz?

| Bileşen | Durum | Açıklama |
|---------|-------|----------|
| Shell (root) | Çalışır | BusyBox/ash üzerinden tam erişim |
| Dosya sistemi | Çalışır | Tüm dosyalar okunabilir/yazılabilir |
| Kriptografi (SW) | Çalışır | OpenSSL, libcrypto, AES fonksiyonları |
| Init script'leri | Çalışır | Başlatma sırası analiz edilebilir |
| Ağ (temel) | Çalışır | QEMU NAT üzerinden |
| TV GUI | Çalışmaz | DirectFB/framebuffer donanım gerektirir |
| MPEG dekoder | Çalışmaz | BCM7358 HW decoder |
| DVB-S2 tuner | Çalışmaz | Fiziksel uydu çipi gerektirir |
| HDMI çıkışı | Çalışmaz | Donanımsal video işlemci |
| Smartcard (CAS) | Kısmen | Yazılımsal kısım çalışır, fiziksel kart okuyucu yok |

## OOB Sorunu

Programlayıcı dökümü OOB (spare area) verisi içeriyorsa binwalk dosya
sistemini bulamayabilir. Bu durumda:

```bash
# nand-tool ile OOB temizliği
pip3 install nand-tool
nand-tool -i dump.bin -o dump-clean.bin -p 2048 -s 64
```

## Dizin Yapısı

```
tools/firmware-rehost/
├── config/
│   ├── template.env          # Yeni cihaz şablonu
│   └── humax-5000s.env       # Humax IRHD-5000S config
├── scripts/
│   ├── lib.sh                # Ortak fonksiyonlar
│   ├── 01-nand-analyze.sh    # NAND tarama
│   ├── 02-extract-rootfs.sh  # RootFS çıkarma
│   ├── 03-qemu-rehost.sh     # QEMU + chroot
│   └── 04-analyze-crypto.sh  # Kriptografi analizi
└── README.md
```
