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

The **Build Unsigned IPA** workflow is now an upstream-style macOS build for
`iPSX2-src`, not just a packager for this lightweight wrapper repository. It runs
on `push`, `pull_request`, and manual `workflow_dispatch`. The run name includes
the branch and commit SHA, and the first steps print the workflow revision so it
is obvious when GitHub is still running an old workflow file.

The workflow does this:

1. checks out this repository for the helper scripts;
2. uses an existing `cpp/CMakeLists.txt` if the workflow is copied into the real
   source repo, otherwise clones `jk0965844931-netizen/iPSX2-src`;
3. generates the top-level iOS Xcode project from `cpp/` with CMake and ignores
   vendor projects such as `cpp/3rdparty/SDL3/Xcode/SDL/SDL.xcodeproj`;
4. archives the `iPSX2` scheme unsigned with code signing disabled;
5. packages the archive as `Payload/*.app` inside `iPSX2-unsigned.ipa`;
6. verifies the IPA structure and uploads it as `iPSX2-unsigned-<run number>`.

If the upstream branch, repo, or scheme changes, rerun the manual workflow and
set `source_repository`, `source_ref`, or `scheme`.

### Troubleshooting stale workflow runs

If the Actions log still fails with a message like
`working directory '/Users/runner/work/Ps2/Ps2/cpp' ... No such file or directory`,
the run is using an older workflow revision. The fixed workflow prints
**Print workflow revision** before Xcode setup and then calls
`scripts/build_unsigned_ipa.sh`; it does not set a YAML-level `working-directory`
to `cpp/`. Merge this branch to `main`, or manually choose this branch in
**Run workflow**, then run **Build Unsigned IPA** again.

The helper script still supports packaging a prebuilt app/archive locally:

```bash
python3 scripts/package_ipa.py --app path/to/App.app --output artifacts/App.ipa
python3 scripts/package_ipa.py --archive path/to/App.xcarchive --output artifacts/App.ipa
```

Unsigned IPAs are useful as CI artifacts and for sideloading workflows that sign
later. Installing directly on a physical iPhone or distributing through TestFlight
normally still requires Apple certificates, provisioning profiles, and a signed
export step.
