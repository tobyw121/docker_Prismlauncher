# syntax=docker/dockerfile:1.4
# Build PrismLauncher as a .deb directly from GitHub.
# No makedeb, no MPR, no local source ZIP required.

FROM debian:bookworm-slim AS builder

ARG REPO_URL="https://github.com/PrismLauncher/PrismLauncher.git"
ARG BRANCH="release-9.x"
ARG PKG_NAME="prismlauncher"
ARG PKG_VERSION="auto"
ARG MAINTAINER="Local Build <root@localhost>"
ARG ENABLE_LTO="OFF"
ARG BUILD_JOBS=""

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    dpkg-dev \
    extra-cmake-modules \
    file \
    git \
    ninja-build \
    pkg-config \
    xz-utils \
    scdoc \
    cmark \
    libcmark-dev \
    libarchive-dev \
    gamemode \
    gamemode-dev \
    libgamemode0 \
    libgl1-mesa-dev \
    libqrencode-dev \
    libtomlplusplus-dev \
    libvulkan-dev \
    libxcb-cursor-dev \
    libxkbcommon-dev \
    zlib1g-dev \
    openjdk-17-jdk-headless \
    qtchooser \
    qt6-base-dev \
    qt6-base-dev-tools \
    qt6-networkauth-dev \
    libqt6core5compat6-dev \
    libqt6opengl6-dev \
    libqt6svg6-dev \
    qt6-image-formats-plugins \
 && set -eux; \
    multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"; \
    if [ ! -e "/usr/lib/${multiarch}/libgamemode.so" ] && [ -e "/usr/lib/${multiarch}/libgamemode.so.0" ]; then \
      ln -s libgamemode.so.0 "/usr/lib/${multiarch}/libgamemode.so"; \
    fi; \
    ldconfig; \
    rm -rf /var/lib/apt/lists/*

RUN git clone --recursive --branch "${BRANCH}" "${REPO_URL}" /src/prismlauncher \
 && git -C /src/prismlauncher submodule update --init --recursive

WORKDIR /src/prismlauncher

RUN <<'EOSH'
set -euo pipefail

if [ "${PKG_VERSION}" = "auto" ] || [ -z "${PKG_VERSION}" ]; then
    major="$(sed -n 's/^[[:space:]]*set(Launcher_VERSION_MAJOR[[:space:]]*\([0-9][0-9]*\)).*/\1/p' CMakeLists.txt | head -n1)"
    minor="$(sed -n 's/^[[:space:]]*set(Launcher_VERSION_MINOR[[:space:]]*\([0-9][0-9]*\)).*/\1/p' CMakeLists.txt | head -n1)"
    patch="$(sed -n 's/^[[:space:]]*set(Launcher_VERSION_PATCH[[:space:]]*\([0-9][0-9]*\)).*/\1/p' CMakeLists.txt | head -n1)"
    commit="$(git rev-parse --short=12 HEAD)"
    if [ -z "${major}" ] || [ -z "${minor}" ] || [ -z "${patch}" ]; then
        echo "Could not derive PrismLauncher version from CMakeLists.txt" >&2
        exit 1
    fi
    resolved_version="${major}.${minor}.${patch}+git${commit}"
else
    resolved_version="${PKG_VERSION}"
fi

dpkg --validate-version "${resolved_version}"
printf '%s\n' "${resolved_version}" > /tmp/pkg_version
printf '%s\n' "$(git rev-parse HEAD)" > /tmp/git_commit
printf 'Using Debian package version: %s\n' "${resolved_version}"
EOSH

RUN cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DBUILD_TESTING=OFF \
      -DENABLE_LTO=${ENABLE_LTO} \
      -DLauncher_BUILD_PLATFORM=debian \
      -DLauncher_BUILD_ARTIFACT=deb \
      -DLauncher_ENABLE_JAVA_DOWNLOADER=ON \
 && jobs="${BUILD_JOBS:-$(nproc)}" \
 && cmake --build build --parallel "${jobs}"

RUN rm -rf /pkgroot /out \
 && mkdir -p /pkgroot/DEBIAN /out \
 && DESTDIR=/pkgroot cmake --install build --strip

RUN <<'EOSH'
set -euo pipefail

cat > /pkgroot/DEBIAN/postinst <<'EOF_POSTINST'
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
EOF_POSTINST

cat > /pkgroot/DEBIAN/postrm <<'EOF_POSTRM'
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
EOF_POSTRM

chmod 0755 /pkgroot/DEBIAN/postinst /pkgroot/DEBIAN/postrm

ARCH="$(dpkg --print-architecture)"
VERSION="$(cat /tmp/pkg_version)"
COMMIT="$(cat /tmp/git_commit)"
SIZE="$(du -ks /pkgroot/usr | awk '{print $1}')"

mkdir -p /tmp/shlibscan/debian
cat > /tmp/shlibscan/debian/control <<EOF_CONTROL_SCAN
Source: ${PKG_NAME}
Section: games
Priority: optional
Maintainer: ${MAINTAINER}
Standards-Version: 4.6.2

Package: ${PKG_NAME}
Architecture: any
Description: Prism Launcher
EOF_CONTROL_SCAN

mapfile -t ELF_FILES < <(
    find /pkgroot -type f -perm /111 -print0 \
    | while IFS= read -r -d '' file_path; do
        if file -b "${file_path}" | grep -q 'ELF'; then
            printf '%s\n' "${file_path}"
        fi
      done
)

DEPS=""
if [ "${#ELF_FILES[@]}" -gt 0 ]; then
    cd /tmp/shlibscan
    DEPS="$(dpkg-shlibdeps -O "${ELF_FILES[@]}" | sed -n 's/^shlibs:Depends=//p')"
fi
if [ -z "${DEPS}" ]; then
    DEPS="libc6, libstdc++6, zlib1g"
fi

# Additional runtime packages that are not always discovered by shlibdeps.
DEPS="${DEPS}, qt6-image-formats-plugins, libqt6svg6, gamemode, mesa-utils, pciutils"

cat > /pkgroot/DEBIAN/control <<EOF_CONTROL
Package: ${PKG_NAME}
Version: ${VERSION}
Section: games
Priority: optional
Architecture: ${ARCH}
Maintainer: ${MAINTAINER}
Installed-Size: ${SIZE}
Depends: ${DEPS}
Homepage: https://prismlauncher.org/
Description: Prism Launcher
 Prism Launcher packaged directly from ${REPO_URL}, branch ${BRANCH}.
 .
 Git commit: ${COMMIT}
EOF_CONTROL

dpkg-deb --build --root-owner-group /pkgroot "/out/${PKG_NAME}_${VERSION}_${ARCH}.deb"
dpkg-deb -I "/out/${PKG_NAME}_${VERSION}_${ARCH}.deb"
EOSH

FROM scratch AS artifact
COPY --from=builder /out/ /
