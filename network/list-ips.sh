#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# list-ips.sh
# source: https://github.com/mshannaq/debian13.tools/blob/main/network/list-ips.sh
# Purpose: List active IPv4/IPv6 addresses on the host.
# Defaults:
#   - Show only non-loopback interfaces.
#   - Show only global-scope addresses (skip IPv6 link-local).
# Options:
#   -A, --all          Include loopback + link-local addresses.
#   -c, --cidr         Keep CIDR suffix (e.g., /24, /64).
#   -1, --one-per-line Print addresses only, one per line (no grouping).
#   -h, --help         Show usage.
# -----------------------------------------------------------------------------

set -Eeuo pipefail

SHOW_ALL=0
SHOW_CIDR=0
ONE_PER_LINE=0

usage() {
  cat <<'USAGE'
Usage: list-ips.sh [options]

List active IPv4/IPv6 addresses.
Defaults: exclude loopback and IPv6 link-local; group by interface.

Options:
  -A, --all           Include loopback and link-local addresses.
  -c, --cidr          Keep CIDR suffix (e.g., /24, /64).
  -1, --one-per-line  Print addresses only, one per line.
  -h, --help          Show this help.

Examples:
  list-ips.sh
  list-ips.sh --cidr
  list-ips.sh --all --one-per-line
USAGE
}

for arg in "$@"; do
  case "$arg" in
    -A|--all) SHOW_ALL=1 ;;
    -c|--cidr) SHOW_CIDR=1 ;;
    -1|--one-per-line) ONE_PER_LINE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage; exit 1 ;;
  esac
done

command -v ip >/dev/null 2>&1 || { echo "ERROR: 'ip' command not found." >&2; exit 1; }

strip_cidr() {
  local cidr="$1"
  if [[ $SHOW_CIDR -eq 1 ]]; then
    printf "%s" "$cidr"
  else
    printf "%s" "${cidr%%/*}"
  fi
}

# Build commands for IPv4/IPv6
if [[ $SHOW_ALL -eq 1 ]]; then
  CMD4=(ip -o -4 addr show up)
  CMD6=(ip -o -6 addr show up)
  FILTER_LO='cat'   # don't filter loopback
  FILTER_SCOPE='cat' # don't filter by scope
else
  CMD4=(ip -o -4 addr show scope global up)
  CMD6=(ip -o -6 addr show scope global up)
  FILTER_LO="grep -vE ' lo '"
  FILTER_SCOPE='cat'
fi

# Collect addresses
declare -A V4_BY_IF
declare -A V6_BY_IF

# IPv4
while read -r line; do
  [[ -n "$line" ]] || continue
  # Example: "2: eth0    inet 198.51.100.10/24 brd ... scope global eth0 ..."
  IFACE=$(awk '{print $2}' <<<"$line")
  [[ $SHOW_ALL -eq 1 ]] || [[ "$IFACE" != "lo" ]] || continue
  ADDR=$(awk '{print $4}' <<<"$line")
  ADDR=$(strip_cidr "$ADDR")
  V4_BY_IF["$IFACE"]+="${V4_BY_IF[$IFACE]:+ }$ADDR"
done < <("${CMD4[@]}" | bash -c "$FILTER_LO")

# IPv6
while read -r line; do
  [[ -n "$line" ]] || continue
  # Example: "2: eth0    inet6 2001:db8::1/64 scope global ..."
  IFACE=$(awk '{print $2}' <<<"$line")
  [[ $SHOW_ALL -eq 1 ]] || [[ "$IFACE" != "lo" ]] || continue
  # Skip link-local explicitly when not --all
  if [[ $SHOW_ALL -eq 0 ]] && grep -q 'scope link' <<<"$line"; then
    continue
  fi
  ADDR=$(awk '{print $4}' <<<"$line")
  ADDR=$(strip_cidr "$ADDR")
  V6_BY_IF["$IFACE"]+="${V6_BY_IF[$IFACE]:+ }$ADDR"
done < <("${CMD6[@]}" | bash -c "$FILTER_LO" | bash -c "$FILTER_SCOPE")

# Print
if [[ $ONE_PER_LINE -eq 1 ]]; then
  for IFACE in "${!V4_BY_IF[@]}"; do
    for A in ${V4_BY_IF[$IFACE]}; do echo "$A"; done
  done
  for IFACE in "${!V6_BY_IF[@]}"; do
    for A in ${V6_BY_IF[$IFACE]}; do echo "$A"; done
  done
  exit 0
fi

# Grouped output
echo "IPv4:"
if [[ ${#V4_BY_IF[@]} -eq 0 ]]; then
  echo "  (none)"
else
  for IFACE in "${!V4_BY_IF[@]}"; do
    echo "  - ${IFACE}: ${V4_BY_IF[$IFACE]}"
  done
fi

echo "IPv6:"
if [[ ${#V6_BY_IF[@]} -eq 0 ]]; then
  echo "  (none)"
else
  for IFACE in "${!V6_BY_IF[@]}"; do
    echo "  - ${IFACE}: ${V6_BY_IF[$IFACE]}"
  done
fi
