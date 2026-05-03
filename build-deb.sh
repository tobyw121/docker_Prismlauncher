#!/usr/bin/env bash
set -Eeuo pipefail

SRC_DIR="${1:-/src}"
OUT_DIR="${2:-/out}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
PACKAGE_NAME="${PACKAGE_NAME:-prismlauncher}"
MAINTAINER="${MAINTAINER:-Prism Launcher CI <ci@example.invalid>}"
REVISION="${REVISION:-1}"
BUILD_DIR="${BUILD_DIR:-$SRC_DIR/build-deb}"
PKG_ROOT="${PKG_ROOT:-$SRC_DIR/pkgroot-deb}"
QT_ROOT="${QT_ROOT:-/opt/qt/${QT_VERSION:-6.10.2}/${QT_ABI:-gcc_64}}"
APP_LIB_DIR="$PKG_ROOT/usr/lib/prismlauncher"

log() { printf '\n==> %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

sanitize_deb_upstream_version() {
  local raw="$1"
  raw="${raw#v}"
  raw="$(printf '%s' "$raw" | sed -E 's/[^A-Za-z0-9.+:~]/+/g; s/^[+.:~-]+//; s/[+.:~-]+$//')"
  [[ -n "$raw" ]] || raw="0"
  if [[ ! "$raw" =~ ^[0-9] ]]; then
    raw="0~git${raw}"
  fi
  printf '%s' "$raw"
}

copy_qt_lib_from_ldd() {
  local binary="$1"
  [[ -e "$binary" ]] || return 0
  LD_LIBRARY_PATH="$APP_LIB_DIR:$QT_ROOT/lib:${LD_LIBRARY_PATH:-}" ldd "$binary" \
    | awk '/=> \/opt\/qt\// {print $3} /^\/opt\/qt\// {print $1}' \
    | sort -u \
    | while read -r lib; do
        [[ -n "$lib" && -f "$lib" ]] || continue
        cp -L "$lib" "$APP_LIB_DIR/$(basename "$lib")"
      done
}

SRC_DIR="$(readlink -f "$SRC_DIR")"
mkdir -p "$OUT_DIR"
OUT_DIR="$(readlink -f "$OUT_DIR")"
[[ -d "$SRC_DIR" ]] || fail "Source directory not found: $SRC_DIR"
[[ -x "$QT_ROOT/bin/qmake6" || -x "$QT_ROOT/bin/qt-cmake" ]] || fail "Qt not found under $QT_ROOT"

if [[ -d "$SRC_DIR/.git" ]]; then
  log "Updating submodules"
  git -C "$SRC_DIR" submodule update --init --recursive
fi

RAW_VERSION="${VERSION:-}"
if [[ -z "$RAW_VERSION" ]]; then
  RAW_VERSION="$(git -C "$SRC_DIR" describe --tags --always --dirty 2>/dev/null || true)"
fi
if [[ -z "$RAW_VERSION" ]]; then
  RAW_VERSION="0~local$(date -u +%Y%m%d%H%M%S)"
fi
UPSTREAM_VERSION="$(sanitize_deb_upstream_version "$RAW_VERSION")"
DEB_VERSION="${UPSTREAM_VERSION}-${REVISION}"
ARCH="$(dpkg --print-architecture)"

log "Configuring Prism Launcher $DEB_VERSION for $ARCH"
rm -rf "$BUILD_DIR" "$PKG_ROOT"
export ARTIFACT_NAME="${ARTIFACT_NAME:-Linux-${ARCH}-deb}"
export BUILD_PLATFORM="${BUILD_PLATFORM:-official}"
export CMAKE_PREFIX_PATH="$QT_ROOT${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export PATH="$QT_ROOT/bin:$PATH"

cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G "Ninja Multi-Config" \
  -DLauncher_BUILD_ARTIFACT="$ARTIFACT_NAME" \
  -DLauncher_BUILD_PLATFORM="$BUILD_PLATFORM" \
  -DLauncher_ENABLE_JAVA_DOWNLOADER=ON \
  -DENABLE_LTO=ON

log "Building $BUILD_TYPE"
cmake --build "$BUILD_DIR" --config "$BUILD_TYPE" --parallel "$(nproc)"

log "Installing into package root"
DESTDIR="$PKG_ROOT" cmake --install "$BUILD_DIR" --config "$BUILD_TYPE" --prefix /usr --strip

[[ -x "$PKG_ROOT/usr/bin/prismlauncher" ]] || fail "Installed launcher binary not found"
mkdir -p "$APP_LIB_DIR"
mv "$PKG_ROOT/usr/bin/prismlauncher" "$APP_LIB_DIR/prismlauncher-bin"

cat > "$PKG_ROOT/usr/bin/prismlauncher" <<'WRAPPER'
#!/bin/sh
APPDIR=/usr/lib/prismlauncher
export LD_LIBRARY_PATH="$APPDIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="$APPDIR/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
exec "$APPDIR/prismlauncher-bin" "$@"
WRAPPER
chmod 0755 "$PKG_ROOT/usr/bin/prismlauncher" "$APP_LIB_DIR/prismlauncher-bin"

log "Bundling Qt runtime libraries and plugins"
copy_qt_lib_from_ldd "$APP_LIB_DIR/prismlauncher-bin"
mkdir -p "$APP_LIB_DIR/plugins"
rsync -a --include='*/' --include='*.so' --exclude='*' "$QT_ROOT/plugins/" "$APP_LIB_DIR/plugins/"
find "$APP_LIB_DIR/plugins" -type f -name '*.so' -print0 \
  | while IFS= read -r -d '' plugin; do copy_qt_lib_from_ldd "$plugin"; done

cat > "$APP_LIB_DIR/qt.conf" <<'QTCONF'
[Paths]
Plugins = plugins
QTCONF

log "Collecting Debian runtime dependencies"
declare -A DEB_DEPS=()
add_dep() {
  local dep="$1"
  [[ -n "$dep" ]] || return 0
  DEB_DEPS["$dep"]=1
}
collect_system_deps() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  while read -r lib; do
    [[ -n "$lib" && -e "$lib" ]] || continue
    case "$lib" in
      "$APP_LIB_DIR"/*|"$QT_ROOT"/*) continue ;;
    esac
    local pkg
    pkg="$(dpkg-query -S "$lib" 2>/dev/null | awk -F: 'NR==1 {print $1}' || true)"
    [[ -n "$pkg" ]] || continue
    add_dep "$pkg"
  done < <(LD_LIBRARY_PATH="$APP_LIB_DIR:$QT_ROOT/lib:${LD_LIBRARY_PATH:-}" ldd "$file" 2>/dev/null \
      | awk '/=> \/.*\// {print $3} /^\/.*\// {print $1}')
}

add_dep "ca-certificates"
add_dep "default-jre | java-runtime"
while IFS= read -r -d '' elf; do
  collect_system_deps "$elf"
done < <(find "$APP_LIB_DIR" -type f \
  \( -name 'prismlauncher-bin' -o -name '*.so' -o -name '*.so.*' \) -print0)
DEPENDS="$(printf '%s\n' "${!DEB_DEPS[@]}" | sort -u | awk 'BEGIN { first=1 } { if (!first) printf ", "; printf "%s", $0; first=0 } END { printf "\n" }')"

log "Creating Debian metadata"
mkdir -p "$PKG_ROOT/DEBIAN"
INSTALLED_SIZE="$(du -sk "$PKG_ROOT/usr" | awk '{print $1}')"
cat > "$PKG_ROOT/DEBIAN/control" <<CONTROL
Package: ${PACKAGE_NAME}
Version: ${DEB_VERSION}
Section: games
Priority: optional
Architecture: ${ARCH}
Maintainer: ${MAINTAINER}
Installed-Size: ${INSTALLED_SIZE}
Depends: ${DEPENDS}
Recommends: desktop-file-utils, shared-mime-info, hicolor-icon-theme
Homepage: https://prismlauncher.org/
Description: Prism Launcher for Minecraft
 Prism Launcher is a custom Minecraft launcher for managing multiple
 Minecraft instances, modpacks, mods, resource packs and Java settings.
 This package bundles the Qt runtime used by the build.
CONTROL

cat > "$PKG_ROOT/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v update-mime-database >/dev/null 2>&1; then
  update-mime-database /usr/share/mime || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
POSTINST
chmod 0755 "$PKG_ROOT/DEBIAN/postinst"

cat > "$PKG_ROOT/DEBIAN/prerm" <<'PRERM'
#!/bin/sh
set -e
exit 0
PRERM
chmod 0755 "$PKG_ROOT/DEBIAN/prerm"

find "$PKG_ROOT" -type d -exec chmod 0755 {} +

DEB_FILE="${PACKAGE_NAME}_${DEB_VERSION}_${ARCH}.deb"
log "Building $DEB_FILE"
dpkg-deb --root-owner-group --build "$PKG_ROOT" "$OUT_DIR/$DEB_FILE"

log "Validating package"
dpkg-deb --info "$OUT_DIR/$DEB_FILE"
dpkg-deb --contents "$OUT_DIR/$DEB_FILE" | head -80

printf '\nBuilt package: %s\n' "$OUT_DIR/$DEB_FILE"
