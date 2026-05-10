#!/usr/bin/env python3
"""Package an iOS .app bundle or .xcarchive into an .ipa file.

An IPA is a zip archive with this layout:

    Payload/YourApp.app/...

This helper intentionally does packaging only. Building the .app still requires
an iOS/Xcode project, and installing on physical devices usually requires a
properly signed build.
"""

from __future__ import annotations

import argparse
import os
import plistlib
import shutil
import tempfile
import zipfile
from pathlib import Path


class PackagingError(ValueError):
    """Raised when the supplied app/archive cannot be packaged as an IPA."""


def _find_single_app(apps_dir: Path) -> Path:
    apps = sorted(path for path in apps_dir.glob("*.app") if path.is_dir())
    if not apps:
        raise PackagingError(f"no .app bundle found in {apps_dir}")
    if len(apps) > 1:
        names = ", ".join(app.name for app in apps)
        raise PackagingError(f"multiple .app bundles found in {apps_dir}: {names}")
    return apps[0]


def resolve_app_bundle(*, app: Path | None = None, archive: Path | None = None) -> Path:
    """Resolve either an explicit .app path or an .xcarchive to one .app bundle."""

    if app and archive:
        raise PackagingError("use either --app or --archive, not both")
    if not app and not archive:
        raise PackagingError("one of --app or --archive is required")

    if archive:
        archive = archive.expanduser().resolve()
        apps_dir = archive / "Products" / "Applications"
        if archive.suffix != ".xcarchive" or not apps_dir.is_dir():
            raise PackagingError(f"{archive} is not a valid .xcarchive with Products/Applications")
        app = _find_single_app(apps_dir)

    assert app is not None
    app = app.expanduser().resolve()
    if app.suffix != ".app" or not app.is_dir():
        raise PackagingError(f"{app} is not an .app bundle directory")

    info_plist = app / "Info.plist"
    if not info_plist.is_file():
        raise PackagingError(f"missing required {info_plist}")

    with info_plist.open("rb") as handle:
        metadata = plistlib.load(handle)
    if metadata.get("CFBundlePackageType") not in (None, "APPL"):
        raise PackagingError("Info.plist CFBundlePackageType must be APPL for an iOS app")

    return app


def package_ipa(app: Path, output: Path) -> Path:
    """Create an IPA containing *app* and return the output path."""

    app = resolve_app_bundle(app=app)
    output = output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="ipa-payload-") as tmpdir:
        payload_dir = Path(tmpdir) / "Payload"
        staged_app = payload_dir / app.name
        payload_dir.mkdir()
        shutil.copytree(app, staged_app, symlinks=True)

        temporary_output = output.with_suffix(output.suffix + ".tmp")
        if temporary_output.exists():
            temporary_output.unlink()

        with zipfile.ZipFile(temporary_output, "w", compression=zipfile.ZIP_DEFLATED) as ipa:
            for path in sorted(payload_dir.rglob("*")):
                archive_name = path.relative_to(payload_dir.parent).as_posix()
                ipa.write(path, archive_name)

        os.replace(temporary_output, output)

    return output


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--app", type=Path, help="Path to a built .app bundle.")
    source.add_argument("--archive", type=Path, help="Path to an .xcarchive containing one .app.")
    parser.add_argument("--output", type=Path, required=True, help="Output .ipa path.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    app = resolve_app_bundle(app=args.app, archive=args.archive)
    ipa = package_ipa(app, args.output)
    print(f"Wrote {ipa}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
