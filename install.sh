#!/usr/bin/env bash
#
# Installs VeilLink as a systemd service.
#
#   sudo ./install.sh              install, or upgrade an existing installation
#   sudo ./install.sh --uninstall  remove the service (keeps the configuration)
#
set -euo pipefail
umask 022

SERVICE=veillink
SERVICE_USER=veillink
INSTALL_DIR=/opt/veillink
CONFIG_DIR=/etc/veillink
STATE_DIR=/var/lib/$SERVICE
UNIT_FILE=/etc/systemd/system/$SERVICE.service
SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

die() {
    echo "error: $*" >&2
    exit 1
}

usage() {
    echo "usage: sudo $0 [--uninstall]"
}

check_system() {
    [[ $EUID -eq 0 ]] || die "must be run as root (try: sudo $0${*:+ $*})"
    [[ -d /run/systemd/system ]] || die "systemd is not running on this system"
}

install_service() {
    local erl erlc
    if ! erl=$(command -v erl) || ! erlc=$(command -v erlc); then
        die "erl/erlc not found; install Erlang/OTP first (the 'erlang' package on most distributions)"
    fi

    echo "Compiling main.erl..."
    BUILD_DIR=$(mktemp -d)
    trap 'rm -rf "$BUILD_DIR"' EXIT
    "$erlc" -o "$BUILD_DIR" "$SOURCE_DIR/main.erl"

    if ! id -u "$SERVICE_USER" &>/dev/null; then
        echo "Creating system user $SERVICE_USER..."
        useradd --system --user-group --no-create-home --home-dir "$STATE_DIR" \
            --shell "$(command -v nologin || echo /bin/false)" \
            --comment "VeilLink proxy" "$SERVICE_USER"
    fi

    echo "Installing to $INSTALL_DIR..."
    install -d -m 0755 "$INSTALL_DIR" "$CONFIG_DIR"
    install -m 0644 "$BUILD_DIR/main.beam" "$INSTALL_DIR/main.beam"
    if [[ -e $CONFIG_DIR/config.csv ]]; then
        echo "Keeping existing configuration in $CONFIG_DIR/config.csv"
    else
        install -m 0644 "$SOURCE_DIR/config.csv" "$CONFIG_DIR/config.csv"
        echo "Installed default configuration to $CONFIG_DIR/config.csv"
    fi

    echo "Writing $UNIT_FILE..."
    cat >"$UNIT_FILE" <<EOF
[Unit]
Description=VeilLink TCP/UDP forwarding proxy
Documentation=https://github.com/BradyHodge/veilLink
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
# main.erl reads config.csv from its working directory.
WorkingDirectory=$CONFIG_DIR
ExecStart=$erl -noinput -pa $INSTALL_DIR -s main start
Environment=HOME=$STATE_DIR
Environment=ERL_CRASH_DUMP=$STATE_DIR/erl_crash.dump
StateDirectory=$SERVICE
# Signal only the VM on stop; it shuts down its helper processes itself.
KillMode=mixed
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

# Lets the unprivileged user listen on ports below 1024.
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE"
    systemctl restart "$SERVICE"

    # Type=simple counts the service as started as soon as erl is forked, so
    # give the VM time to boot before checking whether it stayed up.
    sleep 3
    if ! systemctl is-active --quiet "$SERVICE"; then
        journalctl -u "$SERVICE" -n 20 --no-pager >&2 || true
        die "$SERVICE failed to start; see the log above"
    fi

    cat <<EOF

VeilLink is running and will start at boot.
  Config: $CONFIG_DIR/config.csv (apply changes with: sudo systemctl restart $SERVICE)
  Logs:   journalctl -u $SERVICE -f
EOF
}

uninstall_service() {
    systemctl disable --now "$SERVICE" 2>/dev/null || true
    rm -f "$UNIT_FILE"
    systemctl daemon-reload
    systemctl reset-failed "$SERVICE" 2>/dev/null || true
    rm -rf "$INSTALL_DIR" "$STATE_DIR"
    if id -u "$SERVICE_USER" &>/dev/null; then
        userdel "$SERVICE_USER"
    fi
    echo "VeilLink has been removed. Its configuration was left in $CONFIG_DIR."
}

case ${1:-} in
    "")
        check_system
        install_service
        ;;
    --uninstall)
        check_system "$@"
        uninstall_service
        ;;
    -h | --help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
