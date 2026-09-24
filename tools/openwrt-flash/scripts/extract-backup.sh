#!/usr/bin/env bash
# capture-serial-log.sh ile kaydedilmiş bir log dosyasından, print-backup-steps.sh
# komutlarının bastığı ===BACKUP:<isim>:START=== / ===BACKUP:<isim>:END===
# blokları arasındaki hex veriyi ayıklayıp gerçek .bin dosyalarına çevirir.
#
# Kullanım: ./extract-backup.sh ../config/<cihaz>.env <log-dosyasi>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
require_config "${1:-}"

LOG_FILE="${2:-}"
if [[ -z "$LOG_FILE" || ! -f "$LOG_FILE" ]]; then
    echo "Kullanım: $0 <config.env> <log-dosyasi>" >&2
    echo "Log dosyası bulunamadı: ${LOG_FILE:-<verilmedi>}" >&2
    exit 1
fi

# hex_decode: stdin'den hex string okur, stdout'a ham (binary) yazar.
# xxd -> python3 -> perl sırasıyla ilk bulduğunu kullanır.
if command -v xxd >/dev/null 2>&1; then
    hex_decode() { xxd -r -p; }
elif command -v python3 >/dev/null 2>&1; then
    hex_decode() { python3 -c 'import sys,binascii; sys.stdout.buffer.write(binascii.unhexlify(sys.stdin.read().strip()))'; }
elif command -v perl >/dev/null 2>&1; then
    hex_decode() { perl -ne 'print pack("H*", $_)'; }
else
    echo "HATA: hex çözmek için xxd, python3 veya perl'den hiçbiri bulunamadı." >&2
    exit 1
fi

if [[ -z "${BACKUP_PARTITIONS:-}" ]]; then
    echo "Config'te BACKUP_PARTITIONS boş, çıkarılacak bir şey yok." >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
FAILED=0

for part in $BACKUP_PARTITIONS; do
    OUT="$BACKUP_DIR/${part}-${STAMP}.bin"
    HEX_CHARS=$(
        awk -v p="$part" '
            $0 ~ "===BACKUP:" p ":START===" { flag=1; next }
            $0 ~ "===BACKUP:" p ":END===" { flag=0 }
            flag { print }
        ' "$LOG_FILE" | tr -d ' \t\r\n'
    )

    if [[ -z "$HEX_CHARS" ]]; then
        echo "UYARI: '$part' için log'da START/END bloğu bulunamadı, atlanıyor." >&2
        FAILED=1
        continue
    fi

    if (( ${#HEX_CHARS} % 2 != 0 )); then
        echo "UYARI: '$part' için ayıklanan hex verisi tek sayıda karakter — kayıp/bozuk olabilir." >&2
    fi

    echo "$HEX_CHARS" | hex_decode > "$OUT"
    SIZE=$(stat -c%s "$OUT" 2>/dev/null || wc -c < "$OUT")
    echo "OK: $part -> $OUT ($SIZE byte)"
    echo "    Kontrol: bu boyutu router'da 'cat /proc/mtd' çıktısındaki partition"
    echo "    boyutuyla karşılaştır — eşleşmiyorsa capture'ı tekrarla."
done

if [[ "$FAILED" -eq 1 ]]; then
    echo
    echo "Bazı partition'lar çıkarılamadı. Log dosyasını gözden geçir: $LOG_FILE" >&2
    exit 1
fi
