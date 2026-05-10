# iPSX2 Performance Toolkit

This repository now includes a small, testable performance-profile generator that can be used by iPSX2 launchers, setup tools, or CI packaging scripts to ship safer default settings for smoother gameplay.

The toolkit focuses on changes that are generally safe for emulators:

- keeps frame pacing stable instead of blindly chasing peak FPS;
- enables cache-friendly runtime defaults;
- scales worker threads to the host CPU without oversubscribing low-core systems;
- separates `performance`, `balanced`, and `compatibility` profiles so players can trade speed for stability when a title needs it.

> Note: the upstream source URL supplied with the task could not be fetched from this environment, so the changes are packaged as a standalone module that can be merged into the project tree or called from an existing launcher.

## Usage

Preview a profile without writing files:

```bash
python3 scripts/apply_performance_profile.py --preset performance --dry-run
```

Write the generated profile to a config directory:

```bash
python3 scripts/apply_performance_profile.py --preset balanced --config-dir ./user-config
```

The command writes `ipsx2-performance.json` atomically so a crash cannot leave a partially-written config file.

## Presets

| Preset | Goal | Best for |
| --- | --- | --- |
| `performance` | Higher throughput and lower input latency | Fast devices, lighter games, users chasing FPS |
| `balanced` | Smooth frame pacing with conservative defaults | Most users |
| `compatibility` | Fewer risky speed hacks and extra validation | Buggy titles or slower/older devices |

## Development

Run the unit tests:

```bash
python3 -m unittest discover -s tests
```

## GitHub Actions unsigned IPA output

The **Build Unsigned IPA** workflow is set up for the common GitHub-hosted macOS
flow: run the workflow manually, let GitHub use a `macos-14` runner with Xcode,
archive the iOS target with code signing disabled, package the generated `.app`
inside `Payload/`, and upload `iPSX2-unsigned.ipa` as a downloadable artifact.

If the repository contains a single `.xcworkspace` or `.xcodeproj`, you can leave
`workspace`, `project`, and `scheme` blank and the workflow will auto-detect the
build container and first shared scheme. If auto-detection is wrong, rerun the
workflow and provide the exact `workspace`/`project` and `scheme` inputs.

The workflow also supports packaging a prebuilt app/archive:

```bash
python3 scripts/package_ipa.py --app path/to/App.app --output artifacts/App.ipa
python3 scripts/package_ipa.py --archive path/to/App.xcarchive --output artifacts/App.ipa
```

Unsigned IPAs are useful as CI artifacts and for sideloading workflows that sign
later. Installing directly on a physical iPhone or distributing through TestFlight
normally still requires Apple certificates, provisioning profiles, and a signed
export step.
