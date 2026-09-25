#!/usr/bin/env bash
# ==========================================================================
# Adım 5: Broadcom SquashFS Çıkarma
# ==========================================================================
# nand-scan.py'nin bulduğu SquashFS'i temiz NAND dökümünden keser ve
# sasquatch / unsquashfs ile açmayı dener. Broadcom BCM7xxx cihazları
# özel (modified) SquashFS formatı kullandığı için sasquatch gerekir.
#
# Kullanım: ./05-extract-squashfs.sh ../config/humax-htr1000s.env
# ==========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
require_config "${1:-}"

CLEAN_DUMP="$EXTRACT_DIR/nand-clean.bin"
SQFS_OFFSET="${2:-4599936}"  # 0x00463080 = 4599936 decimal

if [[ ! -f "$CLEAN_DUMP" ]]; then
    log_error "Temiz NAND dökümü bulunamadı: $CLEAN_DUMP"
    echo "Önce 01-nand-analyze.sh çalıştır — OOB temizliği yapıp nand-clean.bin üretir." >&2
    exit 1
fi

CLEAN_SIZE=$(stat -f%z "$CLEAN_DUMP" 2>/dev/null || stat -c%s "$CLEAN_DUMP" 2>/dev/null)

log_info "Cihaz: $DEVICE_NAME"
log_info "Temiz döküm: $CLEAN_DUMP ($(human_size "$CLEAN_SIZE"))"
log_info "SquashFS ofset: 0x$(printf '%08X' "$SQFS_OFFSET") ($SQFS_OFFSET)"
echo

# --- SquashFS bloğunu kes ---
SQFS_FILE="$EXTRACT_DIR/rootfs.sqfs"
ROOTFS_DIR="$EXTRACT_DIR/rootfs"

log_info "SquashFS bloğu kesiliyor (ofsetten itibaren tüm veri)..."
dd if="$CLEAN_DUMP" bs=1 skip="$SQFS_OFFSET" of="$SQFS_FILE" 2>/dev/null

SQFS_SIZE=$(stat -f%z "$SQFS_FILE" 2>/dev/null || stat -c%s "$SQFS_FILE" 2>/dev/null)
log_ok "SquashFS bloğu: $SQFS_FILE ($(human_size "$SQFS_SIZE"))"
echo

# --- Magic byte kontrolü ---
MAGIC=$(xxd -l 4 -p "$SQFS_FILE" 2>/dev/null || od -A n -t x1 -N 4 "$SQFS_FILE" | tr -d ' ')
log_info "Magic bytes: $MAGIC"
case "$MAGIC" in
    68737173|73716873) log_info "Standart SquashFS (hsqs/sqsh)" ;;
    73687371|71736873) log_info "Broadcom modifiye SquashFS (shsq/qshs)" ;;
    *)                 log_warn "Tanınmayan magic: $MAGIC" ;;
esac
echo

# --- Çıkarma denemeleri ---
mkdir -p "$ROOTFS_DIR"

extract_success=0

# Deneme 1: sasquatch (Broadcom özel formatlar için)
if command -v sasquatch >/dev/null 2>&1; then
    log_info "[Deneme 1/4] sasquatch ile çıkarılıyor..."
    if sasquatch -d "$ROOTFS_DIR" -f "$SQFS_FILE" 2>&1; then
        extract_success=1
        log_ok "sasquatch başarılı!"
    else
        log_warn "sasquatch başarısız."
    fi
else
    log_warn "[Deneme 1/4] sasquatch bulunamadı — atlanıyor."
    echo "  Kurulum: git clone https://github.com/devttys0/sasquatch" >&2
    echo "           cd sasquatch && ./build.sh" >&2
fi

# Deneme 2: unsquashfs (standart)
if [[ "$extract_success" -eq 0 ]] && command -v unsquashfs >/dev/null 2>&1; then
    log_info "[Deneme 2/4] unsquashfs ile çıkarılıyor..."
    if unsquashfs -d "$ROOTFS_DIR" -f "$SQFS_FILE" 2>&1; then
        extract_success=1
        log_ok "unsquashfs başarılı!"
    else
        log_warn "unsquashfs başarısız (beklenen — Broadcom özel format)."
    fi
fi

# Deneme 3: unsquashfs -no-xattrs (bazı sürümlerde yardımcı olur)
if [[ "$extract_success" -eq 0 ]] && command -v unsquashfs >/dev/null 2>&1; then
    log_info "[Deneme 3/4] unsquashfs -no-xattrs ile deneniyor..."
    if unsquashfs -no-xattrs -d "$ROOTFS_DIR" -f "$SQFS_FILE" 2>&1; then
        extract_success=1
        log_ok "unsquashfs -no-xattrs başarılı!"
    else
        log_warn "unsquashfs -no-xattrs başarısız."
    fi
fi

# Deneme 4: Farklı ofset — magic byte arama
if [[ "$extract_success" -eq 0 ]]; then
    log_info "[Deneme 4/4] Alternatif SquashFS ofseti aranıyor..."
    ALT_OFFSETS=$(python3 -c "
import sys
with open('$CLEAN_DUMP', 'rb') as f:
    data = f.read()
magics = [b'hsqs', b'sqsh', b'shsq', b'qshs']
for m in magics:
    idx = 0
    while True:
        idx = data.find(m, idx)
        if idx == -1:
            break
        if idx != $SQFS_OFFSET:
            print(f'{idx} 0x{idx:08X} {m.decode(\"ascii\", errors=\"replace\")}')
        idx += 1
" 2>/dev/null || true)
    if [[ -n "$ALT_OFFSETS" ]]; then
        echo "  Alternatif SquashFS konumları:"
        echo "$ALT_OFFSETS" | sed 's/^/    /'
        echo
        echo "  Farklı ofsetle tekrar dene:"
        echo "    $0 ${1:-config.env} <decimal-ofset>"
    else
        echo "  Başka SquashFS magic'i bulunamadı."
    fi
fi

echo
echo "=========================================="

if [[ "$extract_success" -eq 1 ]]; then
    # Başarılı çıkarma — sonuçları göster
    log_ok "RootFS başarıyla çıkarıldı: $ROOTFS_DIR"
    echo
    echo "Dizin yapısı:"
    ls -la "$ROOTFS_DIR" 2>/dev/null | head -20
    echo
    echo "Temel dizinler:"
    for d in bin sbin etc lib usr var tmp dev proc sys opt app; do
        if [[ -d "$ROOTFS_DIR/$d" ]]; then
            COUNT=$(find "$ROOTFS_DIR/$d" -maxdepth 1 2>/dev/null | wc -l)
            printf "  + /%s (%d oge)\n" "$d" "$((COUNT - 1))"
        fi
    done
    echo
    echo "Sonraki adimlar:"
    echo "  ./scripts/04-analyze-crypto.sh config/humax-htr1000s.env"
    echo "  ./scripts/03-qemu-rehost.sh config/humax-htr1000s.env"
else
    log_warn "SquashFS otomatik cikarilamamistir."
    echo
    echo "Bu Broadcom ozel SquashFS formati. Cozum:" >&2
    echo >&2
    echo "  1) sasquatch kur (Broadcom SquashFS destegi):" >&2
    echo "     git clone https://github.com/devttys0/sasquatch" >&2
    echo "     cd sasquatch && ./build.sh" >&2
    echo "     sudo cp sasquatch /usr/local/bin/" >&2
    echo "     # Sonra bu script'i tekrar calistir" >&2
    echo >&2
    echo "  2) firmware-mod-kit dene:" >&2
    echo "     git clone https://github.com/rampageX/firmware-mod-kit" >&2
    echo "     cd firmware-mod-kit" >&2
    echo "     ./unsquashfs_all.sh $SQFS_FILE" >&2
    echo >&2
    echo "  3) Jefferson (JFFS2 icin):" >&2
    echo "     pip3 install jefferson" >&2
    echo "     jefferson -d $ROOTFS_DIR $SQFS_FILE" >&2
    echo >&2
    echo "  4) Manuel strings analizi (cikaramasak bile icerigine bakabiliriz):" >&2
    echo "     strings $SQFS_FILE | grep -i 'linux\|root\|mount\|passwd\|aes\|key'" >&2
    echo "     strings $CLEAN_DUMP | grep -i 'password\|serial\|uart\|console'" >&2
fi
