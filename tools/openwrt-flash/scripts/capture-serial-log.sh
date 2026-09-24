#!/usr/bin/env bash
# connect-serial.sh ile aynı bağlantıyı açar, ama TÜM oturumu (yazdığın ve
# router'ın bastığı her şeyi) bir log dosyasına kaydeder. Yedekleme
# komutlarının çıktısını daha sonra extract-backup.sh ile işlemek için
# kullanılır.
#
# Kullanım: ./capture-serial-log.sh ../config/<cihaz>.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
require_config "${1:-}"

if [[ ! -e "$SERIAL_PORT" ]]; then
    echo "UYARI: $SERIAL_PORT bulunamadı. Mevcut portlar:" >&2
    ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo "  (hiç USB-seri cihaz görünmüyor)" >&2
    exit 1
fi

if ! command -v script >/dev/null 2>&1; then
    echo "HATA: 'script' komutu bulunamadı (genelde util-linux/bsdutils paketinde gelir)." >&2
    exit 1
fi

mkdir -p "${BACKUP_DIR:-$HOME/openwrt-backups}/raw-logs"
LOG_FILE="${BACKUP_DIR:-$HOME/openwrt-backups}/raw-logs/serial-$(date +%Y%m%d-%H%M%S).log"

pick_serial_cmd

echo "== $DEVICE_NAME — loglanan seri oturum =="
echo "Log dosyası: $LOG_FILE"
echo "Oturumdan çıkınca (picocom: Ctrl-A Ctrl-X) bu dosyayı extract-backup.sh'a ver."
echo

script -q -c "$(printf '%q ' "${SERIAL_CMD[@]}")" "$LOG_FILE"

echo
echo "Oturum kapandı. Log kaydedildi: $LOG_FILE"
