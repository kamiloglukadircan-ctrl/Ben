#!/usr/bin/env bash
# Config'teki BACKUP_PARTITIONS listesi için, OEM firmware'in seri
# konsolundaki (root shell) prompta yapıştırılacak yedekleme komutlarını
# üretir. Her partition ikili (binary) içeriğini hex'e çevirip, ayırt edici
# START/END etiketleriyle çevrelenmiş şekilde ekrana basar — bu çıktı
# capture-serial-log.sh ile kaydedilen log dosyasından, extract-backup.sh
# tarafından geri ikili dosyaya çevrilir.
#
# Kullanım: ./print-backup-steps.sh ../config/<cihaz>.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
require_config "${1:-}"

if [[ -z "${BACKUP_PARTITIONS:-}" ]]; then
    echo "Config'te BACKUP_PARTITIONS boş." >&2
    echo "Önce router'da 'cat /proc/mtd' çalıştırıp partition isimlerini gör," >&2
    echo "sonra config dosyasına BACKUP_PARTITIONS=\"isim1 isim2 ...\" olarak ekle." >&2
    exit 1
fi

cat <<EOF
============================================================
 $DEVICE_NAME — OEM Firmware Yedekleme Adımları
============================================================
Bu adımlar OEM firmware ÇALIŞIRKEN, seri konsoldan login olduğun
root shell'de ($ROUTER_IP değil, doğrudan seri terminaldeki prompt)
çalıştırılır. Flash'a hiçbir şey YAZMAZ, sadece okur.

0) ÖNCE bu oturumu logla (ayrı bir terminalde, bu script'in yerine):
     ./scripts/capture-serial-log.sh $1
   (Bu, normal connect-serial.sh ile aynı işi yapar ama tüm çıktıyı da
   bir dosyaya kaydeder — aşağıdaki komutları o oturumda çalıştıracaksın.)

1) Partition isimlerini doğrula:
   cat /proc/mtd

   BACKUP_PARTITIONS içindeki isimlerin ("${BACKUP_PARTITIONS}") çıktıda
   tırnak içinde göründüğünü kontrol et. Uyuşmuyorsa config dosyasını
   düzelt ve bu script'i tekrar çalıştır.

2) Aşağıdaki komutları TEK TEK, sırayla seri konsola yapıştır:

EOF

for part in $BACKUP_PARTITIONS; do
cat <<EOF
   --- $part ---
   M=\$(awk -F: '/"$part"/{print \$1}' /proc/mtd); echo "===BACKUP:$part:START==="; od -A n -v -t x1 /dev/\$M | tr -d ' \n'; echo; echo "===BACKUP:$part:END==="

EOF
done

cat <<EOF
3) Tüm partition'lar için yukarıdakileri çalıştırdıktan sonra seri
   oturumdan çık (picocom: Ctrl-A Ctrl-X / minicom: Ctrl-A X).

4) Log dosyasından gerçek .bin dosyalarını çıkar:
   ./scripts/extract-backup.sh $1 <capture-serial-log.sh'ın verdiği log yolu>

============================================================
NOT: Bu yöntem sadece küçük partition'lar (radio/config/romfile gibi,
genelde 64-256KB) için pratiktir. 8MB'lık tüm flash'ı bu yolla çekmek
seri hız yüzünden çok uzun sürer — tüm firmware'i yedeklemek istersen
donanımsal bir SPI programlayıcı (BusPirate, Raspberry Pi SPI) kullanman
gerekir, bkz. ToH sayfasındaki "Debricking" bölümü.
============================================================
EOF
