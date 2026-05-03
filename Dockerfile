# syntax=docker/dockerfile:1
# Builder image for Prism Launcher Debian packages.
# It builds Prism Launcher with the upstream Qt toolchain and produces a self-contained .deb
# that bundles Qt under /usr/lib/prismlauncher while leaving common system libraries as Debian deps.

ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

ARG DEBIAN_FRONTEND=noninteractive
ARG QT_VERSION=6.10.2
ARG QT_HOST=linux
ARG QT_TARGET=desktop
ARG QT_ARCH=
ARG QT_ABI=gcc_64

ENV QT_VERSION=${QT_VERSION} \
    QT_ABI=${QT_ABI} \
    QT_ROOT=/opt/qt/${QT_VERSION}/${QT_ABI} \
    PATH=/opt/qt/${QT_VERSION}/${QT_ABI}/bin:${PATH} \
    QT_PLUGIN_PATH=/opt/qt/${QT_VERSION}/${QT_ABI}/plugins \
    CMAKE_LINKER_TYPE=lld \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates curl git gnupg locales python3-pip \
    build-essential clang lld llvm \
    cmake ninja-build extra-cmake-modules pkg-config \
    openjdk-17-jdk \
    dpkg-dev fakeroot file patchelf rsync xz-utils \
    cmark scdoc \
    gamemode-dev libarchive-dev libcmark-dev libgamemode0 \
    libgl1-mesa-dev libqrencode-dev libtomlplusplus-dev libvulkan-dev \
    libxcb-cursor-dev libxkbcommon-dev libdbus-1-dev \
    libglib2.0-0t64 libgl1 libegl1 libopengl0 \
    libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
    libxcb-render-util0 libxcb-xinerama0 libxkbcommon0 \
 && echo 'C.UTF-8 UTF-8' > /etc/locale.gen \
 && locale-gen \
 && rm -rf /var/lib/apt/lists/*

RUN pip3 install --break-system-packages --no-cache-dir aqtinstall \
 && aqt install-qt \
    ${QT_HOST} ${QT_TARGET} ${QT_VERSION} ${QT_ARCH} \
    --outputdir /opt/qt \
    --modules qtimageformats qtnetworkauth \
 && rm -rf \
    "$QT_PLUGIN_PATH"/designer \
    "$QT_PLUGIN_PATH"/help \
    "$QT_PLUGIN_PATH"/printsupport \
    "$QT_PLUGIN_PATH"/qmllint \
    "$QT_PLUGIN_PATH"/qmlls \
    "$QT_PLUGIN_PATH"/qmltooling \
    "$QT_PLUGIN_PATH"/sqldrivers

COPY build-deb.sh /usr/local/bin/build-deb
RUN chmod +x /usr/local/bin/build-deb

WORKDIR /src
ENTRYPOINT ["/usr/local/bin/build-deb"]
