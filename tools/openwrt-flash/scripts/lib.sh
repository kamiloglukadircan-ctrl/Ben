#!/usr/bin/env bash
# Ortak yardımcı fonksiyonlar. Diğer script'ler bunu source eder.
set -euo pipefail

require_config() {
    local config_path="${1:-}"
    if [[ -z "$config_path" ]]; then
        echo "Kullanım: $0 <config-dosyasi.env>" >&2
        echo "Örnek:    $0 ../config/tdw8970-v1.env" >&2
        exit 1
    fi
    if [[ ! -f "$config_path" ]]; then
        echo "Config dosyası bulunamadı: $config_path" >&2
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$config_path"

    local required_vars=(
        DEVICE_NAME SERIAL_PORT SERIAL_BAUD ROUTER_IP TFTP_SERVER_IP
        TFTP_ROOT_DIR FIRMWARE_TFTP_NAME FIRMWARE_SOURCE_PATH
        RAM_LOAD_ADDR FLASH_ERASE_START FLASH_ERASE_SIZE
    )
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            echo "Config'te eksik değişken: $var (dosya: $config_path)" >&2
            exit 1
        fi
    done
}

# picocom > minicom > screen sırasıyla ilk bulduğunu, ihtiyaç duyulan
# argümanlarla birlikte döndürür (exec edilecek komut dizisi olarak).
# Kullanım: pick_serial_cmd  (sonra "${SERIAL_CMD[@]}" ile çağır)
pick_serial_cmd() {
    if command -v picocom >/dev/null 2>&1; then
        SERIAL_CMD=(picocom -b "$SERIAL_BAUD" "$SERIAL_PORT")
    elif command -v minicom >/dev/null 2>&1; then
        SERIAL_CMD=(minicom -D "$SERIAL_PORT" -b "$SERIAL_BAUD")
    elif command -v screen >/dev/null 2>&1; then
        SERIAL_CMD=(screen "$SERIAL_PORT" "$SERIAL_BAUD")
    else
        echo "HATA: picocom, minicom veya screen bulunamadı. Birini kur:" >&2
        echo "  sudo apt install picocom" >&2
        exit 1
    fi
}
