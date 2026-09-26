#!/usr/bin/env bash
# Config'teki değerlerle doldurulmuş, U-Boot konsoluna TEK TEK yapıştırılacak
# komutları ekrana basar. Hiçbir şeyi otomatik ÇALIŞTIRMAZ — U-Boot'a erişimin
# olan tek yer seri konsol olduğu için komutları elle/kopyala-yapıştır ile
# oraya sen giriyorsun.
#
# Kullanım: ./print-flash-steps.sh ../config/<cihaz>.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
require_config "${1:-}"

BOARD_LINE=""
if [[ -n "${BOARD_ARG:-}" ]]; then
    BOARD_LINE="setenv bootargs 'board=${BOARD_ARG}'"
fi

cat <<EOF
============================================================
 $DEVICE_NAME — U-Boot Flash Adımları
============================================================
Kaynak: ${DEVICE_TOH_URL:-belirtilmemiş}

0) Router'a güç ver, açılışta 't' tuşuna basılı/ısrarla bas,
   U-Boot komut satırına (genelde bir prompt görünür) düş.

1) IP ayarları:
   setenv ipaddr ${ROUTER_IP}
   setenv serverip ${TFTP_SERVER_IP}
$( [[ -n "$BOARD_LINE" ]] && echo "   $BOARD_LINE" )

============================================================
 ADIM A — FLASH'A DOKUNMADAN RAM'DE TEST (ŞİDDETLE ÖNERİLİR)
============================================================
EOF

if [[ -n "${INITRAMFS_TFTP_NAME:-}" ]]; then
cat <<EOF
Bu adım hiçbir şeyi flash'a yazmaz. İmaj sadece RAM'e yüklenip oradan
çalıştırılır. Bir şey ters giderse elektriği kesip fişi çek/tak — cihaz
eski (OEM) firmware'iyle olduğu gibi açılır, flash'a hiç dokunulmamıştır.

A1) İmajı RAM'e çek:
    tftpboot ${RAM_LOAD_ADDR} ${INITRAMFS_TFTP_NAME}

    -> "Bytes transferred = ..." mesajını gördükten sonra devam et.

A2) RAM'den boot et (flash'a YAZMAZ):
    bootm ${RAM_LOAD_ADDR}

A3) OpenWrt RAM'de açılınca test et:
    NOT: bootm ile açılan OpenWrt, U-Boot'un ${ROUTER_IP} adresini DEĞİL,
    kendi varsayılan LAN adresi olan 192.168.1.1'i kullanır (bu, U-Boot'un
    ipaddr'ı sadece TFTP transferi içindir, OpenWrt'in ağ ayarıyla ilgisi
    yoktur). Bilgisayarının ağ arayüzüne GEÇİCİ olarak 192.168.1.x/24
    aralığından bir IP ver (örn. 192.168.1.5), sonra:
    - LAN portuna bağlanıp 192.168.1.1'e ping at
    - SSH ile bağlanmayı dene: ssh root@192.168.1.1
    - dmesg / ifconfig ile ethernet ve (varsa) WLAN'ın göründüğünü kontrol et
    - Sorun görürsen: sadece elektriği kes/tak, hiçbir hasar yok, OEM firmware
      hâlâ flash'ta duruyor.

A4) Her şey iyi görünüyorsa: elektriği kesip tekrar ver, açılışta yine
    't' tuşuna basıp U-Boot'a dön, ADIM B'ye geç (kalıcı flash).
    (RAM'de çalışan bir sistemden flash'a yazmak istersen, üzerindeyken
    "sysupgrade" komutunu da kullanabilirsin — ama bu toolkit'in B adımı
    U-Boot üzerinden garantili/tekrarlanabilir yolu izliyor.)

EOF
else
cat <<EOF
UYARI: Config'te INITRAMFS_TFTP_NAME/INITRAMFS_SOURCE_PATH tanımlı değil,
bu adım atlanıyor. Flash'a yazmadan önce test etmen şiddetle tavsiye edilir:
firmware-selector.openwrt.org'dan bu cihaz için "Initramfs" imajını da indirip
config dosyana INITRAMFS_SOURCE_PATH olarak ekle, sonra setup-tftp.sh'ı tekrar
çalıştır.

EOF
fi

cat <<EOF
============================================================
 ADIM B — KALICI FLASH (GERİ DÖNÜŞÜ YOK)
============================================================
B1) İmajı RAM'e çek:
   tftpboot ${RAM_LOAD_ADDR} ${FIRMWARE_TFTP_NAME}

   -> "Bytes transferred = ..." mesajını gördükten sonra devam et.

B2) Flash alanını sil:
   sf erase ${FLASH_ERASE_START} ${FLASH_ERASE_SIZE}

B3) Flash'a yaz:
   sf write ${RAM_LOAD_ADDR} ${FLASH_ERASE_START} 0x\$(filesize)

B4) Yeniden başlat:
   reset

============================================================
NOTLAR:
${NOTES:-"(config dosyasında not girilmemiş)"}
============================================================
EOF
