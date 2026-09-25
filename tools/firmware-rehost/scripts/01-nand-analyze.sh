#!/usr/bin/env bash
# ==========================================================================
# Adım 1: NAND Döküm Analizi
# ==========================================================================
# Ham NAND dökümünü binwalk ile tarar; SquashFS, JFFS2, kernel, bootloader
# gibi bileşenlerin ofsetlerini ve türlerini raporlar. Henüz bir şey
# çıkarmaz — sadece haritayı çıkarır.
#
# Kullanım: ./01-nand-analyze.sh ../config/humax-5000s.env
# ==========================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
require_config "${1:-}"
require_tool binwalk

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

# --- Entropy analizi (şifreli/sıkıştırılmış bölgeleri gösterir) ---
log_info "Entropy analizi yapılıyor..."
ENTROPY_PNG="$EXTRACT_DIR/entropy.png"
mkdir -p "$EXTRACT_DIR"
binwalk -E -N -F "$NAND_DUMP_PATH" > "$EXTRACT_DIR/entropy.txt" 2>&1 || true
log_ok "Entropy grafiği: $EXTRACT_DIR/entropy.txt"
echo

# --- Ana imza taraması ---
log_info "Binwalk imza taraması başlıyor (bu büyük dökümler için 1-5 dk sürebilir)..."
SCAN_REPORT="$EXTRACT_DIR/binwalk-scan.txt"
binwalk "$NAND_DUMP_PATH" | tee "$SCAN_REPORT"
echo
log_ok "Tarama raporu: $SCAN_REPORT"

# --- Bulguları özetle ---
echo
echo "=========================================="
echo "ÖZET — Bulunan dosya sistemi imzaları:"
echo "=========================================="

SQFS_COUNT=$(grep -ci "squashfs" "$SCAN_REPORT" 2>/dev/null || echo "0")
JFFS_COUNT=$(grep -ci "jffs2" "$SCAN_REPORT" 2>/dev/null || echo "0")
CRAMFS_COUNT=$(grep -ci "cramfs" "$SCAN_REPORT" 2>/dev/null || echo "0")
LZMA_COUNT=$(grep -ci "lzma" "$SCAN_REPORT" 2>/dev/null || echo "0")
UIMAGE_COUNT=$(grep -ci "uimage\|u-boot" "$SCAN_REPORT" 2>/dev/null || echo "0")
GZIP_COUNT=$(grep -ci "gzip" "$SCAN_REPORT" 2>/dev/null || echo "0")

echo "  SquashFS  : $SQFS_COUNT adet"
echo "  JFFS2     : $JFFS_COUNT adet"
echo "  CramFS    : $CRAMFS_COUNT adet"
echo "  LZMA blob : $LZMA_COUNT adet"
echo "  gzip blob : $GZIP_COUNT adet"
echo "  uImage/UBoot: $UIMAGE_COUNT adet"
echo

if (( SQFS_COUNT > 0 )); then
    log_ok "SquashFS bulundu — bir sonraki adım: 02-extract-rootfs.sh"
    echo "  SquashFS ofseti(leri):"
    grep -i "squashfs" "$SCAN_REPORT" | head -5
elif (( JFFS_COUNT > 0 )); then
    log_warn "JFFS2 bulundu ama SquashFS yok. RootFS JFFS2 tabanlı olabilir."
    echo "  JFFS2 ofseti(leri):"
    grep -i "jffs2" "$SCAN_REPORT" | head -5
else
    log_warn "Bilinen dosya sistemi imzası bulunamadı."
    echo "Olası nedenler:" >&2
    echo "  1) NAND OOB verisi ham döküme karışmış — nand-tool ile temizle" >&2
    echo "  2) Döküm şifreli (entropy analizi kontrol et)" >&2
    echo "  3) Özel/bilinmeyen dosya sistemi formatı" >&2
    echo >&2
    echo "OOB temizliği için:" >&2
    echo "  nand-tool -i $NAND_DUMP_PATH -o ${NAND_DUMP_PATH%.bin}-clean.bin \\" >&2
    echo "    -p $NAND_PAGE_SIZE -s $NAND_OOB_SIZE" >&2
fi
