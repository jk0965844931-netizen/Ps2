import json
import tempfile
import unittest

from ipsx2_optimizer import PRESETS, build_profile, write_profile


class PerformanceProfileTests(unittest.TestCase):
    def test_all_presets_build_with_expected_schema(self):
        for preset in PRESETS:
            with self.subTest(preset=preset):
                profile = build_profile(preset, cpu_threads=8)

                self.assertEqual(profile["schema_version"], 1)
                self.assertEqual(profile["preset"], preset)
                self.assertIn("cpu", profile)
                self.assertIn("gpu", profile)
                self.assertIn("emulation", profile)
                self.assertIn("frame_pacing", profile)

    def test_worker_threads_keep_capacity_for_main_emulation_thread(self):
        self.assertEqual(build_profile("performance", cpu_threads=1)["cpu"]["worker_threads"], 1)
        self.assertEqual(build_profile("performance", cpu_threads=2)["cpu"]["worker_threads"], 1)
        self.assertEqual(build_profile("performance", cpu_threads=8)["cpu"]["worker_threads"], 6)
        self.assertEqual(build_profile("balanced", cpu_threads=8)["cpu"]["worker_threads"], 4)
        self.assertEqual(build_profile("compatibility", cpu_threads=8)["cpu"]["worker_threads"], 2)

    def test_unknown_preset_reports_valid_options(self):
        with self.assertRaisesRegex(ValueError, "Valid presets"):
            build_profile("turbo")

    def test_invalid_cpu_count_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "greater than zero"):
            build_profile("balanced", cpu_threads=0)

    def test_write_profile_is_json_and_creates_parent_directory(self):
        profile = build_profile("balanced", cpu_threads=4)

        with tempfile.TemporaryDirectory() as tmpdir:
            path = write_profile(f"{tmpdir}/nested/config", profile)
            loaded = json.loads(path.read_text(encoding="utf-8"))

        self.assertEqual(loaded, profile)
        self.assertEqual(path.name, "ipsx2-performance.json")


if __name__ == "__main__":
    unittest.main()
