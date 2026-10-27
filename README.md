# Cuvee

Play your Windows games on a Mac (Steam, Epic Games, Battle.net…) with a Wine you build yourself.

Cuvee builds the Wine that ships inside CrossOver 26.3 (Wine 11.0) from the source code CodeWeavers publishes,
adds a few small patches so the game launchers work, and gives you:

- `cuvee`, a command-line bottle manager: install a launcher in its own bottle, create, remove or import bottles,
  pick each bottle's graphics engine (Vulkan, OpenGL or Metal with MetalFX upscaling), launch a game, run a program;
- `Cuvee.app`, in English or French: a sidebar to search, start or install each launcher, open a bottle or report
  a bug, every installed game in one place, and per-bottle settings with a recommendation for your Apple Silicon chip.

> Cuvee is an independent project. It is not affiliated with, endorsed by or supported by CodeWeavers.
> CrossOver is a trademark of CodeWeavers, Inc.; Steam is a trademark of Valve Corporation; Wine is a trademark
> of the Wine project. If CrossOver works for you, buy it: CodeWeavers funds a large share of Wine's development,
> and their source releases are what makes this project possible.

*En français : Cuvee compile le Wine de CrossOver 26.3 depuis la source publique de CodeWeavers, ajoute des correctifs
pour les lanceurs de jeux (Steam, Epic, Battle.net…), et fournit une commande `cuvee` et une app pour gérer les bouteilles. Projet indépendant, sans lien avec CodeWeavers.*

## Status

Tested on an Apple Silicon Mac with macOS 27, through Rosetta 2.

| Works | Not yet |
| --- | --- |
| Steam: login, store, library, Play button | DirectX 12 (no vkd3d build yet) |
| Steam overlay FPS counter | DXVK (wined3d is used for D3D10/11) |
| D3D10/11 games through wined3d + MoltenVK (Kenshi, Brawlhalla tested) | Games with kernel anti-cheat |
| D3D10/11 on Metal through DXMT (Kenshi in game, 2560×1440); MetalFX upscaling not measured yet | Ubisoft Connect: installs, window stays white |
| Epic Games Launcher: install, update, sign-in screen | EA app: installer window shows, rest not verified yet |
| Battle.net: install, sign-in screen | Steam overlay menu (Shift+Tab) not verified |
| Dock icons named after the program ("Steam") | DLSS itself (NVIDIA hardware); DXMT maps a D3D11 game's DLSS option to MetalFX |

## What the patches do

All of them are in `patches/` and are applied by `build-wine.sh` on top of the pristine CodeWeavers source.

- **`steam-cmdline-flags.patch`** (kernelbase): adds `--no-sandbox --in-process-gpu --disable-gpu` to every
  `steamwebhelper.exe` (otherwise Steam's window stays black; Proton does something similar) and every
  `Battle.net.exe` (otherwise its sign-in window stays white), `--in-process-gpu --disable-gpu
  --disable-gpu-compositing` to `3DMark.exe` (otherwise its window stays black), and `-no-dwrite` to
  `gameoverlayui64.exe`/`gameoverlayui.exe` (otherwise the overlay's text, such as the FPS counter, is blank:
  Steam's VGUI draws it through DirectWrite, which renders nothing here; GDI text works).
- **`dock-app-name.patch`** (ntdll): CrossOver's code names each Dock icon after its program, but kept the `.exe`
  and named the first process after the loader. Cuvee drops the extension, capitalizes the name, names the first
  process after the program it starts, and shows Steam's window (owned by `steamwebhelper`) as "Steam".
- **`vulkan-soname-default.patch`** (win32u): Wine is configured without its own Vulkan loader; this points it at
  `libMoltenVK.dylib`.
- **`dll-path-prepend.patch`** (ntdll): `WINEDLLPATH_PREPEND` is searched before Wine's own DLLs, so a bottle set to
  `graphics dxmt` loads DXMT's `d3d11`/`dxgi`/`d3d10core` instead of wined3d's. Wine's `d3d12` (vkd3d) does not
  work with DXMT's `dxgi`, so a program whose `.exe` imports `d3d12.dll` but not `d3d11.dll` (normal or delay-load
  imports) skips `WINEDLLPATH_PREPEND` and gets Wine's own `dxgi`; every other program keeps DXMT. A game that imports
  both (many Unreal Engine games) stays on DXMT and falls back to Direct3D 11 if it can.

`cuvee` also sets `WINE_SIMULATE_WRITECOPY=1` for Battle.net bottles (its CEF renderer crashes in a loop without it)
and passes Windows paths to `msiexec` (Wine's msiexec crashes on a raw Unix path).

Cuvee contains no code or binary taken from CrossOver's closed-source parts.

## Requirements

- Apple Silicon Mac with Rosetta 2 (`softwareupdate --install-rosetta`), Xcode Command Line Tools.
- [Homebrew](https://brew.sh) and: `brew install bison flex mingw-w64 autoconf automake libtool pkgconf gettext`
- About 6 GB of disk for sources and build, plus your games.
- So far the build has only been checked on the author's Mac: if a step fails on a clean machine, please open an issue.
- MoltenVK, see below.
- `fetch-sources.sh` also downloads DXMT 0.80 (3Shain/dxmt, LGPL-2.1+) and Wine Gecko 2.47.4 (WineHQ, MPL),
  both SHA-256 checked.

## Build

The build directory must be reachable through a path without spaces, so use a symlink:

```bash
git clone https://github.com/YesStonksMan/cuvee.git ~/cuvee-src && ln -sn ~/cuvee-src ~/.cuvee
cd ~/.cuvee
./fetch-sources.sh    # CrossOver 26.3 sources, GNU nettle, DXMT, Wine Gecko; SHA-256 checked
./build-deps.sh       # x86_64 gmp, nettle, gnutls, freetype
./build-wine.sh       # Wine + patches -> dist/
./cuvee install       # copy dist/ and the CLI to ~/Library/Application Support/Cuvee/runtime
launcher/build.sh     # optional: /Applications/Cuvee.app
alias cuvee=~/.cuvee/cuvee   # put this in ~/.zshrc to type `cuvee` anywhere
```

`cuvee install` copies the build out of your project folder because apps started from the Finder cannot read
`~/Desktop` or `~/Documents`. Run it again after every rebuild, with Steam and games closed.

The first `cuvee install` then offers to install the game launchers (`cuvee setup` asks again).

`Cuvee.app` runs that installed copy, so run `cuvee install` first. Being started from the Finder, it does not see
shell variables such as `CUVEE_BOTTLES`.

`dist/` bundles gmp, nettle, gnutls and freetype; it is meant for your own Mac, not for redistribution as is.

### MoltenVK

wined3d needs MoltenVK (Vulkan on Metal) for Direct3D 10/11. It has to be CodeWeavers' fork
(`src/sources/moltenvk`, Apache-2.0): the upstream Khronos build lacks `geometryShader`, `shaderCullDistance` and
`pipelineStatisticsQuery`, which wined3d requires. Building it needs full Xcode, so Cuvee does not ship it:

- if CrossOver is installed, `build-wine.sh` copies its `libMoltenVK.dylib` (tested: CrossOver 26.3);
- otherwise, build `src/sources/moltenvk` with Xcode and put `libMoltenVK.dylib` in `dist/lib/`.

Without it, Direct3D 10/11 games fall back to OpenGL 4.1, and many will crash.

## Use

```bash
cuvee launchers             # steam epic ea battlenet ubisoft
cuvee add epic              # create the "Epic Games" bottle and install the launcher from Epic's site
cuvee open "Epic Games"     # start a bottle's launcher
cuvee create NAME           # empty Windows 10 bottle; cuvee remove NAME moves one to the Trash
cuvee set NAME graphics dxmt    # vulkan (default) | opengl | dxmt (Direct3D 10/11 on Metal)
cuvee set NAME metalfx on       # MetalFX upscaling, needs dxmt; cuvee settings NAME shows a bottle's settings
cuvee import Steam          # clone an existing CrossOver bottle named Steam (APFS clone, no extra disk)
cuvee game Steam 291550     # launch a game by its Steam app id, like the Play button
cuvee run NAME PROGRAM      # run any Windows program in bottle NAME
cuvee cfg NAME              # winecfg
cuvee stop NAME             # close bottle NAME as Windows does at shutdown (programs can save)
cuvee kill NAME             # stop everything in bottle NAME, without letting it save
```

Bottles live in `~/Library/Application Support/Cuvee/Bottles` (`CUVEE_BOTTLES` to change it). Extra Steam
arguments go in `CUVEE_STEAM_ARGS`. The app logs to `~/Library/Logs/Cuvee.log`.

Tips:

- wined3d picks its Vulkan renderer for D3D10/11 when MoltenVK is present; `graphics opengl` forces OpenGL.
- FSR is a setting inside each game. MetalFX with `graphics dxmt` renders fewer pixels and scales the image up
  (factor 2 by default; `d3d11.metalSpatialUpscaleFactor` in a `dxmt.conf` changes it, see DXMT's documentation).
- `tests/steam-fps-test.sh LABEL DIST BOTTLE` launches Steam and Brawlhalla (must be installed), captures the
  FPS counter corner to `tests/out/`, then closes Brawlhalla and Steam. Needs Accessibility and Screen Recording
  permission for your terminal. Do not run it while you play.
- `tests/d3dred.c` is a minimal D3D11 window: `x86_64-w64-mingw32-gcc tests/d3dred.c -o d3dred.exe -ld3d11 -ldxgi -ldxguid -mwindows`.
- `tests/d3d12green.c` (clear only) and `tests/d3d12tri.c` (HLSL compiled at run time, one triangle) are minimal D3D12
  windows; each prints every call's HRESULT and the frame count after 20 s:
  `x86_64-w64-mingw32-gcc tests/d3d12tri.c -o d3d12tri.exe -ld3d12 -ldxgi -ldxguid -ld3dcompiler -mwindows`.

## License

Copyright (C) 2026 YesStonksMan and contributors.

Cuvee's scripts, app, icon and patches are released under the GNU Lesser General Public License v2.1 or later,
the license of Wine (see `LICENSE`). Wine, CrossOver's source release, MoltenVK, DXMT and Wine Gecko belong to their respective
authors and keep their own licenses.
