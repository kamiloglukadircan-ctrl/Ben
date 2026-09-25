#!/usr/bin/env bash
# Ortak yardımcı fonksiyonlar. Diğer script'ler bunu source eder.
set -euo pipefail

require_config() {
    local config_path="${1:-}"
    if [[ -z "$config_path" ]]; then
        echo "Kullanım: $0 <config-dosyasi.env>" >&2
        echo "Örnek:    $0 ../config/humax-5000s.env" >&2
        exit 1
    fi
    if [[ ! -f "$config_path" ]]; then
        echo "Config dosyası bulunamadı: $config_path" >&2
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$config_path"

    local required_vars=(
        DEVICE_NAME DEVICE_ARCH NAND_DUMP_PATH EXTRACT_DIR
    )
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            echo "Config'te eksik değişken: $var (dosya: $config_path)" >&2
            exit 1
        fi
    done
}

log_info()  { echo "[BİLGİ]  $*"; }
log_warn()  { echo "[UYARI]  $*" >&2; }
log_error() { echo "[HATA]   $*" >&2; }
log_ok()    { echo "[  OK  ]  $*"; }

require_tool() {
    local tool="$1"
    if ! command -v "$tool" >/dev/null 2>&1; then
        log_error "'$tool' bulunamadı. Kurulum:"
        case "$tool" in
            binwalk)
                echo "  Mac:   brew install binwalk" >&2
                echo "  Linux: sudo apt install binwalk" >&2
                ;;
            qemu-system-mips|qemu-system-mipsel)
                echo "  Mac:   brew install qemu" >&2
                echo "  Linux: sudo apt install qemu-system-mips" >&2
                ;;
            unsquashfs)
                echo "  Mac:   brew install squashfs" >&2
                echo "  Linux: sudo apt install squashfs-tools" >&2
                ;;
            mips-linux-gnu-objdump|mips-linux-gnu-readelf)
                echo "  Mac:   brew install mips-elf-binutils" >&2
                echo "  Linux: sudo apt install binutils-mips-linux-gnu" >&2
                ;;
            jefferson)
                echo "  pip3 install jefferson" >&2
                ;;
            sasquatch)
                echo "  git clone https://github.com/devttys0/sasquatch && cd sasquatch && ./build.sh" >&2
                ;;
            *)
                echo "  Sistem paket yöneticisi ile kur." >&2
                ;;
        esac
        exit 1
    fi
}

human_size() {
    local bytes="$1"
    if (( bytes >= 1073741824 )); then
        printf "%.1f GB" "$(echo "$bytes / 1073741824" | bc -l)"
    elif (( bytes >= 1048576 )); then
        printf "%.1f MB" "$(echo "$bytes / 1048576" | bc -l)"
    elif (( bytes >= 1024 )); then
        printf "%.1f KB" "$(echo "$bytes / 1024" | bc -l)"
    else
        printf "%d B" "$bytes"
    fi
}
