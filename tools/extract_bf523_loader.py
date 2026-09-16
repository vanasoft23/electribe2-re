#!/usr/bin/env python3
"""Extract and reconstruct the BF523 boot stream embedded in HACKTRIBE.

The source bytes are read through Ghidra MCP's HTTP ``/read_memory`` endpoint.
The script validates the BF52x 16-byte block headers, preserves the original
loader stream, and emits deterministic stage/region images plus a JSON map.

It deliberately does not disassemble anything.  Ghidra's stock distribution
does not include a Blackfin language module, while the installed Analog
Devices GNU toolchain can consume the reconstructed region images directly.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


HEADER = struct.Struct("<IIII")
BOOT_SIGNATURE = 0xAD000000
BOOT_SIGNATURE_MASK = 0xFF000000
BLOCK_TYPE_MASK = 0x000000FF
BLOCK_TYPE_DATA = 0x01
BLOCK_FLAG_MASK = 0x0000FF00
BFLAG_FILL = 0x0100
BFLAG_INIT = 0x0800
BFLAG_IGNORE = 0x1000
BFLAG_FIRST = 0x4000
BFLAG_FINAL = 0x8000


@dataclass(frozen=True)
class MemoryRegion:
    name: str
    base: int
    end: int

    @property
    def size(self) -> int:
        return self.end - self.base


BF523_REGIONS = (
    MemoryRegion("external_sdram", 0x00000000, 0x02000000),
    MemoryRegion("l1_data_a", 0xFF800000, 0xFF804000),
    MemoryRegion("l1_data_b", 0xFF900000, 0xFF904000),
    MemoryRegion("l1_instruction", 0xFFA00000, 0xFFA0C000),
)


@dataclass(frozen=True)
class BootRecord:
    index: int
    stream_offset: int
    block_code: int
    target: int
    byte_count: int
    argument: int
    payload_offset: int
    stored_size: int

    @property
    def flags(self) -> int:
        return self.block_code & BLOCK_FLAG_MASK

    @property
    def is_fill(self) -> bool:
        return bool(self.flags & BFLAG_FILL)

    @property
    def end_offset(self) -> int:
        return self.payload_offset + self.stored_size

    def to_json(self, stream: bytes) -> dict[str, object]:
        payload = stream[self.payload_offset : self.end_offset]
        return {
            "index": self.index,
            "stream_offset": f"0x{self.stream_offset:X}",
            "block_code": f"0x{self.block_code:08X}",
            "flags": f"0x{self.flags:04X}",
            "target": f"0x{self.target:08X}",
            "byte_count": self.byte_count,
            "argument": f"0x{self.argument:08X}",
            "payload_offset": f"0x{self.payload_offset:X}",
            "stored_size": self.stored_size,
            "payload_sha256": hashlib.sha256(payload).hexdigest() if payload else None,
        }


def parse_int(value: str) -> int:
    return int(value, 0)


def fetch_memory(base_url: str, program: str, address: int, length: int, chunk_size: int) -> bytes:
    result = bytearray()
    for offset in range(0, length, chunk_size):
        requested = min(chunk_size, length - offset)
        query = urllib.parse.urlencode(
            {
                "address": f"0x{address + offset:X}",
                "length": requested,
                "program": program,
            }
        )
        url = f"{base_url.rstrip('/')}/read_memory?{query}"
        with urllib.request.urlopen(url, timeout=30) as response:
            reply = json.load(response)
        data = bytes(reply["data"])
        if len(data) != requested:
            raise RuntimeError(
                f"short MCP read at 0x{address + offset:08X}: "
                f"requested {requested}, received {len(data)}"
            )
        result.extend(data)
    return bytes(result)


def parse_records(stream: bytes) -> list[BootRecord]:
    records: list[BootRecord] = []
    offset = 0
    while offset < len(stream):
        if len(stream) - offset < HEADER.size:
            raise ValueError(f"truncated block header at stream offset 0x{offset:X}")
        block_code, target, byte_count, argument = HEADER.unpack_from(stream, offset)
        if block_code & BOOT_SIGNATURE_MASK != BOOT_SIGNATURE:
            raise ValueError(
                f"bad BF52x header signature at stream offset 0x{offset:X}: "
                f"0x{block_code:08X}"
            )
        if block_code & BLOCK_TYPE_MASK != BLOCK_TYPE_DATA:
            raise ValueError(
                f"unsupported BF52x block type at stream offset 0x{offset:X}: "
                f"0x{block_code & BLOCK_TYPE_MASK:02X}"
            )
        flags = block_code & BLOCK_FLAG_MASK
        stored_size = 0 if flags & BFLAG_FILL else byte_count
        payload_offset = offset + HEADER.size
        end_offset = payload_offset + stored_size
        if end_offset > len(stream):
            raise ValueError(
                f"block {len(records)} overruns stream: end 0x{end_offset:X}, "
                f"stream length 0x{len(stream):X}"
            )
        records.append(
            BootRecord(
                index=len(records),
                stream_offset=offset,
                block_code=block_code,
                target=target,
                byte_count=byte_count,
                argument=argument,
                payload_offset=payload_offset,
                stored_size=stored_size,
            )
        )
        offset = end_offset
    if offset != len(stream):
        raise AssertionError("parser did not consume the exact stream")
    return records


def find_region(address: int, size: int) -> MemoryRegion:
    end = address + size
    for region in BF523_REGIONS:
        if region.base <= address and end <= region.end:
            return region
    raise ValueError(f"write 0x{address:08X}-0x{end - 1:08X} is outside known BF523 memory regions")


def merged_ranges(ranges: Iterable[tuple[int, int]]) -> list[tuple[int, int]]:
    merged: list[list[int]] = []
    for start, end in sorted(ranges):
        if not merged or start > merged[-1][1]:
            merged.append([start, end])
        else:
            merged[-1][1] = max(merged[-1][1], end)
    return [(start, end) for start, end in merged]


def reconstruct_stage(
    stage_name: str,
    records: Iterable[BootRecord],
    stream: bytes,
    output_dir: Path,
) -> dict[str, object]:
    images: dict[str, bytearray] = {}
    writes: dict[str, list[tuple[int, int, int]]] = {}
    overlaps: list[dict[str, object]] = []

    for record in records:
        if record.byte_count == 0:
            continue
        region = find_region(record.target, record.byte_count)
        image = images.setdefault(region.name, bytearray(region.size))
        prior_writes = writes.setdefault(region.name, [])
        start = record.target - region.base
        end = start + record.byte_count
        for prior_start, prior_end, prior_index in prior_writes:
            overlap_start = max(start, prior_start)
            overlap_end = min(end, prior_end)
            if overlap_start < overlap_end:
                overlaps.append(
                    {
                        "record": record.index,
                        "overwrites_record": prior_index,
                        "region": region.name,
                        "start": f"0x{region.base + overlap_start:08X}",
                        "end_exclusive": f"0x{region.base + overlap_end:08X}",
                    }
                )
        prior_writes.append((start, end, record.index))
        if record.is_fill:
            if record.byte_count % 4:
                raise ValueError(
                    f"fill block {record.index} has non-dword byte count "
                    f"0x{record.byte_count:X}"
                )
            image[start:end] = struct.pack("<I", record.argument) * (
                record.byte_count // 4
            )
        else:
            payload = stream[record.payload_offset : record.end_offset]
            if len(payload) != record.byte_count:
                raise AssertionError(f"stored payload mismatch in block {record.index}")
            image[start:end] = payload

    artifacts: list[dict[str, object]] = []
    for region in BF523_REGIONS:
        if region.name not in images:
            continue
        ranges = merged_ranges((start, end) for start, end, _ in writes[region.name])
        low = min(start for start, _ in ranges)
        high = max(end for _, end in ranges)
        base = region.base + low
        data = bytes(images[region.name][low:high])
        file_name = f"{stage_name}_{region.name}_{base:08x}.bin"
        (output_dir / file_name).write_bytes(data)
        artifacts.append(
            {
                "file": file_name,
                "region": region.name,
                "base": f"0x{base:08X}",
                "length": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
                "initialized_ranges": [
                    {
                        "start": f"0x{region.base + start:08X}",
                        "end_exclusive": f"0x{region.base + end:08X}",
                    }
                    for start, end in ranges
                ],
            }
        )
    return {"name": stage_name, "artifacts": artifacts, "overlaps": overlaps}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:8089")
    parser.add_argument("--program", default="HACKTRIBE.bin")
    parser.add_argument("--address", type=parse_int, default=0xC00F9E10)
    parser.add_argument("--length", type=parse_int, default=0x422A0)
    parser.add_argument("--chunk-size", type=parse_int, default=0x8000)
    parser.add_argument("--output-dir", type=Path, default=Path("bf523"))
    parser.add_argument(
        "--input",
        type=Path,
        help="Parse an existing loader stream instead of reading Ghidra MCP",
    )
    args = parser.parse_args()

    output_dir: Path = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    if args.input:
        stream = args.input.read_bytes()
    else:
        stream = fetch_memory(args.url, args.program, args.address, args.length, args.chunk_size)
    if len(stream) != args.length:
        raise ValueError(f"expected 0x{args.length:X} bytes, received 0x{len(stream):X}")

    records = parse_records(stream)
    init_record = next((record for record in records if record.flags & BFLAG_INIT), None)
    final_record = next((record for record in records if record.flags & BFLAG_FINAL), None)
    first_records = [record for record in records if record.flags & BFLAG_FIRST]
    if init_record is None or final_record is None or len(first_records) != 2:
        raise ValueError(
            "unexpected multi-application loader layout: expected two FIRST records, "
            "one INIT record, and one FINAL record"
        )
    if final_record.index != len(records) - 1:
        raise ValueError("FINAL record is not the last loader record")

    loader_name = "HACKTRIBE_BF523.ldr"
    (output_dir / loader_name).write_bytes(stream)

    init_records = records[first_records[0].index + 1 : init_record.index]
    app_records = records[first_records[1].index + 1 : final_record.index]
    stages = [
        reconstruct_stage("init", init_records, stream, output_dir),
        reconstruct_stage("app", app_records, stream, output_dir),
    ]

    flag_counts: dict[str, int] = {}
    for record in records:
        key = f"0x{record.flags:04X}"
        flag_counts[key] = flag_counts.get(key, 0) + 1
    manifest = {
        "source": {
            "program": args.program,
            "address": f"0x{args.address:08X}",
            "length": len(stream),
            "sha256": hashlib.sha256(stream).hexdigest(),
            "file": loader_name,
        },
        "format": {
            "header_size": HEADER.size,
            "endianness": "little",
            "signature": "0xAD",
            "record_count": len(records),
            "flag_counts": flag_counts,
            "stored_header_bytes": len(records) * HEADER.size,
            "stored_payload_bytes": sum(record.stored_size for record in records),
            "declared_bytes": sum(record.byte_count for record in records),
        },
        "special_records": {
            "first": [record.index for record in first_records],
            "init": init_record.index,
            "final": final_record.index,
            "init_entry": f"0x{init_record.target:08X}",
            "application_entry": f"0x{final_record.target:08X}",
        },
        "records": [record.to_json(stream) for record in records],
        "stages": stages,
    }
    manifest_path = output_dir / "loader_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    print(f"Extracted {len(stream):,} bytes to {output_dir / loader_name}")
    print(f"Validated {len(records)} BF52x loader headers; exact end 0x{len(stream):X}")
    print(f"INIT entry: 0x{init_record.target:08X}")
    print(f"Application entry: 0x{final_record.target:08X}")
    for stage in stages:
        for artifact in stage["artifacts"]:
            print(
                f"{stage['name']}: {artifact['file']} @ {artifact['base']} "
                f"({artifact['length']:,} bytes)"
            )


if __name__ == "__main__":
    main()
