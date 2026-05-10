import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

from scripts.package_ipa import PackagingError, package_ipa, resolve_app_bundle


def create_app(path: Path, bundle_name: str = "TestApp.app") -> Path:
    app = path / bundle_name
    app.mkdir(parents=True)
    (app / "TestApp").write_text("fake executable", encoding="utf-8")
    with (app / "Info.plist").open("wb") as handle:
        plistlib.dump(
            {
                "CFBundleExecutable": "TestApp",
                "CFBundleIdentifier": "dev.example.testapp",
                "CFBundleName": "TestApp",
                "CFBundlePackageType": "APPL",
            },
            handle,
        )
    return app


class PackageIpaTests(unittest.TestCase):
    def test_packages_app_as_payload_zip(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            app = create_app(root)
            output = root / "artifacts" / "TestApp.ipa"

            package_ipa(app, output)

            self.assertTrue(output.is_file())
            with zipfile.ZipFile(output) as ipa:
                names = set(ipa.namelist())

        self.assertIn("Payload/TestApp.app/Info.plist", names)
        self.assertIn("Payload/TestApp.app/TestApp", names)

    def test_resolves_single_app_from_xcarchive(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            archive = Path(tmpdir) / "Build.xcarchive"
            apps_dir = archive / "Products" / "Applications"
            app = create_app(apps_dir)

            self.assertEqual(resolve_app_bundle(archive=archive), app.resolve())

    def test_rejects_missing_info_plist(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            app = Path(tmpdir) / "Broken.app"
            app.mkdir()

            with self.assertRaisesRegex(PackagingError, "Info.plist"):
                resolve_app_bundle(app=app)

    def test_rejects_multiple_apps_in_archive(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            apps_dir = Path(tmpdir) / "Build.xcarchive" / "Products" / "Applications"
            create_app(apps_dir, "One.app")
            create_app(apps_dir, "Two.app")

            with self.assertRaisesRegex(PackagingError, "multiple"):
                resolve_app_bundle(archive=Path(tmpdir) / "Build.xcarchive")


if __name__ == "__main__":
    unittest.main()
