#!/usr/bin/env python3
"""Generiše placeholder ikone za browser ekstenziju (crvena „pulse" tačka na providnoj pozadini).

Samo Python stdlib (zlib, struct) — bez Pillow. Pokreni iz root-a repo-a:
    python3 scripts/gen-extension-icons.py
Rezultat: extension/icons/icon{16,48,128}.png
"""
import os
import struct
import zlib

DOT = (0xD0, 0x34, 0x2C)  # #d0342c, ista crvena kao Options primary dugme


def png(size: int) -> bytes:
    cx = cy = (size - 1) / 2.0
    r = size * 0.42
    rows = bytearray()
    for y in range(size):
        rows.append(0)  # filter type 0 po redu
        for x in range(size):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            # Anti-aliasing: alfa opada na ivici kruga (1px prelaz).
            a = max(0.0, min(1.0, r - d))
            alpha = int(round(a * 255))
            rows.extend((DOT[0], DOT[1], DOT[2], alpha))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)  # 8-bit RGBA
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
            + chunk(b"IEND", b""))


def main():
    out = os.path.join(os.path.dirname(__file__), "..", "extension", "icons")
    os.makedirs(out, exist_ok=True)
    for size in (16, 48, 128):
        path = os.path.join(out, f"icon{size}.png")
        with open(path, "wb") as f:
            f.write(png(size))
        print("wrote", os.path.relpath(path))


if __name__ == "__main__":
    main()
