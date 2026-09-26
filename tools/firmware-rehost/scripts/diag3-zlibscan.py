#!/usr/bin/env python3
"""
Tum imajda zlib akisi (deflate) tarayici.

gzip-sikistirilmis bir squashfs yuzlerce zlib bloku icerir; her biri
0x78 ile baslar (0x78 0x9c / 0x78 0xda / 0x78 0x01 / 0x78 0x5e).
Bu script imaji identity / swap16 / swap32 donusumleri altinda tarar,
her birinde zlib basligi sayar ve gercekten acilabilen (valid) olanlari
dogrular. En cok gecerli akis hangi donusumde ise, veri o byte-order'dadir.

Kullanim: python3 diag3-zlibscan.py <rootfs.sqfs>
"""
import sys, array, zlib

if len(sys.argv) < 2:
    print("Kullanim: python3 diag3-zlibscan.py <rootfs.sqfs>")
    sys.exit(1)

data = open(sys.argv[1], "rb").read()
# Sadece squashfs bolgesini tara (ilk 16MB yeterli)
data = data[:16 * 1024 * 1024]
print(f"Taranan boyut: {len(data):,}")

def swap16(buf):
    n = len(buf) & ~1
    a = array.array("H"); a.frombytes(buf[:n]); a.byteswap()
    return bytes(a) + buf[n:]

def swap32(buf):
    n = len(buf) & ~3
    a = array.array("I"); a.frombytes(buf[:n]); a.byteswap()
    return bytes(a) + buf[n:]

transforms = {
    "identity": lambda x: x,
    "swap16": swap16,
    "swap32": swap32,
}

ZLIB_HEADERS = [b"\x78\x01", b"\x78\x5e", b"\x78\x9c", b"\x78\xda"]

for tname, tf in transforms.items():
    buf = tf(data)
    total = 0
    valid = 0
    örnekler = []
    for hdr in ZLIB_HEADERS:
        pos = 0
        while True:
            i = buf.find(hdr, pos)
            if i < 0:
                break
            total += 1
            # Gercekten aciliyor mu?
            try:
                d = zlib.decompressobj()
                out = d.decompress(buf[i:i+4096])
                if len(out) > 0:
                    valid += 1
                    if len(örnekler) < 5:
                        örnekler.append(f"0x{i:x}(+{len(out)}b)")
            except Exception:
                pass
            pos = i + 1
    print(f"\n[{tname}] zlib basligi: {total} adet, GECERLI (acilan): {valid}")
    if örnekler:
        print(f"   ornek konumlar: {', '.join(örnekler)}")

print("\n=== SONUC ===")
print("En cok GECERLI akis hangi donusumde ise, veri bolgesi o byte-order'dadir.")
print("O zaman tum imaji o donusumle cevirip unsquashfs calistiracagiz.")
