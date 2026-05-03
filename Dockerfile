# Basis-Image: Debian Bookworm (schlanke Version)
FROM debian:bookworm-slim

# Das ist die User ID deines Host-Systems.
# WICHTIG: Ersetze '1000' hier, falls deine Host-UID anders ist,
# oder übergebe sie beim Build mit --build-arg HOST_UID=<deine_UID>
ARG HOST_UID=1000

# Umgebungsvariablen setzen, um interaktive Abfragen während der Installation zu vermeiden.
ENV DEBIAN_FRONTEND=noninteractive

# 1. Alle benötigten Systemabhängigkeiten als Root installieren.
# Dieser Schritt wird standardmäßig als Root ausgeführt.
RUN apt-get update && apt-get install -y \
    build-essential \
    qt6-base-dev \
    qtchooser \
    qt6-base-dev-tools \
    libqt6core6 \
    libqt6core5compat6-dev \
    libqt6network6 \
    qt6-networkauth-dev \
    cmake \
    ninja-build \
    extra-cmake-modules \
    zlib1g-dev \
    openjdk-17-jdk \
    libgl1-mesa-dev \
    scdoc \
    wget \
    git \
    ca-certificates \
    gpg \
    lsb-release \
    sudo \
    dirmngr \
    sed \
    vim \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Benutzer 'appuser' erstellen und seine UID an die Host-UID anpassen.
# Dadurch erhält der appuser die korrekten Berechtigungen im gemounteten Volume.
RUN useradd -ms /bin/bash -u ${HOST_UID} appuser \
    # Sicherstellen, dass die Gruppe des Benutzers ebenfalls die Host-GID hat.
    && groupadd -g ${HOST_UID} appuser || true \
    && usermod -g ${HOST_UID} appuser

# WICHTIGE ÄNDERUNG: Sicherste sudoers Konfiguration
# Füge "Defaults !requiretty" direkt in /etc/sudoers ein, um sicherzustellen, dass sudo
# niemals ein Terminal anfordert. Dies ist der robusteste Weg.
# Füge dann den NOPASSWD-Eintrag für appuser hinzu.
RUN echo "Defaults !requiretty" >> /etc/sudoers \
    && echo "appuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/appuser_nopasswd \
    && chmod 0440 /etc/sudoers.d/appuser_nopasswd

# Kopiere das vorbereitete, modifizierte Makedeb-Installationsskript in den Container.
# Die Berechtigungen werden hier als Root gesetzt, um Fehler zu vermeiden.
COPY install_makedeb_no_tput.sh /tmp/install_makedeb_no_tput.sh
RUN chmod +x /tmp/install_makedeb_no_tput.sh

# Wechsel zum Nicht-Root-Benutzer 'appuser'.
# Alle nachfolgenden Befehle werden als 'appuser' ausgeführt.
USER appuser
# Setze das Arbeitsverzeichnis des Benutzers auf sein Home-Verzeichnis.
# ALLE Operationen, die nicht mit einem absoluten Pfad beginnen, finden HIER statt.
WORKDIR /home/appuser

# 3. Das Makedeb-Installationsskript als 'appuser' ausführen.
# Das Skript nutzt intern 'sudo', was durch die vorherige Konfiguration funktionieren sollte.
RUN MAKEDEB_RELEASE=makedeb /tmp/install_makedeb_no_tput.sh

# 4. PrismaLauncher-Repository klonen (als 'appuser').
# Da WORKDIR auf /home/appuser gesetzt ist, wird es hier geklont.
RUN git clone https://mpr.makedeb.org/prismlauncher.git

# 5. Wechsel in das geklonte 'prismlauncher'-Verzeichnis.
# Dies ändert den WORKDIR für die nachfolgenden Befehle.
WORKDIR /home/appuser/prismlauncher

# 6. PrismaLauncher mit 'makedeb' bauen (als 'appuser').
RUN makedeb -s

# 7. Die Docker-Shell öffnen, um den Container interaktiv zu nutzen.
CMD ["/bin/bash"]

# Definiere ein Volume, um Daten im Verzeichnis der Dockerfile zu speichern.
# Der Inhalt von /home/appuser im Container wird mit dem Host-Verzeichnis synchronisiert,
# in dem der 'docker run'-Befehl ausgeführt wird.
VOLUME /home/appuser
