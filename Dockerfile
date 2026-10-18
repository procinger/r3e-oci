# syntax=docker/dockerfile:1
FROM ubuntu:24.04

ARG TARGETARCH
ARG PROTON_VERSION=GE-Proton11-9

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN <<'INSTALL_PACKAGES'
set -eu
export DEBIAN_FRONTEND=noninteractive

test "${TARGETARCH:-amd64}" = amd64
dpkg --add-architecture i386
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    cabextract \
    curl \
    fonts-liberation \
    lib32gcc-s1 \
    lib32stdc++6 \
    libasound2t64 libasound2t64:i386 \
    libgl1 libgl1:i386 \
    libvulkan1 libvulkan1:i386 \
    libwine libwine:i386 \
    nginx \
    python3 \
    tini \
    xauth \
    xvfb
rm -rf /var/lib/apt/lists/*
INSTALL_PACKAGES

RUN <<'INSTALL_STEAMCMD'
set -eu
mkdir -p /opt/steamcmd
curl -fsSL --retry 3 \
    https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
    | tar -xz -C /opt/steamcmd
INSTALL_STEAMCMD

RUN <<'INSTALL_PROTON'
set -eu
release_url="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_VERSION}"
archive="${PROTON_VERSION}-x86_64.tar.gz"

mkdir -p /opt/proton
cd /tmp
curl -fsSL --retry 3 -O "${release_url}/${archive}"
curl -fsSL --retry 3 -O "${release_url}/${PROTON_VERSION}-x86_64.sha512sum"
sha512sum -c "${PROTON_VERSION}-x86_64.sha512sum"
tar -xzf "$archive" -C /opt/proton --strip-components=1
rm "$archive" "${PROTON_VERSION}-x86_64.sha512sum"
INSTALL_PROTON

ARG WINETRICKS_VERSION=20260125
ARG WINETRICKS_REVISION=b76e1ee79ac57d7aceb384f74518fc423265810c

RUN <<'INSTALL_WINETRICKS'
set -eu
curl -fsSL --retry 3 \
    "https://raw.githubusercontent.com/Winetricks/winetricks/${WINETRICKS_REVISION}/src/winetricks" \
    -o /usr/local/bin/winetricks
# Check that the pinned commit contains the declared release.
grep -Fx "WINETRICKS_VERSION=${WINETRICKS_VERSION}" /usr/local/bin/winetricks
chmod 755 /usr/local/bin/winetricks
INSTALL_WINETRICKS

RUN <<'CREATE_USER'
set -eu
userdel -r ubuntu
useradd --uid 1000 --create-home --shell /bin/bash steam
# Let the unprivileged entrypoint initialize this file at startup.
install -o steam -g steam -m 0644 /dev/null /etc/machine-id
mkdir -p /data /opt/raceroom
chown -R steam:steam /opt/steamcmd /opt/raceroom /data
CREATE_USER

# Persistent home, Windows prefix and Steam identity.
ENV HOME=/data/home \
    STEAM_COMPAT_CLIENT_INSTALL_PATH=/opt/steamcmd \
    STEAM_COMPAT_DATA_PATH=/data/compatdata \
    WINEPREFIX=/data/dotnet48 \
    SteamAppId=354060 \
    SteamGameId=354060

# Headless rendering and server startup defaults.
ENV PROTON_USE_WINED3D=1 \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES=mscoree=n,b \
    UPDATE_ON_START=true \
    SERVER_EXE=RRRE_Dedicated.exe

COPY --chmod=755 scripts/entrypoint.sh /usr/local/bin/entrypoint

USER 1000:1000
WORKDIR /data

RUN <<'PREPARE_DOTNET'
set -eu
# Use the same initialization for Wine during the build, then clear the ID below.
source /usr/local/bin/entrypoint
prepare_machine_id
mkdir -p "$HOME" "$WINEPREFIX"
env WINE=/opt/proton/files/bin/wine \
    WINESERVER=/opt/proton/files/bin/wineserver \
    WINEDLLOVERRIDES=mscoree=d \
    xvfb-run -a winetricks -q dotnet48
WINEPREFIX="$WINEPREFIX" /opt/proton/files/bin/wineserver -w
tar -cf /opt/raceroom/dotnet48-prefix.tar -C "$WINEPREFIX" .
rm -rf "$WINEPREFIX" "$HOME/.cache/winetricks"
: > /etc/machine-id
PREPARE_DOTNET

COPY scripts/nginx.conf /etc/raceroom-nginx.conf

EXPOSE 8080/tcp 60000/udp 60001/tcp 60002/udp

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/entrypoint"]
