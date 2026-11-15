# Changelog

## 1.1.1 — 2026-11-15 (preview)

- Engine: msync no longer leaks a server node when a wait gives up early (`patches/msync-wait-leak.patch`); this was the
  `node memory pool exhausted` line that filled Cuvee.log (10 GB). `tests/msync-leak.sh` reproduces it in ~20 s.
- Log: written in append mode (several programs at once), emptied in place past 20 MB instead of renamed.
- App: a failed launch drops its "Launching…" badge; errors show the CLI's reason and a Log button; a bottle without a
  launcher can run a program and be stopped; bottle creation shows progress; clearer name rules (case, leading `.`/`-`);
  Trash disabled while the bottle runs; every bottle is reachable from the sidebar.
- A build made on the Mac no longer offers the public installer (it would replace the developer runtime).
- CLI: a cut download is never kept as a cached installer, https only; `.x` and `-x` bottle names refused.
- Release workflow: a GitHub API error stops the run instead of rebuilding over a published release.
- Includes the microphone fix (PR #4) and the log cap, neither of which was in 1.1.0.

## 1.1.0 — 2026-11-13 (preview)

- Self-contained PKG and DMG installers for Apple Silicon, macOS 15+, Rosetta 2.
- In-app release checks, SHA-256 verification, and user-initiated macOS Installer updates.
- VERSION changes on main build, test and publish installers plus corresponding sources.
- main protected against force pushes and deletion, administrators included.
- DXMT/OpenGL/Gecko included; Vulkan, MoltenVK and DirectX 12 excluded from this edition.
- Ad-hoc signed, without Developer ID or notarization. Game data remains per user.
- Validation: six packaging tests, 19 updater checks, native app build, installer verification and a successful clean GitHub release build.
- Release: https://github.com/YesStonksMan/cuvee/releases/tag/v1.1.0

## Documentation — 2026-11-14

- Recorded the published GitHub product introduction, prominent direct downloads and About URL (`7bfd52b`).
- Documented that current download URLs pin 1.1.0 and need refreshing for future releases.
- Recorded the proposed first-user test plan, explicitly separate from executed actions or confirmed decisions.
- Updated local project instructions and Graphify notes/index without rebuilding the graph.
