import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import server


class PackTest(unittest.TestCase):
    def test_pack_tracks_source_and_offsets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "project.godot").write_text("config_version=5\n")
            (root / "scripts").mkdir()
            (root / "scenes").mkdir()
            script = root / "scripts" / "example.gd"
            script.write_text("extends Node\n")
            with patch.object(server, "PROJECT", root):
                first = server.make_pack()
                script.write_text("extends Node\n# updated\n")
                second = server.make_pack()
                self.assertNotEqual(first, second)
                self.assertEqual(struct.unpack_from("<II", second), (0x43504447, 2))
                count = struct.unpack_from("<I", second, 96)[0]
                position = 100
                unpacked = {}
                for _ in range(count):
                    length = struct.unpack_from("<I", second, position)[0]
                    position += 4
                    name = second[position:position + length].rstrip(b"\0").decode()
                    position += length
                    offset, size = struct.unpack_from("<QQ", second, position)
                    position += 8 + 8 + 16 + 4
                    unpacked[name] = second[offset:offset + size]
                self.assertEqual(unpacked["scripts/example.gd"], script.read_bytes())
                self.assertEqual(unpacked[".godot/global_script_class_cache.cfg"], b"list=[]\n")
                script.write_text("extends Node\nclass_name Example\n")
                with self.assertRaisesRegex(RuntimeError, "normal Godot export"):
                    server.make_pack()


if __name__ == "__main__":
    unittest.main()
