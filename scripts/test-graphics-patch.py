#!/usr/bin/env python3
"""Failure-path and ASAR round-trip checks. Never read a user profile."""
import hashlib
import importlib.util
import json
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("patch", Path(__file__).with_name("patch-graphics.py"))
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)
CONFIGURE = '''function configureLinuxGpu(options) {
  const mode = resolveLinuxGpuMode({ platform: process.platform, server: options.server, disableGpu: process.env.OPENBOT_DISABLE_GPU });
  if (mode.reason === "not-linux") return mode;
  if (!mode.hardwareAcceleration) {
    app.disableHardwareAcceleration();
    return mode;
  }
  writeGpuFailure(startPath, chromiumMajor);
  app.on("child-process-gone", () => {
    writeGpuFailure(crashPath, chromiumMajor);
  });
  return mode;
}'''


class PatchTest(unittest.TestCase):
    def test_policy_drift_and_duplicate_patch_fail(self):
        original = patch.EXPECTED_RESOLVER + "\n" + CONFIGURE
        updated = patch.patch_main(original)
        self.assertIn('server: options.server && process.env.OPENBOT_SERVER_GPU !== "1",', updated)
        self.assertIn(patch.EXPECTED_RESOLVER, updated)
        with self.assertRaises(ValueError):
            patch.patch_main(updated)
        with self.assertRaises(ValueError):
            patch.patch_main(original.replace('reason: "gpu-process-crash"', 'reason: "changed"'))
        with self.assertRaises(ValueError):
            patch.patch_main(original.replace('writeGpuFailure(crashPath, chromiumMajor);', ''))

    def test_archive_round_trip_preserves_other_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            contents = {
                "package.json": json.dumps({"name": "openbot", "version": "0.52.1", "main": "./out/main/index.js"}).encode(),
                "out/main/index.js": (patch.EXPECTED_RESOLVER + "\n" + CONFIGURE).encode(),
                "untouched.txt": b"unchanged public fixture\n",
            }
            header = {"files": {}}
            offset = 0
            for name, data in contents.items():
                node = header
                parts = name.split('/')
                for part in parts[:-1]:
                    node = node['files'].setdefault(part, {"files": {}})
                digest = hashlib.sha256(data).hexdigest()
                node['files'][parts[-1]] = {"size": len(data), "offset": str(offset), "integrity": {
                    "algorithm": "SHA256", "hash": digest, "blockSize": 4194304, "blocks": [digest]}}
                offset += len(data)
            header['files']['native.node'] = {"size": 100, "unpacked": True}
            raw = json.dumps(header).encode()
            pad = b'\0' * (-len(raw) % 4)
            size = 8 + len(raw) + len(pad)
            source = root / 'original.asar'
            source.write_bytes(struct.pack('<IIII', 4, size, size - 4, len(raw)) + raw + pad + b''.join(contents.values()))
            output = root / 'patched.asar'
            subprocess.run(['python3', str(Path(patch.__file__)), str(source), str(output)], check=True)
            stream, actual, start = patch.read_archive(output)
            for name in ('package.json', 'untouched.txt'):
                self.assertEqual(patch.read_entry(stream, start, patch.entry(actual, name)), contents[name])
            changed = patch.read_entry(stream, start, patch.entry(actual, 'out/main/index.js')).decode()
            self.assertIn('configureOpenBotServerGraphics(app, options, mode);', changed)
            self.assertEqual(actual['files']['native.node'], header['files']['native.node'])
            stream.close()


if __name__ == '__main__':
    unittest.main()
