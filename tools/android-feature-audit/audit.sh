#!/usr/bin/env bash
# Bağlı Android telefonun (örn. Vivo Y21s) hangi özelliklerinin açık / kapalı /
# kısıtlı olduğunu ROOT GEREKTİRMEDEN, sadece ADB ile okur. Telefonda hiçbir
# ayarı DEĞİŞTİRMEZ; yalnızca okuma komutları çalıştırır.
#
# Gereksinim: adb (bilgisayarda platform-tools ya da Termux'ta android-tools)
# ve yetkilendirilmiş bir cihaz. adb yoksa telefonda (Termux) sınırlı yerel
# modda çalışır.
#
# Kullanım: ./audit.sh [çıktı_klasörü]
#   Varsayılan çıktı klasörü: ./audit-<model>-<tarih>

set -u

state=""
command -v adb >/dev/null 2>&1 && state="$(adb get-state 2>/dev/null || true)"

if [[ "$state" == "device" ]]; then
    sh_() { adb shell "$@" 2>&1 | tr -d '\r'; }
elif command -v getprop >/dev/null 2>&1; then
    # Telefonun kendisinde (Termux) ADB bağlantısı olmadan çalışıyoruz.
    # Uygulama yetkisiyle getprop ve pm çalışır; dumpsys/settings/device_config
    # çoğunlukla "Permission Denial" verir. Tam sonuç için Termux içinden
    # kablosuz hata ayıklama ile adb'ye bağlanın (README'ye bakın).
    echo "UYARI: adb cihazı yok, YEREL (sınırlı) modda çalışılıyor." >&2
    sh_() { "$@" 2>&1; }
else
    echo "HATA: Yetkilendirilmiş cihaz yok (durum: ${state:-yok})." >&2
    echo "Telefonda: Geliştirici seçenekleri > USB/Kablosuz hata ayıklama, sonra 'izin ver'." >&2
    exit 1
fi
model="$(sh_ getprop ro.product.model | tr ' /' '__')"
out="${1:-./audit-${model:-android}-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$out"
echo "== Çıktı klasörü: $out =="

# name|komut  -> her biri ayrı dosyaya
dump() {
    local name="$1"; shift
    printf '  %-22s ' "$name"
    sh_ "$@" > "$out/$name.txt"
    echo "($(wc -l < "$out/$name.txt") satır)"
}

echo "== Ham veriler toplanıyor =="
dump props              getprop
dump features           pm list features
dump packages_all       pm list packages -f -u
dump packages_enabled   pm list packages -e
dump packages_disabled  pm list packages -d
dump packages_installed pm list packages
dump settings_global    settings list global
dump settings_secure    settings list secure
dump settings_system    settings list system
dump device_config      device_config list
dump camera             dumpsys media.camera
dump carrier_config     dumpsys carrier_config
dump telephony_ims      dumpsys telephony.registry
dump display            dumpsys display
dump sensors            dumpsys sensorservice
dump nfc                dumpsys nfc
dump wifi_caps          dumpsys wifi
dump bluetooth          dumpsys bluetooth_manager
dump battery            dumpsys battery
dump thermal            dumpsys thermalservice
dump codecs             dumpsys media.player

# Kaldırılmış (ama sistemde duran) paketler = -u listesinde olup normal listede olmayanlar
comm -23 <(sed 's/^package:.*=//; s/^package://' "$out/packages_all.txt" | sort -u) \
         <(sed 's/^package://' "$out/packages_installed.txt" | sort -u) \
         > "$out/packages_uninstalled_for_user.txt"

p() { grep -m1 -F "[$1]" "$out/props.txt" | sed 's/.*: \[\(.*\)\]/\1/'; }
has_feature() { grep -qE "^feature:${1//./\\.}(=.*)?$" "$out/features.txt" && echo "VAR" || echo "YOK"; }

S="$out/OZET.txt"
{
echo "=== CİHAZ ==="
echo "Model            : $(p ro.product.model) ($(p ro.product.device))"
echo "Bölge/ürün adı   : $(p ro.product.name)  bölge: $(p ro.product.locale) $(p persist.sys.vivo.product.region)$(p ro.product.customize.bbk)"
echo "Android / SDK    : $(p ro.build.version.release) / $(p ro.build.version.sdk)"
echo "Yazılım sürümü   : $(p ro.vivo.os.build.display.id)$(p ro.build.display.id)"
echo "Güvenlik yaması  : $(p ro.build.version.security_patch)"
echo "SoC / platform   : $(p ro.soc.model)$(p ro.board.platform) $(p ro.hardware)"
echo
echo "=== BOOTLOADER / GÜVENLİK ==="
echo "Verified boot    : $(p ro.boot.verifiedbootstate)  (green=kilitli+orijinal)"
echo "Flash kilitli    : $(p ro.boot.flash.locked)  (1=kilitli)"
echo "OEM unlock destek: $(p ro.oem_unlock_supported)  izin: $(p sys.oem_unlock_allowed)"
echo "SELinux          : $(sh_ getenforce)"
echo
echo "=== DONANIM ÖZELLİKLERİ (pm list features) ==="
for f in android.hardware.nfc android.hardware.nfc.hce android.hardware.camera.raw \
         android.hardware.camera.level.full android.hardware.wifi.direct \
         android.hardware.wifi.aware android.hardware.wifi.rtt android.hardware.wifi.passpoint \
         android.hardware.bluetooth_le android.hardware.usb.host android.hardware.consumerir \
         android.hardware.sensor.gyroscope android.hardware.sensor.compass \
         android.hardware.sensor.stepcounter android.hardware.fingerprint \
         android.hardware.telephony.ims android.hardware.opengles.aep \
         android.hardware.vulkan.level android.software.freeform_window_management \
         android.software.picture_in_picture android.hardware.fm; do
    printf '  %-45s %s\n' "$f" "$(has_feature "$f")"
done
echo
echo "=== KAMERA (Camera2 API donanım seviyesi) ==="
echo "  0=LIMITED 1=FULL 2=LEGACY 3=LEVEL_3 4=EXTERNAL"
grep -iE "Camera ID|supportedHardwareLevel|android.info.supportedHardwareLevel" -A1 "$out/camera.txt" \
    | grep -iE "Camera ID|HardwareLevel|^\s*\[?[0-9]" | head -20 | sed 's/^/  /'
echo
echo "=== VoLTE / VoWiFi / IMS ==="
grep -iE "(volte|vowifi|wfc|vilte|ims).*(support|avail|enable)" "$out/props.txt" | sed 's/^/  /'
grep -iE "carrier_volte_available_bool|carrier_wfc_ims_available_bool|carrier_vt_available_bool|editable_enhanced_4g_lte_bool|hide_enhanced_4g_lte_bool" \
    "$out/carrier_config.txt" | sort -u | head -20 | sed 's/^/  /'
echo
echo "=== EKRAN MODLARI ==="
grep -oE "supportedModes=\[[^]]*\]|DisplayModeRecord\{[^}]*\}" "$out/display.txt" | sort -u | head -10 | sed 's/^/  /'
echo
echo "=== 'KAPALI' GÖRÜNEN PROP'LAR (support/enable/feature = 0/false) ==="
grep -iE "(support|enable|feature|_on\]|switch)" "$out/props.txt" \
    | grep -E ": \[(0|false|no|off|disable)\]" | sed 's/^/  /'
echo
echo "=== VIVO'YA ÖZEL PROP'LAR ==="
grep -iE "vivo|bbk|funtouch|originos" "$out/props.txt" | head -80 | sed 's/^/  /'
echo
echo "=== DEVRE DIŞI (disabled) PAKETLER ==="
sed 's/^package:/  /' "$out/packages_disabled.txt"
echo
echo "=== KULLANICI İÇİN KALDIRILMIŞ AMA SİSTEMDE DURAN PAKETLER ==="
sed 's/^/  /' "$out/packages_uninstalled_for_user.txt"
echo
echo "=== ÖZELLİK BAYRAKLARI (device_config, 'false' olanlar, ilk 60) ==="
grep -E "=false$" "$out/device_config.txt" | head -60 | sed 's/^/  /'
} > "$S"

echo
echo "== Özet: $S =="
echo "Ham veriler aynı klasörde (props.txt, features.txt, camera.txt ...)."
