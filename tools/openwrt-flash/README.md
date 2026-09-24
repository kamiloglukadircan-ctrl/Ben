# OpenWrt Flash Toolkit

Farklı cihazlara UART üzerinden OpenWrt kurulumunu **aynı script'lerle,
sadece config dosyası değiştirerek** tekrarlamak için hazırlanmış küçük bir
araç seti. Fikir: tüm cihaza-özel bilgi (IP'ler, seri port, flash adresleri,
firmware dosya yolu) `config/*.env` dosyalarında; `scripts/` altındaki
her şey config'i okuyup ona göre davranır, hiçbir script cihaza özel
değer içermez.

## Klasör yapısı

```
tools/openwrt-flash/
  config/
    template.env       # yeni cihaz eklerken kopyalanacak şablon
    tdw8970-v1.env      # TP-Link TD-W8970 v1 için dolu config
  scripts/
    lib.sh                 # ortak fonksiyonlar (diğer script'ler bunu kullanır)
    setup-tftp.sh           # firmware'i TFTP kök dizinine kopyalar
    connect-serial.sh       # seri konsola bağlanır (picocom/minicom/screen)
    print-flash-steps.sh    # U-Boot'a elle gireceğin komutları, config'ten
                             # doldurulmuş halde ekrana basar
    print-backup-steps.sh   # OEM firmware'i flaşlamadan önce yedeklemek için
                             # router'a yapıştırılacak komutları üretir
    capture-serial-log.sh   # seri oturumu dosyaya loglayarak açar (yedekleme için)
    extract-backup.sh       # loglanan hex çıktısını gerçek .bin dosyalarına çevirir
```

## Kullanım (TD-W8970 v1 örneği)

```bash
cd tools/openwrt-flash

# 1. Firmware-selector.openwrt.org'dan hem "Sysupgrade" hem "Initramfs"
#    imajını indir; config/tdw8970-v1.env içindeki FIRMWARE_SOURCE_PATH ve
#    INITRAMFS_SOURCE_PATH değerlerini gerçek dosya yollarıyla güncelle.

# 2. Dosyaları TFTP dizinine kopyala
./scripts/setup-tftp.sh config/tdw8970-v1.env

# 3. Ayrı bir terminalde seri konsola bağlan
./scripts/connect-serial.sh config/tdw8970-v1.env

# 4. Komutları unutursan (başka bir terminalde):
./scripts/print-flash-steps.sh config/tdw8970-v1.env
```

`print-flash-steps.sh` hiçbir şeyi otomatik çalıştırmaz — sadece U-Boot
konsoluna elle/kopyala-yapıştır ile gireceğin komutları, config'teki
gerçek IP/adres değerleriyle doldurup ekrana basar. Çıktısı iki adıma
ayrılır:

- **ADIM A** — imajı sadece RAM'e yükleyip `bootm` ile geçici çalıştırır,
  **flash'a hiçbir şey yazmaz**. Bir sorun olursa elektriği kesip tekrar
  vermen yeterli, cihaz eski firmware'iyle açılır. `INITRAMFS_SOURCE_PATH`
  config'te tanımlıysa bu adım otomatik olarak komutlara dahil edilir.
- **ADIM B** — RAM testinden memnun kaldıktan sonra yapılan, **geri dönüşü
  olmayan** kalıcı flash yazımı.

Flash işlemi baştan sona seri konsol üzerinden, senin kontrolünde ilerler.

## OEM Firmware Yedekleme (Flaşlamadan Önce, Şiddetle Önerilir)

Cihazın hâlâ OEM firmware ile açılıp seri konsoldan doğrudan root shell
verdiği durumda (bu cihazda login: `admin`/`1234`), kritik partition'ları
(özellikle WLAN kalibrasyon/MAC verisi) bilgisayarına yedekleyebilirsin.
Yöntem: partition'ı router'da hex'e çevirip seri konsola bastır, tüm
oturumu bir log dosyasına kaydet, sonra log'dan gerçek `.bin` dosyasını
çıkar. Flash'a hiçbir şey yazmaz, sadece okur.

```bash
# 1. Router'da hangi partition isimlerinin olduğunu gör (seri konsolda):
#    cat /proc/mtd
#    Gördüğün isimleri config/tdw8970-v1.env içindeki BACKUP_PARTITIONS'a yaz.

# 2. Loglanan bir seri oturum aç (normal connect-serial.sh yerine):
./scripts/capture-serial-log.sh config/tdw8970-v1.env

# 3. print-backup-steps.sh'ın bastığı komutları o oturumda TEK TEK çalıştır:
./scripts/print-backup-steps.sh config/tdw8970-v1.env

# 4. Oturumdan çık (picocom: Ctrl-A Ctrl-X), sonra log'u işle:
./scripts/extract-backup.sh config/tdw8970-v1.env <capture'ın verdiği log yolu>
```

Çıkan `.bin` dosyaları `BACKUP_DIR`'a (`config/tdw8970-v1.env`'de tanımlı)
kaydedilir. `extract-backup.sh`'ın yazdığı dosya boyutunu, router'daki
`cat /proc/mtd` çıktısındaki partition boyutuyla karşılaştırıp doğrula.

Bu yöntem yalnızca küçük partition'lar (64-256KB) için pratiktir — tüm
8MB flash'ı yedeklemek istersen donanımsal bir SPI programlayıcı gerekir
(bkz. ana dokümandaki "Debricking" notu).

## Yeni bir cihaz eklemek

```bash
cp config/template.env config/<yeni-cihaz>.env
# template.env içindeki yorumları takip ederek değerleri doldur
# (ToH sayfasındaki "Installation" ve "Flash layout" bölümlerinden alınır)
./scripts/setup-tftp.sh config/<yeni-cihaz>.env
./scripts/connect-serial.sh config/<yeni-cihaz>.env
./scripts/print-flash-steps.sh config/<yeni-cihaz>.env
```

Script'lerde hiçbir değişiklik gerekmez — sadece yeni config dosyası.

## İlgili doküman

TD-W8970 v1 için donanım bağlantısı, malzeme listesi ve kurtarma planı gibi
daha geniş anlatım: [`docs/td-w8970-v1-uart-flash-guide.md`](../../docs/td-w8970-v1-uart-flash-guide.md)
