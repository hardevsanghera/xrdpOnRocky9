#!/usr/bin/env bash
# Convert a Rocky Linux 9 server installation into a graphical workstation
# and configure xrdp for RDP access.
#
# Run as a user with sudo privileges:
#   bash setup-rocky9-xrdp.sh
#
# The script performs the work in two stages:
#   1. Updates the OS, installs the Workstation group, sets graphical boot,
#      installs a post-reboot continuation service, and reboots.
#   2. Installs and configures xrdp after the reboot, then verifies port 3389.
#
# GNOME is configured to use X11 by default because this generally provides
# the most reliable xrdp session on Rocky Linux 9.
# To avoid changing the GDM Wayland setting:
#   FORCE_X11=false bash setup-rocky9-xrdp.sh
#
# Progress and command output are appended to:
#   /var/log/rocky-xrdp-setup.log
# Follow setup progress with:
#   sudo tail -f /var/log/rocky-xrdp-setup.log

set -Eeuo pipefail

STATE_FILE="/var/lib/rocky-xrdp-setup.state"
INSTALLED_SCRIPT="/usr/local/sbin/rocky-xrdp-setup.sh"
CONTINUATION_UNIT="/etc/systemd/system/rocky-xrdp-setup.service"
LOG_FILE="/var/log/rocky-xrdp-setup.log"
FORCE_X11="${FORCE_X11:-true}"

if [[ "${EUID}" -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

log() {
    printf '\n[%s] ==> %s\n' "$(date '+%Y-%m-%d %H:%M:%S%z')" "$1"
}

run_root() {
    if [[ -n "${SUDO}" ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

start_logging() {
    run_root install -d -m 0755 "$(dirname "${LOG_FILE}")"
    run_root touch "${LOG_FILE}"
    run_root chmod 0644 "${LOG_FILE}"
    exec > >(run_root tee -a "${LOG_FILE}") 2>&1

    log "Starting setup (script: ${SCRIPT_PATH}; log: ${LOG_FILE})"
    trap 'status=$?; log "ERROR: command failed with exit ${status} at line ${LINENO}: ${BASH_COMMAND}"; exit "${status}"' ERR
}

install_continuation_service() {
    log "Installing the post-reboot continuation service"

    run_root install -D -m 0755 "${SCRIPT_PATH}" "${INSTALLED_SCRIPT}"

    run_root tee "${CONTINUATION_UNIT}" >/dev/null <<EOF
[Unit]
Description=Continue Rocky Linux workstation and xrdp setup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=FORCE_X11=${FORCE_X11}
ExecStart=${INSTALLED_SCRIPT} --resume

[Install]
WantedBy=multi-user.target
EOF

    run_root systemctl daemon-reload
    run_root systemctl enable rocky-xrdp-setup.service
}

configure_x11() {
    if [[ "${FORCE_X11}" != "true" ]]; then
        return
    fi

    log "Configuring GNOME to use X11 for xrdp"
    local gdm_config=/etc/gdm/custom.conf
    run_root cp -a "${gdm_config}" "${gdm_config}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true

    if run_root grep -qE '^WaylandEnable=' "${gdm_config}" 2>/dev/null; then
        run_root sed -i 's/^WaylandEnable=.*/WaylandEnable=false/' "${gdm_config}"
    elif run_root grep -qE '^\[daemon\]' "${gdm_config}" 2>/dev/null; then
        run_root sed -i '/^\[daemon\]/a WaylandEnable=false' "${gdm_config}"
    else
        printf '\n[daemon]\nWaylandEnable=false\n' | run_root tee -a "${gdm_config}" >/dev/null
    fi
}

stage_one() {
    log "Checking Rocky Linux version"
    if [[ -r /etc/rocky-release ]]; then
        cat /etc/rocky-release
    else
        echo "Warning: /etc/rocky-release was not found; continuing anyway." >&2
    fi

    log "Applying operating-system updates"
    run_root dnf clean all
    run_root dnf makecache --refresh
    run_root dnf upgrade -y

    log "Installing the Workstation package group"
    run_root dnf group install -y "Workstation"

    log "Setting graphical boot as the default"
    run_root systemctl set-default graphical.target

    run_root install -d -m 0755 /var/lib
    printf 'post-reboot\n' | run_root tee "${STATE_FILE}" >/dev/null
    install_continuation_service

    log "Rebooting; xrdp setup will continue automatically after startup"
    run_root systemctl reboot
}

stage_two() {
    log "Applying updates after installing the Workstation group"
    run_root dnf clean packages
    run_root dnf clean metadata
    run_root dnf makecache --refresh
    run_root dnf upgrade -y

    log "Enabling CRB and installing EPEL"
    run_root dnf install -y dnf-plugins-core
    run_root dnf config-manager --set-enabled crb
    run_root dnf install -y epel-release

    log "Installing xrdp and Xorg integration"
    run_root dnf install -y xrdp xorgxrdp

    configure_x11

    log "Enabling and starting xrdp"
    run_root systemctl enable --now xrdp

    if run_root systemctl is-active --quiet firewalld; then
        log "Allowing inbound RDP through firewalld"
        run_root firewall-cmd --permanent --add-port=3389/tcp
        run_root firewall-cmd --reload
    else
        echo "firewalld is not active; no firewall rule was required."
    fi

    log "Verifying xrdp"
    run_root systemctl --no-pager --full status xrdp || true

    if ! run_root ss -ltnp | grep -q ':3389'; then
        echo "ERROR: xrdp is not listening on TCP port 3389." >&2
        echo "Review: sudo journalctl -u xrdp -b --no-pager" >&2
        exit 1
    fi

    #Sneak in a vscode install
    log "Installing vscode"
    run_root rpm --import https://packages.microsoft.com/keys/microsoft.asc &&
    echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
    run_root dnf install -y --refresh code # or code-insiders

    log "Cleaning up the continuation service"
    run_root systemctl disable rocky-xrdp-setup.service || true
    run_root rm -f "${CONTINUATION_UNIT}"
    run_root systemctl daemon-reload
    run_root rm -f "${STATE_FILE}"

    log "Setup completed successfully"
    echo "Rocky Linux Workstation and xrdp are ready."
    echo "Connect your RDP client to this VM on TCP port 3389."
}

start_logging

if [[ "${1:-}" == "--resume" ]] || [[ -f "${STATE_FILE}" ]]; then
    stage_two
else
    stage_one
fi
