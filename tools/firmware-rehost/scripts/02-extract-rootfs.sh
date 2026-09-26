#!/usr/bin/env bash
# ==========================================================================
# Adım 2: RootFS Çıkarma
# ==========================================================================
# 01-nand-analyze.sh'ın bulduğu SquashFS / JFFS2 bölümlerini dökümden
# çıkarır ve bir dizine açar. Çıkan dosya sistemi QEMU chroot'unda
# kullanılacak.
#
# Kullanım: ./02-extract-rootfs.sh ../config/humax-5000s.env [ofset]
#
# Ofset verilmezse binwalk ilk SquashFS'i otomatik bulur.
# Ofset hex (0x1A0000) veya decimal (1703936) olarak verilebilir.
# ==========================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
require_config "${1:-}"
require_tool binwalk

MANUAL_OFFSET="${2:-}"

if [[ ! -f "$NAND_DUMP_PATH" ]]; then
    log_error "NAND döküm dosyası bulunamadı: $NAND_DUMP_PATH"
    exit 1
fi

mkdir -p "$EXTRACT_DIR"

# --- Eğer OOB temizliği gerekiyorsa ---
CLEAN_DUMP="${NAND_DUMP_PATH%.bin}-clean.bin"
if [[ -f "$CLEAN_DUMP" ]]; then
    log_info "OOB temizlenmiş döküm bulundu, onu kullanıyorum: $CLEAN_DUMP"
    WORK_DUMP="$CLEAN_DUMP"
else
    WORK_DUMP="$NAND_DUMP_PATH"
fi

# --- Binwalk ile otomatik çıkarma ---
log_info "Cihaz: $DEVICE_NAME"
log_info "Kaynak: $WORK_DUMP"
echo

if [[ -n "$MANUAL_OFFSET" ]]; then
    # Manuel ofset verildi — dd ile kes, sonra unsquashfs
    log_info "Manuel ofset kullanılıyor: $MANUAL_OFFSET"

    # Hex'i decimal'e çevir
    if [[ "$MANUAL_OFFSET" == 0x* ]]; then
        OFFSET_DEC=$(printf "%d" "$MANUAL_OFFSET")
    else
        OFFSET_DEC="$MANUAL_OFFSET"
    fi

    SQFS_FILE="$EXTRACT_DIR/rootfs-manual.sqfs"
    log_info "Ofsetten itibaren SquashFS kesiliyor..."
    dd if="$WORK_DUMP" bs=1 skip="$OFFSET_DEC" of="$SQFS_FILE" 2>/dev/null
    SQFS_SIZE=$(stat -f%z "$SQFS_FILE" 2>/dev/null || stat -c%s "$SQFS_FILE" 2>/dev/null)
    log_info "Kesilen blok: $(human_size "$SQFS_SIZE")"

    ROOTFS_DIR="$EXTRACT_DIR/rootfs"
    log_info "SquashFS açılıyor..."
    mkdir -p "$ROOTFS_DIR"

    if command -v unsquashfs >/dev/null 2>&1; then
        unsquashfs -d "$ROOTFS_DIR" -f "$SQFS_FILE" 2>&1 || {
            log_warn "Standart unsquashfs başarısız — sasquatch denenecek"
            if command -v sasquatch >/dev/null 2>&1; then
                sasquatch -d "$ROOTFS_DIR" -f "$SQFS_FILE" 2>&1
            else
                log_error "sasquatch bulunamadı. Broadcom özel SquashFS için gerekli."
                log_error "Kurulum: git clone https://github.com/devttys0/sasquatch"
                exit 1
            fi
        }
    else
        require_tool unsquashfs
    fi
else
    # Binwalk otomatik çıkarma
    log_info "Binwalk otomatik çıkarma başlıyor..."
    log_info "(Bu işlem büyük dökümler için 5-15 dakika sürebilir)"
    echo

    binwalk -e -M -C "$EXTRACT_DIR" "$WORK_DUMP" 2>&1

    echo
    log_ok "Binwalk çıkarma tamamlandı."

    # Çıkarılan SquashFS rootfs'i bul
    ROOTFS_DIR=""
    while IFS= read -r -d '' sqfs_dir; do
        if [[ -d "$sqfs_dir" ]]; then
            ROOTFS_DIR="$sqfs_dir"
            break
        fi
    done < <(find "$EXTRACT_DIR" -type d -name "squashfs-root" -print0 2>/dev/null)

    if [[ -z "$ROOTFS_DIR" ]]; then
        # squashfs-root bulunamadıysa, _extracted dizinlerini kontrol et
        while IFS= read -r -d '' ext_dir; do
            if [[ -d "$ext_dir" ]]; then
                # İçinde /bin veya /etc olan ilk dizini rootfs kabul et
                for candidate in "$ext_dir"/*/; do
                    if [[ -d "${candidate}bin" || -d "${candidate}etc" ]]; then
                        ROOTFS_DIR="$candidate"
                        break 2
                    fi
                done
            fi
        done < <(find "$EXTRACT_DIR" -type d -name "*_extracted" -print0 2>/dev/null)
    fi
fi

# --- Sonuç raporu ---
echo
echo "=========================================="

if [[ -n "${ROOTFS_DIR:-}" && -d "$ROOTFS_DIR" ]]; then
    log_ok "RootFS bulundu: $ROOTFS_DIR"
    echo
    echo "Dizin yapısı (üst seviye):"
    ls -la "$ROOTFS_DIR" 2>/dev/null | head -20
    echo
    echo "Temel dizinler:"
    for d in bin sbin etc lib usr var tmp dev proc sys; do
        if [[ -d "$ROOTFS_DIR/$d" ]]; then
            COUNT=$(find "$ROOTFS_DIR/$d" -maxdepth 1 -not -name "$d" 2>/dev/null | wc -l)
            printf "  ✓ /%s (%d öğe)\n" "$d" "$COUNT"
        else
            printf "  ✗ /%s (yok)\n" "$d"
        fi
    done
    echo
    echo "Sonraki adım: 03-qemu-rehost.sh ile QEMU ortamında chroot"
    echo "  ./03-qemu-rehost.sh ../config/humax-5000s.env"
else
    log_warn "RootFS dizini otomatik bulunamadı."
    echo "Binwalk çıktısını kontrol et:" >&2
    find "$EXTRACT_DIR" -maxdepth 3 -type d 2>/dev/null | head -20
    echo >&2
    echo "Manuel çıkarma için ofseti belirt:" >&2
    echo "  $0 ${1:-config.env} 0x1A0000" >&2
fi
