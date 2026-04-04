# TurnipMagisk

A Magisk module that compiles [Mesa Turnip](https://gitlab.freedesktop.org/mesa/mesa) from source with **Vulkan 1.4 enabled for Adreno 6xx and later** (upstream only enables 1.4 for A7xx+).

## What this does

Upstream Mesa gates Vulkan 1.4 behind a `chip >= 7` check in `tu_device.cc`, so Adreno 6xx devices (620, 640, 650, 660, etc.) are capped at Vulkan 1.3 even though they support the required features. This module patches that check out and compiles a single Turnip driver from Mesa main.

### Patches applied
- **Vulkan 1.4 for A6xx** — removes the chip >= 7 gate
- **A710/A720 GPU support** — adds unsupported GPU definitions (K11MCH1)
- **A8xx KGSL/UBWC** — Whitebelyash's Adreno 8xx support patch (downloaded at build time)
- **Vulkan beta extensions** enabled

## Installation

1. Download the latest zip from the [Releases](../../releases) page
2. Flash in **Magisk** / **KernelSU** / **APatch**
3. Reboot

## Switching Drivers

Tap the **action button** on the module card:

```
Turnip (Vulkan 1.4) ↔ Adreno (stock)
```

No reboot needed — takes effect for newly launched apps.

## Emulator / Winlator usage

Download the `.adpkg.zip` from the release and load it in your emulator's driver settings (Yuzu, Vita3K, Eden, Winlator, etc.)

## Building from source

Runs on Linux (or GitHub Actions). Requires: meson, ninja, patchelf, Android NDK.

```bash
bash scripts/build.sh
# Output: out/TurnipMagisk_*.zip + out/Turnip_*.adpkg.zip
```

## How it works

1. Clones Mesa main branch
2. Applies `patches/enable-vk14-a6xx.patch` — removes the A7xx+ gate on Vulkan 1.4
3. Applies `patches/unsup-gpus-a710-a720.patch` — adds A710/A720 GPU definitions
4. Downloads and applies Whitebelyash A8xx KGSL patch
5. Cross-compiles `libvulkan_freedreno.so` for Android aarch64 (NDK r28, API 33)
6. Packages into a Magisk module + adrenotools package

## CI

GitHub Actions builds weekly and publishes to a rolling `nightly` release.

## Credits

- [Mesa/freedreno](https://gitlab.freedesktop.org/mesa/mesa) — the actual Turnip driver
- [K11MCH1](https://github.com/K11MCH1/AdrenoToolsDrivers) — unsupported GPU patches, build system reference
- [Whitebelyash](https://github.com/Whitebelyash/mesa-tu8) — A8xx KGSL support
- [MrPurple666](https://github.com/MrPurple666) — inspiration and prior A6xx Vulkan 1.4 work
- [MrMiy4mo](https://github.com/ilhan-athn7/freedreno_turnip-CI) — original Magisk module structure
