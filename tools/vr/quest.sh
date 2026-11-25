#!/bin/bash
# Run on the build machine (Linux x86_64 with Docker or Podman and a Vulkan GPU). Plays Child of Eden (VR fork) on a
# Meta Quest 2 over Wi-Fi with WiVRn.
#   bash quest.sh             starts the server; when the headset connects (WiVRn app) it launches the game. Ctrl+C to quit.
#   bash quest.sh --dry-run   only checks what is needed and says what it would do; touches nothing.
#   bash quest.sh --test      runs 25 s WITHOUT opening the firewall, to check that the server ends up listening.
# While it runs it opens port 9757 (TCP and UDP) in ufw for the local network only, and closes it on exit (needs
# passwordless sudo for ufw).
# Variables: QUEST_HZ (120; game fps, half of that per eye), QUEST_SCALE (100; game units per meter),
#   QUEST_HEAD (1; 0 = always the floating screen), QUEST_AVAHI (0; 1 = announce on the network), QUEST_ENV (extra "VAR=value ..."),
#   QUEST_IFACE (network interface the headset reaches; default: the one of the default route),
#   QUEST_LAN (CIDR allowed through the firewall; default: the network of that interface).
# NOTE: the original hard-coded the wired interface and the LAN range of the development machine; the two defaults above
# replace them and have not been run. --group-add 44 / 990 are that machine's `video` / `render` GIDs (see tools/test/run.sh).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; WORK="${EDEN_WORK:-$ROOT/work}"; ENGINE="${ENGINE:-docker}"
MODE=${1:-}
IFACE=${QUEST_IFACE:-$(ip -4 route show default 2>/dev/null | awk '{for (i=1;i<NF;i++) if ($i=="dev") {print $(i+1); exit}}')}
IP=$(ip -4 -o addr show "$IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
LAN=${QUEST_LAN:-$(ip -4 route show dev "$IFACE" scope link 2>/dev/null | awk '$1 ~ /\// {print $1; exit}')}
fail() { echo "ERROR: $1" >&2; exit 1; }
[ -x "$WORK/wivrn/bin/wivrn-server" ] || fail "$WORK/wivrn/bin/wivrn-server is missing. Build it with: bash $ROOT/tools/build/build_wivrn.sh"
[ -x "$WORK/build-xr/eden" ] || fail "$WORK/build-xr/eden is missing. Build it with: bash $ROOT/tools/build/build_xr.sh"
[ -d "$WORK/game" ] || fail "$WORK/game is missing (game data)."
$ENGINE image inspect eden-recomp:wivrn >/dev/null 2>&1 || fail "the image eden-recomp:wivrn is missing. Create it with: bash $ROOT/containers/build_images.sh --vr"
[ -n "$IP" ] || fail "could not find the IP address of the interface '${IFACE:-?}'. Check: ip -4 addr (or set QUEST_IFACE)"
[ -n "$LAN" ] || fail "could not work out the local network of '$IFACE'. Set QUEST_LAN=<network>/<prefix>"
exec 9> /tmp/eden-quest.lock
flock -n 9 || fail "a quest.sh is already running (lock /tmp/eden-quest.lock). Close it first."
$ENGINE ps --format '{{.Image}}' | grep -q 'eden-recomp:' && fail "another eden container is running ($ENGINE ps). Two are never run at once."
echo "On the Quest 2: open the WiVRn app (v26.9, Meta Store) and connect to $IP (port 9757)."
if [ "$MODE" = --dry-run ]; then
  echo "[dry-run] would open 9757/tcp and 9757/udp for $LAN (ufw), start wivrn-server in the image eden-recomp:wivrn and close everything on exit."
  exit 0
fi
RULE=0
cleanup() {
  $ENGINE stop -t 5 eden-quest >/dev/null 2>&1
  if [ $RULE = 1 ]; then
    sudo -n ufw delete allow from $LAN to any port 9757 >/dev/null 2>&1 && echo "firewall: port 9757 closed again"
  fi
}
trap cleanup EXIT
if [ "$MODE" != --test ]; then
  sudo -n ufw allow from $LAN to any port 9757 comment 'WiVRn Quest (temporary, quest.sh)' >/dev/null \
    || fail "could not open port 9757 in ufw. By hand: sudo ufw allow from $LAN to any port 9757"
  RULE=1
fi
AVAHI=""; [ "${QUEST_AVAHI:-0}" = 1 ] && AVAHI="-v /run/dbus/system_bus_socket:/run/dbus/system_bus_socket"
[ "$MODE" = --test ] && ( sleep 25; $ENGINE stop -t 3 eden-quest >/dev/null 2>&1 ) &
mkdir -p "$WORK/wivrn-cfg" "$WORK/shots"   # headset pairing (WiVRn keys): kept between runs, outside git
rm -f "$WORK/build-xr/quest_wivrn.log"
( for i in $(seq 1 40); do sleep 1; L=$(grep -m1 "PIN code" "$WORK/build-xr/quest_wivrn.log" 2>/dev/null) && { echo ">>> First time: $L (type it on the headset)"; break; }; done ) &
$ENGINE run --rm --init --name eden-quest --network host --shm-size=3g --device /dev/dri --group-add 44 --group-add 990 --user $(id -u):$(id -g) \
  -m 10g --cpus 8 -e HOME=/tmp -e QUEST_HZ=${QUEST_HZ:-120} -e QUEST_SCALE=${QUEST_SCALE:-100} -e QUEST_HEAD=${QUEST_HEAD:-1} \
  -e QUEST_AVAHI=${QUEST_AVAHI:-0} -e QUEST_ENV="${QUEST_ENV:-}" $AVAHI \
  -v "$WORK/wivrn-cfg:/tmp/cfg/wivrn" -v "$WORK/wivrn:/w:ro" -v "$WORK/build-xr:/b" -v "$WORK/game:/assets:ro" -v "$WORK/shots:/c" -v "$ROOT/tools:/s:ro" -w /b eden-recomp:wivrn bash /s/vr/quest_inner.sh
echo "logs: $WORK/build-xr/quest_wivrn.log (server) and quest_game.log (game)"
