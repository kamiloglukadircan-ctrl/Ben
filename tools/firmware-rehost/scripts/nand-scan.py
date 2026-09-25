#!/usr/bin/env python3
"""
NAND Döküm Tarayıcı — binwalk alternatifi.

Ham NAND dökümünden OOB verisini temizler ve dosya sistemi imzalarını
(SquashFS, JFFS2, CramFS, uImage, gzip, LZMA, UBI) tarar.

Python 3.8+ ile çalışır, harici bağımlılık gerektirmez.

Kullanım:
    python3 nand-scan.py <dump.bin> [--page 2048] [--oob 64]
    python3 nand-scan.py <dump.bin> --strip-only  # sadece OOB temizle
"""
import sys
import os
import struct
import argparse

SIGNATURES = [
    # (ad, magic_bytes, ofset_açıklama)
    ("SquashFS (LE)",      b"hsqs",           "Little-endian SquashFS"),
    ("SquashFS (BE)",      b"sqsh",           "Big-endian SquashFS"),
    ("SquashFS (shsq)",    b"shsq",           "Broadcom modified SquashFS"),
    ("SquashFS (qshs)",    b"qshs",           "Broadcom modified SquashFS (alt)"),
    ("CramFS (LE)",        b"\x45\x3d\xcd\x28", "CramFS little-endian"),
    ("CramFS (BE)",        b"\x28\xcd\x3d\x45", "CramFS big-endian"),
    ("JFFS2 (LE)",         b"\x85\x19",       "JFFS2 little-endian magic"),
    ("JFFS2 (BE)",         b"\x19\x85",       "JFFS2 big-endian magic"),
    ("UBI EC header",      b"UBI#",           "UBI erase counter header"),
    ("UBI VID header",     b"UBI!",           "UBI volume ID header"),
    ("uImage",             b"\x27\x05\x19\x56", "U-Boot uImage header"),
    ("gzip",               b"\x1f\x8b\x08",   "gzip compressed data"),
    ("LZMA",               b"\x5d\x00\x00",   "LZMA compressed data"),
    ("XZ",                 b"\xfd\x37\x7a\x58\x5a\x00", "XZ compressed data"),
    ("bzip2",              b"\x42\x5a\x68",    "bzip2 compressed data"),
    ("ELF",                b"\x7fELF",         "ELF executable"),
    ("Linux kernel",       b"\x27\x05\x19\x56", "Linux kernel image (uImage)"),
    ("UBIFS",              b"\x31\x18\x10\x06", "UBIFS superblock"),
    ("ext2/3/4",           b"\x53\xef",        "ext2/3/4 superblock (ofset 0x438)"),
    ("Certificate (DER)",  b"\x30\x82",        "DER encoded certificate/key"),
]

SQUASHFS_MAGICS = {b"hsqs", b"sqsh", b"shsq", b"qshs"}


def strip_oob(data: bytes, page_size: int, oob_size: int) -> bytes:
    """NAND dökümünden OOB (spare area) verisini temizler."""
    full_page = page_size + oob_size
    total_pages = len(data) // full_page
    remainder = len(data) % full_page

    clean = bytearray()
    for i in range(total_pages):
        offset = i * full_page
        clean.extend(data[offset:offset + page_size])

    if remainder > page_size:
        offset = total_pages * full_page
        clean.extend(data[offset:offset + page_size])
    elif remainder > 0:
        offset = total_pages * full_page
        clean.extend(data[offset:offset + remainder])

    return bytes(clean)


def detect_oob(data: bytes, page_size: int, oob_size: int) -> bool:
    """Dökümde OOB verisi olup olmadığını kontrol eder."""
    expected_clean = page_size * (len(data) // (page_size + oob_size))
    expected_with_oob = (page_size + oob_size) * (len(data) // (page_size + oob_size))

    # Dosya boyutu tam sayfa+oob'a bölünüyorsa OOB var
    if len(data) % (page_size + oob_size) == 0 and len(data) % page_size != 0:
        return True
    # Dosya boyutu tam sayfa boyutuna bölünüyorsa OOB yok
    if len(data) % page_size == 0:
        return False
    # Belirsiz
    return len(data) > page_size * 1024  # büyük dosyalarda varsayılan: OOB var


def scan_signatures(data: bytes, label: str = "") -> list:
    """Veri bloğu içinde bilinen imzaları tarar."""
    findings = []
    seen_jffs2 = set()  # JFFS2 çok tekrar eder, ilk birkaçını göster

    for i in range(0, len(data) - 8):
        for name, magic, desc in SIGNATURES:
            if data[i:i + len(magic)] == magic:
                # JFFS2 her node'da tekrar eder, sadece ilk 5'i al
                if "JFFS2" in name:
                    region = i // (1024 * 1024)  # MB bazında bölge
                    if region in seen_jffs2:
                        continue
                    seen_jffs2.add(region)
                    if len(seen_jffs2) > 5:
                        continue

                # gzip/LZMA çok yaygın, sadece büyük blokları raporla
                if name in ("gzip", "LZMA", "bzip2"):
                    # Sonraki 1KB'yi kontrol et — gerçek sıkıştırılmış veri mi?
                    block = data[i:i + 1024]
                    zeros = block.count(b'\x00')
                    if zeros > 500:  # çoğunlukla boş — yanlış pozitif
                        continue

                # ext2/3/4 superblock 0x438 ofsetinde olur
                if "ext2" in name and i % 0x400 != 0x38:
                    continue

                # DER sertifika — boyut kontrolü
                if "DER" in name:
                    if i + 4 <= len(data):
                        cert_len = struct.unpack(">H", data[i + 2:i + 4])[0]
                        if cert_len < 64 or cert_len > 8192:
                            continue

                findings.append({
                    "offset": i,
                    "hex": f"0x{i:08X}",
                    "name": name,
                    "desc": desc,
                })

    return findings


def parse_squashfs_header(data: bytes, offset: int) -> dict:
    """SquashFS başlığından detay çıkarır."""
    info = {}
    magic = data[offset:offset + 4]

    if magic in (b"hsqs", b"shsq", b"qshs"):  # little-endian variants
        endian = "<"
    else:  # sqsh = big-endian
        endian = ">"

    try:
        # SquashFS v4 header layout
        inode_count = struct.unpack(endian + "I", data[offset + 4:offset + 8])[0]
        mod_time = struct.unpack(endian + "I", data[offset + 8:offset + 12])[0]
        block_size = struct.unpack(endian + "I", data[offset + 12:offset + 16])[0]
        frag_count = struct.unpack(endian + "I", data[offset + 16:offset + 20])[0]
        compression = struct.unpack(endian + "H", data[offset + 20:offset + 22])[0]
        block_log = struct.unpack(endian + "H", data[offset + 22:offset + 24])[0]
        flags = struct.unpack(endian + "H", data[offset + 24:offset + 26])[0]
        id_count = struct.unpack(endian + "H", data[offset + 26:offset + 28])[0]
        version_major = struct.unpack(endian + "H", data[offset + 28:offset + 30])[0]
        version_minor = struct.unpack(endian + "H", data[offset + 30:offset + 32])[0]
        bytes_used = struct.unpack(endian + "Q", data[offset + 40:offset + 48])[0]

        comp_names = {1: "gzip", 2: "lzma", 3: "lzo", 4: "xz", 5: "lz4", 6: "zstd"}

        info["version"] = f"{version_major}.{version_minor}"
        info["compression"] = comp_names.get(compression, f"bilinmeyen({compression})")
        info["block_size"] = block_size
        info["inode_count"] = inode_count
        info["bytes_used"] = bytes_used
        info["endian"] = "little-endian" if endian == "<" else "big-endian"
    except (struct.error, IndexError):
        pass

    return info


def human_size(size: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024:
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def main():
    parser = argparse.ArgumentParser(description="NAND döküm tarayıcı")
    parser.add_argument("dump", help="NAND döküm dosyası (.bin)")
    parser.add_argument("--page", type=int, default=2048, help="NAND sayfa boyutu (varsayılan: 2048)")
    parser.add_argument("--oob", type=int, default=64, help="OOB (spare) boyutu (varsayılan: 64)")
    parser.add_argument("--strip-only", action="store_true", help="Sadece OOB temizle, tarama yapma")
    parser.add_argument("--no-strip", action="store_true", help="OOB temizleme, doğrudan tara")
    parser.add_argument("--output", "-o", help="Temizlenmiş dökümü kaydet (varsayılan: <dosya>-clean.bin)")
    args = parser.parse_args()

    if not os.path.isfile(args.dump):
        print(f"[HATA] Dosya bulunamadı: {args.dump}", file=sys.stderr)
        sys.exit(1)

    file_size = os.path.getsize(args.dump)
    print(f"[BİLGİ] Dosya: {args.dump}")
    print(f"[BİLGİ] Boyut: {human_size(file_size)} ({file_size:,} byte)")
    print(f"[BİLGİ] NAND: sayfa={args.page}B, OOB={args.oob}B")
    print()

    print("[..] Dosya okunuyor...")
    with open(args.dump, "rb") as f:
        raw_data = f.read()

    # --- OOB tespiti ve temizliği ---
    has_oob = detect_oob(raw_data, args.page, args.oob)

    if args.no_strip:
        clean_data = raw_data
        print("[BİLGİ] OOB temizleme atlandı (--no-strip)")
    elif has_oob:
        total_pages = len(raw_data) // (args.page + args.oob)
        print(f"[BİLGİ] OOB tespit edildi! {total_pages:,} sayfa × ({args.page}+{args.oob}) = {len(raw_data):,}")
        print("[..] OOB temizleniyor...")
        clean_data = strip_oob(raw_data, args.page, args.oob)
        print(f"[OK] Temizlendi: {human_size(len(clean_data))} ({len(clean_data):,} byte)")

        # Temizlenmiş dökümü kaydet
        out_path = args.output or args.dump.rsplit(".", 1)[0] + "-clean.bin"
        with open(out_path, "wb") as f:
            f.write(clean_data)
        print(f"[OK] Temiz döküm kaydedildi: {out_path}")
    else:
        clean_data = raw_data
        print("[BİLGİ] OOB yok, döküm temiz.")

    print()

    if args.strip_only:
        print("[OK] Sadece OOB temizliği istendi, tarama atlanıyor.")
        return

    # --- İmza taraması ---
    print("=" * 60)
    print(" İMZA TARAMASI")
    print("=" * 60)
    print()

    # Önce temiz veriyi tara
    print("[..] Temiz veri taranıyor (bu 1-3 dakika sürebilir)...")
    findings = scan_signatures(clean_data, "temiz")

    if not findings:
        # OOB'suz ham veriyi de dene
        if has_oob:
            print("[UYARI] Temiz veride imza bulunamadı, ham veri de taranıyor...")
            findings = scan_signatures(raw_data, "ham")

    # --- Sonuçları raporla ---
    print()
    if not findings:
        print("=" * 60)
        print(" SONUÇ: HİÇBİR İMZA BULUNAMADI")
        print("=" * 60)
        print()
        print("  Olası nedenler:")
        print("  1) Firmware tamamen şifreli (AES ile koruma)")
        print("  2) Özel/bilinmeyen dosya sistemi formatı")
        print("  3) OOB yapısı farklı (sayfa/oob boyutlarını kontrol et)")
        print("  4) Döküm bozuk veya eksik")
        print()
        print("  Denenecekler:")
        print("  - Farklı sayfa boyutu: --page 4096 --oob 128")
        print("  - strings komutu ile metin arama:")
        print(f"    strings {args.dump} | grep -i 'linux\\|root\\|mount\\|squash'")
        return

    # Bulguları türe göre grupla
    print("=" * 60)
    print(" BULUNAN İMZALAR")
    print("=" * 60)
    print()
    print(f"  {'Ofset':<14} {'Tür':<22} {'Açıklama'}")
    print(f"  {'-'*13} {'-'*21} {'-'*30}")

    squashfs_offsets = []
    for f in findings:
        print(f"  {f['hex']:<14} {f['name']:<22} {f['desc']}")
        if "SquashFS" in f["name"]:
            squashfs_offsets.append(f["offset"])

    print()
    print(f"  Toplam: {len(findings)} imza bulundu")
    print()

    # --- SquashFS detayları ---
    if squashfs_offsets:
        print("=" * 60)
        print(" SQUASHFS DETAYLARI")
        print("=" * 60)
        print()
        for offset in squashfs_offsets:
            info = parse_squashfs_header(clean_data, offset)
            if info:
                print(f"  Ofset: 0x{offset:08X} ({offset:,})")
                print(f"  Sürüm: {info.get('version', '?')}")
                print(f"  Sıkıştırma: {info.get('compression', '?')}")
                print(f"  Blok boyutu: {info.get('block_size', '?')}")
                print(f"  Inode sayısı: {info.get('inode_count', '?')}")
                print(f"  Toplam boyut: {human_size(info.get('bytes_used', 0))}")
                print(f"  Endian: {info.get('endian', '?')}")
                print()

        print("  Çıkarmak için:")
        for offset in squashfs_offsets:
            info = parse_squashfs_header(clean_data, offset)
            size = info.get("bytes_used", 0)
            out_path = args.output or args.dump.rsplit(".", 1)[0] + "-clean.bin"
            if size > 0:
                print(f"    dd if=\"{out_path}\" bs=1 skip={offset} count={size} of=rootfs.sqfs")
            else:
                print(f"    dd if=\"{out_path}\" bs=1 skip={offset} of=rootfs.sqfs")
            print(f"    unsquashfs -d rootfs rootfs.sqfs")
            print(f"    # veya Broadcom özel format için: sasquatch -d rootfs rootfs.sqfs")
            print()

    print("=" * 60)
    print(" BİTTİ")
    print("=" * 60)


if __name__ == "__main__":
    main()
