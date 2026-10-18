"""Host checks for product relocation and build-free lane commands."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("compatibility", Path(__file__).with_name("compatibility.py"))
compatibility = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compatibility)


class CompatibilityTests(unittest.TestCase):
    def test_relocated_products_preserve_bundle_and_relative_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "Products"
            source.mkdir()
            bundle = source / "Debug-iphonesimulator/One.app"
            bundle.mkdir(parents=True)
            (bundle / "One").write_bytes(b"signed-binary")
            run = {"OneUITests": {"UITargetAppPath": "__TESTROOT__/Debug-iphonesimulator/One.app",
                                  "TestBundlePath": "__TESTHOST__/PlugIns/OneUITests.xctest"}}
            (source / "One.xctestrun").write_bytes(plistlib.dumps(run))
            relocated = compatibility.copy_products(source, root / "lane/Products")
            self.assertEqual(plistlib.loads(relocated.read_bytes()), run)
            self.assertEqual((relocated.parent / "Debug-iphonesimulator/One.app/One").read_bytes(), b"signed-binary")
            with self.assertRaises(FileExistsError):
                compatibility.copy_products(source, relocated.parent)

    def test_absolute_build_paths_are_rejected_before_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "One.xctestrun").write_bytes(plistlib.dumps({"OneUITests": {"TestHostPath": "/old/cache/Runner.app"}}))
            with self.assertRaisesRegex(ValueError, "Non-relocatable"):
                compatibility.copy_products(root, root / "destination")
            self.assertFalse((root / "destination").exists())

    def test_lane_uses_copied_products_without_building(self):
        command = compatibility.e2e.ui_command(["OneUITests/ClockTests/testScrubbing"], "lane-id", Path("cache"), Path("output"), Path("copy/One.xctestrun"))
        self.assertEqual(command[1], "test-without-building")
        self.assertNotIn("-project", command)
        self.assertIn("copy/One.xctestrun", command)
        self.assertIn("platform=iOS Simulator,id=lane-id", command)
        self.assertIn("-only-testing:OneUITests/ClockTests/testScrubbing", command)


if __name__ == "__main__":
    unittest.main()
