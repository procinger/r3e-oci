#!/usr/bin/env bash
set -Eeuo pipefail

readonly SERVER_DIR=/data/server
readonly STEAMCMD=/opt/steamcmd/steamcmd.sh
readonly WINE=/opt/proton/files/bin/wine
readonly DOTNET_TEMPLATE=/opt/raceroom/dotnet48-prefix.tar
readonly MAX_INSTALL_ATTEMPTS=3

prepare_machine_id() {
    local machine_id_file=/etc/machine-id
    local current_id=""

    if [[ -r "$machine_id_file" ]]; then
        current_id=$(< "$machine_id_file")
    fi

    # Keep valid IDs, including IDs supplied through a read-only mount.
    if [[ "$current_id" =~ ^[0-9a-f]{32}$ && "$current_id" != 00000000000000000000000000000000 ]]; then
        return 0
    fi

    # The image provides an empty file writable by UID 1000.
    python3 -c 'import uuid; print(uuid.uuid4().hex)' > "$machine_id_file"
}

prepare_directories() {
    umask 0027
    mkdir -p "$HOME" "$WINEPREFIX" "$SERVER_DIR"
}

install_server() {
    local attempt

    echo 'Installing/updating RaceRoom Dedicated Server (354060)...'

    # A fresh SteamCMD cache can return "Missing configuration" on first login.
    # Retry failures, but never start the server after an incomplete installation.
    for ((attempt = 1; attempt <= MAX_INSTALL_ATTEMPTS; attempt++)); do
        if "$STEAMCMD" \
            +@ShutdownOnFailedCommand 1 \
            +@NoPromptForPassword 1 \
            +@sSteamCmdForcePlatformType windows \
            +@sSteamCmdForcePlatformBitness 64 \
            +force_install_dir "$SERVER_DIR" \
            +login anonymous \
            +app_info_update 1 \
            +app_update 354060 validate \
            +quit; then
            return 0
        fi

        echo "SteamCMD attempt ${attempt}/${MAX_INSTALL_ATTEMPTS} failed." >&2
    done

    return 1
}

update_server_if_enabled() {
    case "$UPDATE_ON_START" in
        true)  install_server ;;
        false) return 0 ;;
        *)
            echo 'UPDATE_ON_START must be true or false.' >&2
            return 1
            ;;
    esac
}

check_server_executable() {
    if [[ ! -f "$SERVER_DIR/$SERVER_EXE" ]]; then
        echo "Missing $SERVER_DIR/$SERVER_EXE. Check SteamCMD logs or SERVER_EXE." >&2
        return 1
    fi
}

link_steam_libraries() {
    local arch library

    # Some Steamworks applications look for client libraries in the home directory.
    mkdir -p "$HOME/.steam/sdk32" "$HOME/.steam/sdk64"

    for arch in 32 64; do
        library="/opt/steamcmd/linux${arch}/steamclient.so"
        if [[ -f "$library" ]]; then
            ln -sf "$library" "$HOME/.steam/sdk${arch}/steamclient.so"
        fi
    done
}

prepare_dotnet_runtime() {
    local marker="$WINEPREFIX/.raceroom-dotnet48-ready"

    if [[ -f "$marker" ]]; then
        return 0
    fi

    # Preserve existing installations and fail rather than overwrite an unknown prefix.
    if [[ -n $(find "$WINEPREFIX" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
        echo "Wine prefix $WINEPREFIX is not empty and has no .NET readiness marker. Use an empty prefix or restore a known working one." >&2
        return 1
    fi

    echo 'Initializing Wine prefix from the .NET 4.8 template included in the image...'
    tar --no-same-owner -xf "$DOTNET_TEMPLATE" -C "$WINEPREFIX"
    touch "$marker"
}

check_terminal() {
    if [[ ! -t 1 ]]; then
        echo 'RaceRoom with native .NET requires a terminal. Use docker run -t or Kubernetes tty: true.' >&2
        return 1
    fi
}

start_server() {
    cd "$SERVER_DIR"
    echo "Starting $SERVER_EXE with Proton Wine and native .NET; prefix: $WINEPREFIX"

    # Expose the Windows application's loopback-only administration through Nginx.
    nginx -c /etc/raceroom-nginx.conf

    # Replace this shell so Tini can forward signals to the server process group.
    exec xvfb-run -a -s '-screen 0 1024x768x24 -nolisten tcp' \
        "$WINE" "$PWD/$SERVER_EXE" "$@"
}

main() {
    check_terminal
    prepare_machine_id
    prepare_directories
    update_server_if_enabled
    check_server_executable
    link_steam_libraries
    prepare_dotnet_runtime
    start_server "$@"
}

# Allow the image build to reuse initialization without starting the server.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
