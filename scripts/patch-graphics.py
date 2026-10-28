#!/usr/bin/env python3
"""Patch the released Linux ASAR. Keep the binary, fuses and all other files intact."""
import hashlib
import json
import os
import re
import shutil
import struct
import sys
from pathlib import Path

EXPECTED_RESOLVER = '''function resolveLinuxGpuMode(input) {
  if (input.platform !== "linux") return { hardwareAcceleration: true, reason: "not-linux" };
  if (input.server) return { hardwareAcceleration: false, reason: "server" };
  if (input.disableGpu === "1") return { hardwareAcceleration: false, reason: "environment-off" };
  if (input.disableGpu === "0") return { hardwareAcceleration: true, reason: "environment-on" };
  if (input.crash?.chromium === input.chromiumMajor)
    return { hardwareAcceleration: false, reason: "gpu-process-crash" };
  if (input.unfinishedStart?.chromium === input.chromiumMajor)
    return { hardwareAcceleration: false, reason: "unfinished-start" };
  return { hardwareAcceleration: true, reason: "default" };
}'''


def function(text, name):
    found = re.findall(r"function " + name + r"\([^\n]*\) \{\n.*?\n\}", text, re.S)
    if len(found) != 1:
        raise ValueError(f"Expected one {name} function; upstream requires review")
    return found[0]


def patch_main(text):
    resolver = function(text, "resolveLinuxGpuMode")
    if re.sub(r"\s+", "", resolver) != re.sub(r"\s+", "", EXPECTED_RESOLVER):
        raise ValueError("GPU fallback policy changed; upstream requires review")
    configure = function(text, "configureLinuxGpu")
    required = [
        'server: options.server,',
        'if (mode.reason === "not-linux") return mode;',
        'app.disableHardwareAcceleration();',
        'writeGpuFailure(startPath, chromiumMajor);',
        'app.on("child-process-gone",',
        'writeGpuFailure(crashPath, chromiumMajor);',
    ]
    if any(configure.count(part) != 1 for part in required):
        raise ValueError("GPU configuration changed; upstream requires review")
    if "configureOpenBotServerGraphics" in text or "OPENBOT_SERVER_GPU" in configure:
        raise ValueError("Refusing an already patched application")
    updated = configure.replace(
        'server: options.server,',
        'server: options.server && process.env.OPENBOT_SERVER_GPU !== "1",',
    ).replace(
        'if (mode.reason === "not-linux") return mode;',
        'if (mode.reason === "not-linux") return mode;\n'
        '  configureOpenBotServerGraphics(app, options, mode);',
    )
    prefix = 'import { configureOpenBotServerGraphics } from "/usr/local/lib/openbot-graphics/runtime.mjs";\n'
    return prefix + text.replace(configure, updated, 1)


def read_archive(path):
    stream = path.open("rb")
    first = stream.read(16)
    marker, header_size, payload_size, json_size = struct.unpack("<IIII", first)
    if marker != 4 or header_size != payload_size + 4 or not 0 < json_size < 64 * 1024 * 1024:
        raise ValueError("Unexpected ASAR format")
    header = json.loads(stream.read(json_size))
    return stream, header, 8 + header_size


def entry(header, name):
    current = header
    for part in name.split("/"):
        current = current["files"][part]
    if current.get("unpacked") or "link" in current:
        raise ValueError("Expected a packed regular application file")
    return current


def read_entry(stream, start, info):
    stream.seek(start + int(info["offset"]))
    data = stream.read(info["size"])
    if len(data) != info["size"]:
        raise ValueError("Incomplete ASAR file")
    integrity = info.get("integrity")
    if not integrity or integrity["algorithm"] != "SHA256" or hashlib.sha256(data).hexdigest() != integrity["hash"]:
        raise ValueError("Original application integrity check failed")
    return data


def main():
    source, output = map(Path, sys.argv[1:3])
    stream, header, start = read_archive(source)
    package = json.loads(read_entry(stream, start, entry(header, "package.json")))
    if package["name"] != "openbot" or package["main"] != "./out/main/index.js":
        raise ValueError("Unexpected application package")
    info = entry(header, "out/main/index.js")
    original = read_entry(stream, start, info)
    patched = patch_main(original.decode()).encode()
    block_size = info["integrity"]["blockSize"]
    if not isinstance(block_size, int) or not 0 < block_size <= 16 * 1024 * 1024:
        raise ValueError("Unexpected ASAR integrity block size")
    info.update(size=len(patched), offset=str(source.stat().st_size - start), integrity={
        "algorithm": "SHA256", "hash": hashlib.sha256(patched).hexdigest(),
        "blockSize": block_size,
        "blocks": [hashlib.sha256(patched[n:n + block_size]).hexdigest() for n in range(0, len(patched), block_size)],
    })
    raw = json.dumps(header, ensure_ascii=False, separators=(",", ":")).encode()
    padding = b"\0" * (-len(raw) % 4)
    size = 8 + len(raw) + len(padding)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("xb") as target:
        target.write(struct.pack("<IIII", 4, size, size - 4, len(raw)))
        target.write(raw + padding)
        stream.seek(start)
        shutil.copyfileobj(stream, target, 1024 * 1024)
        target.write(patched)
    stream.close()
    os.chmod(output, 0o644)
    check, checked, base = read_archive(output)
    assert read_entry(check, base, entry(checked, "out/main/index.js")) == patched
    check.close()
    if len(sys.argv) > 3:
        Path(sys.argv[3]).write_text(json.dumps({
            "resolver": function(patched.decode(), "resolveLinuxGpuMode"),
            "configure": function(patched.decode(), "configureLinuxGpu"),
        }))
    print(f"Patched OpenBot {package['version']}; GPU crash policy and ASAR integrity metadata retained")


if __name__ == "__main__":
    main()
