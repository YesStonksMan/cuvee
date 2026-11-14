# Changelog

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
