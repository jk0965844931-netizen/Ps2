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

## GitHub Actions IPA output

A GitHub Action cannot magically become an IPA by itself. An `.ipa` is a zip file
containing `Payload/<AppName>.app`, so the workflow needs one of these inputs:

1. an already-built `.app` bundle;
2. an existing `.xcarchive`; or
3. a real iOS Xcode project/workspace plus a scheme that can be archived on a macOS runner.

This repository includes `.github/workflows/build-ipa.yml` for that flow. Run the
manual **Build IPA** workflow and provide `app_path`, `archive_path`, or
`workspace`/`project` plus `scheme`. The workflow uploads the generated `.ipa` as
an artifact.

For local packaging, use:

```bash
python3 scripts/package_ipa.py --app path/to/App.app --output artifacts/App.ipa
```

or:

```bash
python3 scripts/package_ipa.py --archive path/to/App.xcarchive --output artifacts/App.ipa
```

Unsigned IPAs are useful as CI artifacts, but installing on a physical iPhone or
distributing through TestFlight normally requires Apple signing certificates,
provisioning profiles, and a signed export step.
