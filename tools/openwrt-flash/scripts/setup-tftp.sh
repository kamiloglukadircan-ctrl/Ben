#!/usr/bin/env bash
# Firmware dosyasını TFTP kök dizinine, config'te tanımlı isimle kopyalar.
# TFTP server'ın (tftpd-hpa, dnsmasq --enable-tftp, vb.) zaten kurulu ve
# TFTP_ROOT_DIR'i kök dizin olarak kullanacak şekilde ayarlanmış olduğunu
# varsayar.
#
# Kullanım: ./setup-tftp.sh ../config/<cihaz>.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
require_config "${1:-}"

echo "== $DEVICE_NAME için TFTP hazırlığı =="

if [[ ! -f "$FIRMWARE_SOURCE_PATH" ]]; then
    echo "HATA: Firmware dosyası bulunamadı: $FIRMWARE_SOURCE_PATH" >&2
    echo "Config dosyasındaki FIRMWARE_SOURCE_PATH değerini güncelle." >&2
    exit 1
fi

mkdir -p "$TFTP_ROOT_DIR"
cp -v "$FIRMWARE_SOURCE_PATH" "$TFTP_ROOT_DIR/$FIRMWARE_TFTP_NAME"

echo
echo "Firmware kopyalandı: $TFTP_ROOT_DIR/$FIRMWARE_TFTP_NAME"
echo
echo "Kontrol listesi:"
echo "  1. TFTP server'ının çalıştığını doğrula (örn: systemctl status tftpd-hpa)"
echo "  2. TFTP server'ının kök dizininin '$TFTP_ROOT_DIR' olduğunu doğrula"
echo "  3. Bilgisayarının router'a bakan ağ arayüzüne statik IP ver: $TFTP_SERVER_IP"
echo "  4. Router'ı Ethernet ile bu arayüze bağla"
