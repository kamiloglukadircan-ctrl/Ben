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

2) İmajı RAM'e çek:
   tftpboot ${RAM_LOAD_ADDR} ${FIRMWARE_TFTP_NAME}

   -> "Bytes transferred = ..." mesajını gördükten sonra devam et.

3) Flash alanını sil:
   sf erase ${FLASH_ERASE_START} ${FLASH_ERASE_SIZE}

4) Flash'a yaz:
   sf write ${RAM_LOAD_ADDR} ${FLASH_ERASE_START} 0x\$(filesize)

5) Yeniden başlat:
   reset

============================================================
NOTLAR:
${NOTES:-"(config dosyasında not girilmemiş)"}
============================================================
EOF
