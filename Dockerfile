# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
# Keep the Proton release and its Wine submodule revision in sync.
ARG PROTON_VERSION=GE-Proton11-11
ARG WINE_REVISION=c53678ab22a85f0fad3588dd34f0452a463bd015

###### wine-build
FROM ubuntu:26.04@sha256:19fcd1bf268f02b60aca3bd30bd8a6d9a11759a430e32921833e65f16d87348a AS wine-build

ARG WINE_REVISION
ARG PROTON_VERSION
ARG TARGETARCH
ARG BUILD_JOBS=4

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# The binary overlay must match the runtime's Wine source revision.
RUN set -eu \
    && test "${TARGETARCH:-amd64}" = amd64 \
    && test "$PROTON_VERSION" = GE-Proton11-11 \
    && test "$WINE_REVISION" = c53678ab22a85f0fad3588dd34f0452a463bd015

RUN set -eu \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        autoconf \
        bison \
        flex \
        ca-certificates \
        curl \
        git \
        pkg-config \
        python3 \
        gcc-mingw-w64-x86-64 \
        g++-mingw-w64-x86-64 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src/wine

RUN set -eu \
    && curl -fsSL --retry 3 \
        "https://codeload.github.com/ValveSoftware/wine/tar.gz/${WINE_REVISION}" \
        | tar -xz --strip-components=1

RUN set -eu \
    && autoreconf -f \
    && tools/make_requests \
    && dlls/winevulkan/make_vulkan \
    && tools/make_specfiles

WORKDIR /build/wine64

RUN set -eu \
    && /src/wine/configure --enable-win64 --without-x --without-freetype

RUN set -eu \
    && make -j${BUILD_JOBS} dlls/httpapi/x86_64-windows/httpapi.dll \
    && mkdir -p /out/baseline/x86_64-windows \
    && cp dlls/httpapi/x86_64-windows/httpapi.dll /out/baseline/x86_64-windows/

COPY patches/wine/0001-httpapi-synchronous-send-iocp.patch /tmp/httpapi.patch

RUN set -eu \
    && cd /src/wine \
    && git apply --check /tmp/httpapi.patch \
    && git apply /tmp/httpapi.patch

RUN set -eu \
    && make -j${BUILD_JOBS} \
        dlls/httpapi/x86_64-windows/httpapi.dll \
        dlls/httpapi/tests/x86_64-windows/httpapi_test.exe \
    && mkdir -p /out/patched/x86_64-windows /out/tests \
    && cp dlls/httpapi/x86_64-windows/httpapi.dll /out/patched/x86_64-windows/ \
    && cp dlls/httpapi/tests/x86_64-windows/httpapi_test.exe /out/tests/ \
    && printf '%s\n' "$WINE_REVISION" > /out/wine-revision

###### proton-runtime
FROM ubuntu:26.04@sha256:19fcd1bf268f02b60aca3bd30bd8a6d9a11759a430e32921833e65f16d87348a AS proton-runtime

ARG TARGETARCH
ARG PROTON_VERSION

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -eu \
    && export DEBIAN_FRONTEND=noninteractive \
    && test "${TARGETARCH:-amd64}" = amd64 \
    && dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
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
        openssl \
        python3 \
        tini \
        xauth \
        xvfb \
    && rm -rf /var/lib/apt/lists/*

RUN set -eu \
    && mkdir -p /opt/steamcmd \
    && curl -fsSL --retry 3 \
        https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
        | tar -xz -C /opt/steamcmd

RUN set -eu \
    && release_url="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_VERSION}" \
    && archive="${PROTON_VERSION}-x86_64.tar.gz" \
    && mkdir -p /opt/proton \
    && cd /tmp \
    && curl -fsSL --retry 3 -O "${release_url}/${archive}" \
    && curl -fsSL --retry 3 -O "${release_url}/${PROTON_VERSION}-x86_64.sha512sum" \
    && sha512sum -c "${PROTON_VERSION}-x86_64.sha512sum" \
    && tar -xzf "$archive" -C /opt/proton --strip-components=1 \
    && rm "$archive" "${PROTON_VERSION}-x86_64.sha512sum"

# HTTPAPI is overlaid before the .NET prefix template is initialized.
COPY --from=wine-build /out/patched/x86_64-windows/httpapi.dll /opt/proton/files/lib/wine/x86_64-windows/httpapi.dll


###### httpapi-test
FROM proton-runtime AS httpapi-test

COPY --from=wine-build /out/tests/ /opt/httpapi-tests/
COPY --chmod=755 patches/wine/run-httpapi-tests.sh /opt/httpapi-tests/run

# Use a fresh prefix as an unprivileged user, without installing .NET.
RUN set -eu \
    && useradd --uid 1001 --create-home --shell /bin/bash httpapi-test \
    && python3 -c 'import uuid; print(uuid.uuid4().hex)' > /etc/machine-id

USER 1001:1001

ENV HOME=/home/httpapi-test
ENTRYPOINT ["/opt/httpapi-tests/run"]

###### final-image
FROM proton-runtime AS runtime

ARG WINETRICKS_VERSION=20260125
ARG WINETRICKS_REVISION=b76e1ee79ac57d7aceb384f74518fc423265810c

# Check that the pinned commit contains the declared release.
RUN set -eu \
    && curl -fsSL --retry 3 \
        "https://raw.githubusercontent.com/Winetricks/winetricks/${WINETRICKS_REVISION}/src/winetricks" \
        -o /usr/local/bin/winetricks \
    && grep -Fx "WINETRICKS_VERSION=${WINETRICKS_VERSION}" /usr/local/bin/winetricks \
    && chmod 755 /usr/local/bin/winetricks

# Let the unprivileged entrypoint initialize this file at startup.
RUN set -eu \
    && userdel -r ubuntu \
    && useradd --uid 1000 --create-home --shell /bin/bash steam \
    && install -o steam -g steam -m 0644 /dev/null /etc/machine-id \
    && mkdir -p /data /opt/raceroom \
    && chown -R steam:steam /opt/steamcmd /opt/raceroom /data

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

# Use the same initialization for Wine during the build, then clear the ID below.
RUN set -eu \
    && source /usr/local/bin/entrypoint \
    && prepare_machine_id \
    && mkdir -p "$HOME" "$WINEPREFIX" \
    && env WINE=/opt/proton/files/bin/wine \
        WINESERVER=/opt/proton/files/bin/wineserver \
        WINEDLLOVERRIDES=mscoree=d \
        xvfb-run -a winetricks -q dotnet48 \
    && WINEPREFIX="$WINEPREFIX" /opt/proton/files/bin/wineserver -w \
    && tar -cf /opt/raceroom/dotnet48-prefix.tar -C "$WINEPREFIX" . \
    && rm -rf "$WINEPREFIX" "$HOME/.cache/winetricks" \
    && : > /etc/machine-id

COPY scripts/nginx.conf /etc/raceroom-nginx.conf

EXPOSE 8080/tcp 60000/udp 60001/tcp 60002/udp

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/entrypoint"]
