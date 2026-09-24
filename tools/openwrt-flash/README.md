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
    lib.sh              # ortak fonksiyonlar (diğer script'ler bunu kullanır)
    setup-tftp.sh        # firmware'i TFTP kök dizinine kopyalar
    connect-serial.sh    # seri konsola bağlanır (picocom/minicom/screen)
    print-flash-steps.sh # U-Boot'a elle gireceğin komutları, config'ten
                          # doldurulmuş halde ekrana basar
```

## Kullanım (TD-W8970 v1 örneği)

```bash
cd tools/openwrt-flash

# 1. Firmware'i firmware-selector.openwrt.org'dan indir, sonra
#    config/tdw8970-v1.env içindeki FIRMWARE_SOURCE_PATH'i o dosyanın
#    gerçek yoluna güncelle.

# 2. Firmware'i TFTP dizinine kopyala
./scripts/setup-tftp.sh config/tdw8970-v1.env

# 3. Ayrı bir terminalde seri konsola bağlan
./scripts/connect-serial.sh config/tdw8970-v1.env

# 4. Hangi komutları gireceğini unutursan (başka bir terminalde):
./scripts/print-flash-steps.sh config/tdw8970-v1.env
```

`print-flash-steps.sh` hiçbir şeyi otomatik çalıştırmaz — sadece U-Boot
konsoluna elle/kopyala-yapıştır ile gireceğin komutları, config'teki
gerçek IP/adres değerleriyle doldurup ekrana basar. Flash işlemi seri
konsol üzerinden, senin kontrolünde ilerler.

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
