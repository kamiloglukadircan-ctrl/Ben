#!/usr/bin/env bash
# Config'te tanımlı port/baud ile seri konsola bağlanır.
# Sırasıyla picocom, minicom, screen dener (hangisi kuruluysa).
#
# Kullanım: ./connect-serial.sh ../config/<cihaz>.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
require_config "${1:-}"

echo "== $DEVICE_NAME seri konsol bağlantısı =="
echo "Port: $SERIAL_PORT  Baud: $SERIAL_BAUD (8N1)"
echo

if [[ ! -e "$SERIAL_PORT" ]]; then
    echo "UYARI: $SERIAL_PORT bulunamadı. Mevcut portlar:" >&2
    ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo "  (hiç USB-seri cihaz görünmüyor)" >&2
    echo "Config dosyasındaki SERIAL_PORT değerini güncelle." >&2
    exit 1
fi

if command -v picocom >/dev/null 2>&1; then
    exec picocom -b "$SERIAL_BAUD" "$SERIAL_PORT"
elif command -v minicom >/dev/null 2>&1; then
    exec minicom -D "$SERIAL_PORT" -b "$SERIAL_BAUD"
elif command -v screen >/dev/null 2>&1; then
    exec screen "$SERIAL_PORT" "$SERIAL_BAUD"
else
    echo "HATA: picocom, minicom veya screen bulunamadı. Birini kur:" >&2
    echo "  sudo apt install picocom" >&2
    exit 1
fi
