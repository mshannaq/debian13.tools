#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# set-utc.sh
# source: https://github.com/mshannaq/debian13.tools/blob/main/time/set-utc.sh
#
# Purpose: Configure the system timezone to UTC and ensure a single NTP client.
# - Prefers systemd-timesyncd on Debian/Ubuntu.
# - Keeps chrony if it's already active (to avoid fighting over NTP).
# - Logs every step to stdout and /var/log/set-utc.log.
# -----------------------------------------------------------------------------

set -Eeuo pipefail

LOG_FILE="/var/log/set-utc.log"

log() {
  # Log with UTC timestamp to both console and log file
  echo -e "[$(date -u +'%F %T UTC')] $*" | tee -a "$LOG_FILE"
}

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "This script must be run as root. Aborting." >&2
    exit 1
  fi
}

service_active() {
  # Return 0 if service is active, non-zero otherwise
  systemctl is-active --quiet "$1" 2>/dev/null
}

service_exists() {
  # Return 0 if systemd knows about the unit, non-zero otherwise
  systemctl list-unit-files "$1" &>/dev/null
}

install_pkg_if_missing() {
  local pkg="$1"
  if ! dpkg -s "$pkg" &>/dev/null; then
    log "Installing package: $pkg"
    apt-get update -y >>"$LOG_FILE" 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >>"$LOG_FILE" 2>&1
  else
    log "Package already installed: $pkg"
  fi
}

main() {
  require_root

  log "==== Starting UTC & NTP configuration ===="

  # Remember previous timezone target (if any)
  local prev_tz="unknown"
  if [[ -L /etc/localtime ]]; then
    prev_tz="$(readlink -f /etc/localtime || true)"
  fi
  log "Previous /etc/localtime target: ${prev_tz}"

  # 1) Set timezone to UTC
  log "Setting timezone to UTC..."
  timedatectl set-timezone UTC
  log "Timezone set. Verifying:"
  timedatectl | sed -n 's/^\s*Time zone:\s*/Time zone: /p' | tee -a "$LOG_FILE"

  # 2) Ensure exactly one NTP client
  #    If chrony is active, keep it and disable timesyncd.
  #    Otherwise, install+enable systemd-timesyncd and disable chrony.
  if service_active "chrony"; then
    log "Detected active NTP client: chrony. Will keep chrony and disable timesyncd (if present)."
    if service_exists "systemd-timesyncd.service"; then
      systemctl disable --now systemd-timesyncd.service >>"$LOG_FILE" 2>&1 || true
      log "Disabled systemd-timesyncd to avoid conflicts with chrony."
    fi
    # Make sure timedatectl reports NTP on
    timedatectl set-ntp true || true
  else
    log "Chrony not active. Using systemd-timesyncd as NTP client."
    install_pkg_if_missing "systemd-timesyncd"
    systemctl enable --now systemd-timesyncd.service >>"$LOG_FILE" 2>&1
    log "Enabled systemd-timesyncd."
    # Disable chrony if installed to avoid dual-clients
    if dpkg -s chrony &>/dev/null; then
      systemctl disable --now chrony >>"$LOG_FILE" 2>&1 || true
      log "Disabled chrony to avoid conflicts."
    fi
    # Ensure NTP is enabled via timedatectl
    timedatectl set-ntp true || true
  fi

  # 3) (Optional) Set hardware clock to UTC (safe to ignore errors on VMs/containers)
  log "Setting hardware clock to UTC (if supported)..."
  hwclock --systohc >>"$LOG_FILE" 2>&1 || log "hwclock not applicable on this platform (continuing)."

  # 4) Show final status
  log "==== Final status ===="
  timedatectl | tee -a "$LOG_FILE"

  if service_active "systemd-timesyncd.service"; then
    log "NTP client: systemd-timesyncd (active). Timesync status:"
    timedatectl timesync-status 2>>"$LOG_FILE" | tee -a "$LOG_FILE" || \
      (log "timesync-status not available; showing recent logs instead:" && \
       journalctl -u systemd-timesyncd -n 50 --no-pager | tee -a "$LOG_FILE")
  elif service_active "chrony"; then
    log "NTP client: chrony (active). Tracking/sources:"
    if command -v chronyc >/dev/null; then
      chronyc tracking | tee -a "$LOG_FILE"
      chronyc sources -v | tee -a "$LOG_FILE"
    else
      log "chronyc is not available, but chrony service is active."
    fi
  else
    log "WARNING: No active NTP client detected. Consider installing chrony or systemd-timesyncd."
  fi

  log "==== Completed. Log saved to $LOG_FILE ===="
}

main "$@"
