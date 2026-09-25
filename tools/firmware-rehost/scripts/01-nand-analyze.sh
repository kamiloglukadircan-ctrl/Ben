#!/usr/bin/env bash
# ==========================================================================
# Adım 1: NAND Döküm Analizi
# ==========================================================================
# Ham NAND dökümünü tarar; OOB temizliği yapar, SquashFS, JFFS2, kernel,
# bootloader gibi bileşenlerin ofsetlerini ve türlerini raporlar.
# Harici bağımlılık gerektirmez — sadece Python 3.
#
# Kullanım: ./01-nand-analyze.sh ../config/humax-5000s.env
# ==========================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
require_config "${1:-}"
require_tool python3

if [[ ! -f "$NAND_DUMP_PATH" ]]; then
    log_error "NAND döküm dosyası bulunamadı: $NAND_DUMP_PATH"
    echo "Programlayıcıdan okuttuğun .bin dosyasının yolunu config'te" >&2
    echo "NAND_DUMP_PATH olarak ayarla." >&2
    exit 1
fi

DUMP_SIZE=$(stat -f%z "$NAND_DUMP_PATH" 2>/dev/null || stat -c%s "$NAND_DUMP_PATH" 2>/dev/null)
log_info "Cihaz: $DEVICE_NAME"
log_info "SoC:   ${DEVICE_SOC:-bilinmiyor}"
log_info "Döküm: $NAND_DUMP_PATH ($(human_size "$DUMP_SIZE"))"
log_info "NAND sayfa: ${NAND_PAGE_SIZE}B, OOB: ${NAND_OOB_SIZE}B"
echo "=========================================="
echo

mkdir -p "$EXTRACT_DIR"

python3 "$SCRIPT_DIR/nand-scan.py" \
    "$NAND_DUMP_PATH" \
    --page "${NAND_PAGE_SIZE:-2048}" \
    --oob "${NAND_OOB_SIZE:-64}" \
    --output "$EXTRACT_DIR/nand-clean.bin" \
    2>&1 | tee "$EXTRACT_DIR/nand-scan-report.txt"

echo
log_ok "Tarama raporu: $EXTRACT_DIR/nand-scan-report.txt"
