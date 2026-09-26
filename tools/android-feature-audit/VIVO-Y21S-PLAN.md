# Vivo Y21s (V2110) — bulgular ve bootloader planı

## Termux taramasından çıkanlar (Android 13 / Funtouch OS 13, 2110_TR)
- Bootloader: kilitli (`ro.boot.flash.locked=1`, `verifiedbootstate=green`).
  Geliştirici seçeneklerinde "OEM kilit açma" anahtarı açıldı (tek başına bir şey açmaz).
- VoLTE açık; Wi-Fi Araması menüsü var (Ağ ve İnternet > SIM kart ve mobil ağ).
- NFC: yazılımda SN110 ayarları var ama ayar sayfası yok → çip yok.
- OTG var, 5 dk kullanılmayınca kendini kapatıyor.
- RAM 4 GB + 1 GB genişletilmiş.
- Fabrikada kapalı (`ro.*`, root olmadan değişmez): MediaTek PQ özellikleri
  (`ro.vendor.pq.mtk_*_support=0`), `ai_charge_support=0`, `displayp3.support=0`,
  DC karartma, VoNR.
- Açık: KTV/karaoke modu, oyun ses efektleri.

## Bootloader denemesi (Linux Mint, mtkclient)
Uyarı: kilit açma TÜM verileri siler; brick riski var. Fotoğrafları önce yedekleyin.

### 1) Kurulum
```bash
sudo apt update
sudo apt install -y git python3-pip python3-venv libusb-1.0-0 libfuse2 adb fastboot
git clone --recursive https://github.com/bkerler/mtkclient
cd mtkclient
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
pip install .
sudo cp mtkclient/Setup/Linux/*.rules /etc/udev/rules.d/
sudo udevadm control -R
sudo usermod -aG dialout,plugdev $USER
```
Bilgisayarı yeniden başlatın.

### 2) Bağlantı testi (hiçbir şeyi değiştirmez)
```bash
cd ~/mtkclient && source venv/bin/activate
python3 mtk.py printgpt
```
Telefon kapalıyken Ses+ ve Ses− basılı tutup kabloyu takın.
Bölüm listesi gelirse devam; gelmezse Vivo açığı kapatmış demektir, burada durun.

### 3) Tam yedek (ZORUNLU — nvram/nvdata = IMEI)
```bash
python3 mtk.py rl yedek
```
`yedek/` klasörünü başka bir diske de kopyalayın.

### 4) Kilit açma — ancak 2 ve 3 başarılıysa
```bash
python3 mtk.py da seccfg unlock
```

### 5) Root — sonraki adım (boot bölümünü Magisk ile yamalama)

Kaynaklar: https://github.com/bkerler/mtkclient (README-INSTALL.md, README-USAGE.md)
