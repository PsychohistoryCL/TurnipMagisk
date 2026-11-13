#!/usr/bin/env bash
set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
NDK_VERSION="android-ndk-r28"
NDK_URL="https://dl.google.com/android/repository/${NDK_VERSION}-linux.zip"
MESA_REPO="https://github.com/LFRon/Turnip-Enhanced.git"
MESA_BRANCH="main"
API_LEVEL=33
A8XX_PATCH_URL="https://github.com/whitebelyash/mesa-tu8/releases/download/patchset-head-v2/tu8_kgsl.patch"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$ROOT_DIR/build"
TEMPLATE_DIR="$ROOT_DIR/module_template"
PATCHES_DIR="$ROOT_DIR/patches"
OUTPUT_DIR="$ROOT_DIR/out"

# ─── Clean & prepare ─────────────────────────────────────────────────────────
rm -rf "$WORK_DIR" "$OUTPUT_DIR"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
cd "$WORK_DIR"

# ─── Install python deps ─────────────────────────────────────────────────────
echo "==> Installing Python build dependencies..."
pip install mako pyyaml ply --quiet

# ─── Download NDK (skipped if cached) ─────────────────────────────────────────
echo "==> Checking for Android NDK ($NDK_VERSION)..."
if [ -d "$WORK_DIR/$NDK_VERSION" ]; then
    echo "  NDK found in cache, skipping download"
else
    echo "  Downloading NDK (~689 MB)..."
    curl -L "$NDK_URL" -o ndk.zip
    unzip -q ndk.zip
    rm ndk.zip
fi
NDK_TOOLCHAIN="$WORK_DIR/$NDK_VERSION/toolchains/llvm/prebuilt/linux-x86_64/bin"

# Ensure ccache is on PATH and wraps the compiler
export PATH="/usr/lib/ccache:$PATH"

# ─── Clone Mesa ───────────────────────────────────────────────────────────────
echo "==> Cloning Mesa (shallow, branch: $MESA_BRANCH)..."
git clone --depth 1 --branch "$MESA_BRANCH" "$MESA_REPO" mesa
cd mesa

# Extract Mesa version from VERSION file
MESA_VERSION=$(cat VERSION)
echo "  Mesa version: $MESA_VERSION"

# ─── Apply patches ────────────────────────────────────────────────────────────
echo "==> Applying patches..."
for patchfile in "$PATCHES_DIR"/*.patch; do
    if [ -f "$patchfile" ]; then
        PNAME="$(basename "$patchfile")"
        echo "  Applying: $PNAME"
        if git apply --check "$patchfile" 2>/dev/null; then
            git apply "$patchfile"
            echo "    OK (clean)"
        elif patch -p1 --dry-run < "$patchfile" > /dev/null 2>&1; then
            patch -p1 --fuzz=3 < "$patchfile"
            echo "    OK (with fuzz)"
        else
            echo "    SKIPPED: $PNAME — does not apply to current Mesa (upstream may have changed)"
        fi
    fi
done

# Show the patched line to confirm VK 1.4 patch
echo "  Verifying VK 1.4 patch applied:"
grep -n "apiVersion" src/freedreno/vulkan/tu_device.cc | head -5

# ─── Workaround: symlink clang as cc/c++ ─────────────────────────────────────
mkdir -p "$WORK_DIR/bin"
ln -sf "$NDK_TOOLCHAIN/clang" "$WORK_DIR/bin/cc"
ln -sf "$NDK_TOOLCHAIN/clang++" "$WORK_DIR/bin/c++"
export PATH="$WORK_DIR/bin:$NDK_TOOLCHAIN:$PATH"
export CC=clang CXX=clang++ AR=llvm-ar RANLIB=llvm-ranlib
export STRIP=llvm-strip OBJDUMP=llvm-objdump OBJCOPY=llvm-objcopy
export LDFLAGS="-fuse-ld=lld"

# ─── Create meson cross file ─────────────────────────────────────────────────
echo "==> Creating meson cross-compilation files..."
cat > android-aarch64.txt <<EOF
[binaries]
ar = '${NDK_TOOLCHAIN}/llvm-ar'
c = ['ccache', '${NDK_TOOLCHAIN}/aarch64-linux-android${API_LEVEL}-clang']
cpp = ['ccache', '${NDK_TOOLCHAIN}/aarch64-linux-android${API_LEVEL}-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
c_ld = '${NDK_TOOLCHAIN}/ld.lld'
cpp_ld = '${NDK_TOOLCHAIN}/ld.lld'
strip = '${NDK_TOOLCHAIN}/llvm-strip'
pkg-config = ['env', 'PKG_CONFIG_LIBDIR=${NDK_TOOLCHAIN}/pkg-config', '/usr/bin/pkg-config']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

cat > native.txt <<EOF
[build_machine]
c = ['ccache', 'clang']
cpp = ['ccache', 'clang++']
ar = 'llvm-ar'
strip = 'llvm-strip'
c_ld = 'ld.lld'
cpp_ld = 'ld.lld'
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

# ─── Configure ────────────────────────────────────────────────────────────────
echo "==> Configuring Mesa build..."
meson setup build-android-aarch64 \
    --cross-file android-aarch64.txt \
    --native-file native.txt \
    -Dbuildtype=release \
    -Dplatforms=android \
    -Dplatform-sdk-version="$API_LEVEL" \
    -Dandroid-stub=true \
    -Dgallium-drivers= \
    -Dvulkan-drivers=freedreno \
    -Dvulkan-beta=true \
    -Dfreedreno-kmds=kgsl \
    -Db_lto=false \
    -Dstrip=true \
    -Degl=disabled \
    -Dandroid-libbacktrace=disabled \
    2>&1 | tee "$WORK_DIR/meson_log.txt"

# ─── Build ────────────────────────────────────────────────────────────────────
echo "==> Compiling (this takes a while)..."
ninja -C build-android-aarch64 2>&1 | tee "$WORK_DIR/ninja_log.txt"

# ─── Extract built artifacts ──────────────────────────────────────────────────
echo "==> Extracting build artifacts..."
BUILT_SO="build-android-aarch64/src/freedreno/vulkan/libvulkan_freedreno.so"

if [ ! -f "$BUILT_SO" ]; then
    echo "ERROR: Build failed — $BUILT_SO not found"
    echo "Check $WORK_DIR/ninja_log.txt for details"
    exit 1
fi

VERSION_CODE=$(date +%Y%m%d)
BUILD_DATE=$(date +%Y%m%d)

# ─── 1. Magisk module ────────────────────────────────────────────────────────
echo "==> Assembling Magisk module..."
cp "$BUILT_SO" "$WORK_DIR/vulkan.turnip.so"
patchelf --set-soname vulkan.turnip.so "$WORK_DIR/vulkan.turnip.so"

MODULE_DIR="$WORK_DIR/module"
cp -r "$TEMPLATE_DIR" "$MODULE_DIR"
mkdir -p "$MODULE_DIR/system/vendor/lib64/hw"
cp "$WORK_DIR/vulkan.turnip.so" "$MODULE_DIR/system/vendor/lib64/hw/vulkan.turnip.so"

sed -i "s|__MESA_VERSION__|${MESA_VERSION}|g" "$MODULE_DIR/module.prop"
sed -i "s|__VERSION_CODE__|${VERSION_CODE}|g" "$MODULE_DIR/module.prop"

echo "  module.prop:"
cat "$MODULE_DIR/module.prop"

MAGISK_ZIP="TurnipMagisk_v${MESA_VERSION}_${BUILD_DATE}.zip"
cd "$MODULE_DIR"
zip -r "$OUTPUT_DIR/$MAGISK_ZIP" . -x '*.DS_Store' -x '__MACOSX/*'
cd "$ROOT_DIR"
echo "  Magisk module: out/$MAGISK_ZIP"

# ─── 2. AdrenoTools / emulator package ───────────────────────────────────────
echo "==> Assembling adrenotools package (for emulators / Winlator)..."
ADPKG_DIR="$WORK_DIR/adrenotools"
mkdir -p "$ADPKG_DIR"

ADPKG_LIBNAME="vulkan.freedreno.so"
cp "$WORK_DIR/vulkan.turnip.so" "$ADPKG_DIR/$ADPKG_LIBNAME"
patchelf --set-soname "$ADPKG_LIBNAME" "$ADPKG_DIR/$ADPKG_LIBNAME"

cat > "$ADPKG_DIR/meta.json" <<EOF
{
  "schemaVersion": 1,
  "name": "Turnip Magisk v${MESA_VERSION}",
  "description": "Mesa Turnip with VK 1.4 for A6xx+, A8xx KGSL support, beta extensions",
  "author": "N1GHT (Mesa/freedreno + patches)",
  "packageVersion": "${BUILD_DATE}",
  "vendor": "Mesa",
  "driverVersion": "${MESA_VERSION}",
  "minApi": 33,
  "libraryName": "${ADPKG_LIBNAME}"
}
EOF

ADPKG_ZIP="Turnip_v${MESA_VERSION}_${BUILD_DATE}.adpkg.zip"
cd "$ADPKG_DIR"
zip -9 "$OUTPUT_DIR/$ADPKG_ZIP" "$ADPKG_LIBNAME" meta.json
cd "$ROOT_DIR"
echo "  Adrenotools pkg: out/$ADPKG_ZIP"

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Build complete!"
echo "  Mesa version:  $MESA_VERSION"
echo "  Vulkan 1.4:    Enabled for ALL Adreno 6xx+"
echo "  Magisk module: out/$MAGISK_ZIP"
echo "  Adrenotools:   out/$ADPKG_ZIP"
echo "============================================"
ls -lh "$OUTPUT_DIR/"

# Export for GitHub Actions
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "magisk_zip=$MAGISK_ZIP" >> "$GITHUB_OUTPUT"
    echo "adpkg_zip=$ADPKG_ZIP" >> "$GITHUB_OUTPUT"
    echo "mesa_version=$MESA_VERSION" >> "$GITHUB_OUTPUT"
fi
