#!/usr/bin/env bash
# install-net-tools.sh
# source: https://github.com/mshannaq/debian13.tools/blob/main/network/install-net-tools.sh
# Installs common network monitoring tools on Debian/Ubuntu and RHEL/CentOS/Alma/Rocky families.
# Run as root: sudo bash install-net-tools.sh

set -euo pipefail

# List of tools to install (common names; package names may differ by distro)
DEBIAN_PACKAGES=(iftop nload iptraf-ng vnstat bmon nethogs tcpdump mtr iperf3 ethtool net-tools htop)
RHEL_PACKAGES=(iftop nload iptraf-ng vnstat bmon nethogs tcpdump mtr iperf3 ethtool net-tools htop)

# Helper: print message
info() { echo -e "\n==> $*\n"; }
err()  { echo -e "\nERROR: $*\n" >&2; }

if [ "$(id -u)" -ne 0 ]; then
  err "This script must be run as root. Use sudo."
  exit 1
fi

# Detect package manager / distro family
PKG_MANAGER=""
if command -v apt-get >/dev/null 2>&1; then
  PKG_MANAGER="apt"
elif command -v dnf >/dev/null 2>&1; then
  PKG_MANAGER="dnf"
elif command -v yum >/dev/null 2>&1; then
  PKG_MANAGER="yum"
else
  err "No supported package manager found (apt, dnf, yum). Exiting."
  exit 1
fi

info "Detected package manager: $PKG_MANAGER"

install_debian() {
  info "Updating package lists..."
  apt-get update -y

  info "Installing packages: ${DEBIAN_PACKAGES[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${DEBIAN_PACKAGES[@]}"

  # Enable and start vnstat if installed
  info "Enabling and starting vnstat service..."
  systemctl enable --now vnstat || true
  

  # Some distros use 'iptraf' instead of 'iptraf-ng'
  if ! command -v iptraf-ng >/dev/null 2>&1 && command -v iptraf >/dev/null 2>&1; then
    info "iptraf-ng not found but iptraf is available (ok)."
  fi
}

install_rhel() {
  # Install EPEL if necessary (most monitoring tools are in EPEL)
  info "Ensuring EPEL repository is enabled..."
  if ! rpm -qa | grep -q epel-release; then
    if command -v dnf >/dev/null 2>&1; then
      dnf install -y epel-release || yum install -y epel-release || true
    else
      yum install -y epel-release || true
    fi
  fi

  info "Updating package metadata..."
  if command -v dnf >/dev/null 2>&1; then
    dnf makecache --refresh -y || true
  else
    yum makecache -y || true
  fi

  info "Installing packages: ${RHEL_PACKAGES[*]}"
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y "${RHEL_PACKAGES[@]}" || true
  else
    yum install -y "${RHEL_PACKAGES[@]}" || true
  fi

  # vnstat service enable if present
  info "Enabling and starting vnstat service..."
  systemctl enable --now vnstat || true
  systemctl enable --now vnstatd || true
}

main() {
  case "$PKG_MANAGER" in
    apt)
      install_debian
      ;;
    dnf|yum)
      install_rhel
      ;;
    *)
      err "Unsupported package manager: $PKG_MANAGER"
      exit 2
      ;;
  esac


  info "Basic network tools installed."

  # Optional: show quick usage hints
  cat <<'USAGE'

Installed tools and quick commands:
 - iftop        -> run: sudo iftop -i <interface>
 - nload        -> run: sudo nload <interface>
 - iptraf-ng    -> run: sudo iptraf-ng
 - vnstat       -> show stats: sudo vnstat -i <interface>; realtime: vnstat -l -i <interface>
 - bmon         -> run: sudo bmon
 - nethogs      -> run: sudo nethogs <interface>
 - tcpdump      -> capture: sudo tcpdump -i <interface> -w capture.pcap
 - mtr          -> run: mtr <host>  (or mtr -r <host> for report)
 - iperf3       -> run server: iperf3 -s ; run client: iperf3 -c <server>
 - ethtool      -> show NIC info: sudo ethtool <interface>
 - net-tools    -> legacy tools: ifconfig, netstat
 - htop         -> interactive system monitor

Examples:
 sudo iftop -i eth0
 sudo nload eth0
 sudo vnstat -i eth0
 sudo nethogs eth0

USAGE

  info "Done. If you want, You can modify the script to:
  - install only a subset of tools
  - enable firewall rules for monitoring ports
  - add a systemd timer or cron to collect vnstat reports
  - build a small wrapper script that opens the preferred tool automatically
  "
}

main
