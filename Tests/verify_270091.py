#!/usr/bin/env python3
"""Read-only verification of the pristine 4.1.15.11 ARM64 patch locations."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("binary", type=Path, help="Path to pristine wechat.dylib or its ARM64 slice")
args = parser.parse_args()
data = args.binary.read_bytes()
magic = struct.unpack_from(">I", data)[0]
if magic in (0xCAFEBABE, 0xBEBAFECA):
    endian = ">" if magic == 0xCAFEBABE else "<"
    count = struct.unpack_from(endian + "I", data, 4)[0]
    slices = []
    for i in range(count):
        cpu, _, off, size, _ = struct.unpack_from(endian + "IIIII", data, 8 + i * 20)
        if cpu == 0x0100000C:
            assert off + size <= len(data), "Truncated ARM64 slice"
            slices.append(data[off:off + size])
    assert len(slices) == 1, "Expected one ARM64 slice"
    data = slices[0]
assert struct.unpack_from("<II", data) == (0xFEEDFACF, 0x0100000C), "Expected ARM64 Mach-O"
assert hashlib.sha256(data).hexdigest() == "b34e39af3dca3bba09342682998260b608dec2abdf75cc43d0c81b7a49a8a186", "Different build or already modified"
segments = []
pos = 32
for _ in range(struct.unpack_from("<I", data, 16)[0]):
    cmd, size = struct.unpack_from("<II", data, pos)
    assert size >= 8 and pos + size <= len(data)
    if cmd == 0x19:
        va, _, off, count = struct.unpack_from("<QQQQ", data, pos + 24)
        segments.append((va, off, count))
    pos += size


def offset(va):
    for base, off, count in segments:
        if base <= va < base + count:
            return off + va - base
    raise AssertionError("Address not backed by file data")


hits = []
pos = 0
while True:
    pos = data.find(bytes.fromhex("40100034"), pos)
    if pos < 0:
        break
    if pos % 4 == 0 and data[pos + 0x7A0:pos + 0x7A4] == bytes.fromhex("60E600F9"):
        hits.append(pos)
    pos += 1
assert hits == [offset(0x4BBEA28)], "Revoke signature is not unique"
root = Path(__file__).resolve().parents[1]
configs = json.loads((root / "config.json").read_text())
config = next(c for c in configs if c["version"] == "270091")
assert [t["identifier"] for t in config["targets"]] == ["revoke", "multiInstance"]
for target in config["targets"]:
    for entry in target["entries"]:
        start = offset(int(entry["addr"], 16))
        expected = bytes.fromhex(entry["expected"])
        assert data[start:start + len(expected)] == expected, target["identifier"]
original, patched = (struct.unpack("<I", bytes.fromhex(x))[0] for x in ("40100034", "82000014"))
assert original & 0xFF00001F == 0x34000000  # cbz w0
assert patched & 0xFC000000 == 0x14000000  # unconditional b
assert ((original >> 5) & 0x7FFFF) == (patched & 0x3FFFFFF)
assert 0x4BBEA28 + ((patched & 0x3FFFFFF) << 2) == 0x4BBEC30
assert data[offset(0x4BBE7B8):offset(0x4BBE7B8) + 4] == bytes.fromhex("F85FBCA9")
assert data[offset(0x8717760):offset(0x8717760) + 8] == b"newmsgid"
assert data[offset(0x4BBF1C8):offset(0x4BBF1C8) + 4] == bytes.fromhex("60E600F9")
print("PASS: pristine 270091 SHA256, unique revoke anchors, actual config original bytes, branch destination, newmsgid store")
