#!/bin/bash
# Sidecar: restarts the server when Steam has a newer build of the dedicated
# server on our branch, or a Workshop item in WorkshopItems was updated after
# the server started. Players are warned over RCON first; then the world is
# saved and the server quits, and the server container's restart updates both
# (steamcmd in start.sh, Workshop items by the server itself on boot).
set -uo pipefail

ini="/data/Zomboid/Server/$SERVER_NAME.ini"
manifest=/data/server/steamapps/appmanifest_380870.acf
tools=/data/tools

log() { echo "[updater] $(date -u +%FT%TZ) $*"; }

trap 'exit 0' TERM INT
# Sleeps in the background so SIGTERM ends the sidecar immediately.
nap() {
  sleep "$1" &
  wait $!
}

rcon() {
  timeout 30 "$tools/rcon" -a 127.0.0.1:27015 -p "$RCON_PASSWORD" "$@"
}

installed_build() {
  awk -F'"' '$2 == "buildid" { print $4; exit }' "$manifest" 2>/dev/null
}

# This container's own steamcmd (the server's lives on the PVC). appinfo.vdf
# is dropped first because steamcmd otherwise happily prints a stale cache.
latest_build() {
  rm -f /home/steam/Steam/appcache/appinfo.vdf
  timeout 300 /home/steam/steamcmd/steamcmd.sh \
    +login anonymous +app_info_update 1 +app_info_print 380870 +quit 2>/dev/null |
    awk -v b="\"${STEAM_BRANCH:-public}\"" '
      $1 == "\"branches\"" { inb = 1 }
      inb && $1 == b { inbranch = 1 }
      inbranch && $1 == "\"buildid\"" { gsub(/"/, "", $2); print $2; exit }
    '
}

# Prints "<id> <title>" for each Workshop item updated after epoch $1.
updated_mods() {
  local ids i=0 args=()
  ids=$(awk -F= '$1 == "WorkshopItems" { print $2 }' "$ini" | tr ';' ' ')
  for id in $ids; do
    args+=(-d "publishedfileids[$i]=$id")
    i=$((i + 1))
  done
  [ "$i" -gt 0 ] || return 0
  curl -fsS --max-time 30 -d "itemcount=$i" "${args[@]}" \
    https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/ |
    "$tools/jq" -r --argjson t "$1" \
      '.response.publishedfiledetails[] | select((.time_updated // 0) > $t) | "\(.publishedfileid) \(.title)"'
}

online_players() {
  rcon players 2>/dev/null | sed -n 's/.*Players connected (\([0-9]*\)).*/\1/p' | head -n 1
}

log "checking for updates every ${UPDATE_CHECK_INTERVAL}s"
last=''
last_at=0
while :; do
  nap "$UPDATE_CHECK_INTERVAL"

  # Nothing to do while the server is down or still starting.
  started=$(cat /data/.server-started 2>/dev/null) || continue
  rcon players >/dev/null 2>&1 || continue

  reasons=()
  current=$(installed_build)
  latest=$(latest_build)
  if [ -n "$current" ] && [ -n "$latest" ] && [ "$current" != "$latest" ]; then
    reasons+=("game build $current -> $latest")
  fi
  if mods=$(updated_mods "$started") && [ -n "$mods" ]; then
    reasons+=("workshop: $(echo "$mods" | paste -sd ',' -)")
  fi
  [ "${#reasons[@]}" -gt 0 ] || continue

  # A restart that didn't pick the update up (Steam down, a build that isn't
  # downloadable yet) would otherwise repeat every interval; retry every 6h.
  if [ "${reasons[*]}" = "$last" ] && [ $(($(date +%s) - last_at)) -lt 21600 ]; then
    log "still pending after a restart, retrying later: ${reasons[*]}"
    continue
  fi
  last="${reasons[*]}"
  last_at=$(date +%s)

  log "update available: ${reasons[*]}"
  players=$(online_players)
  if [ "${players:-0}" -gt 0 ]; then
    for ((left = UPDATE_WARNING_MINUTES; left > 0; left--)); do
      rcon "servermsg \"Server restarts in $left minute(s) to update\"" >/dev/null
      nap 60
    done
  fi

  log "saving and quitting"
  rcon save >/dev/null
  nap 10
  rcon quit >/dev/null

  # Wait for the restarted server before checking again.
  while [ "$(cat /data/.server-started 2>/dev/null)" = "$started" ]; do
    nap 10
  done
  log "server restarted"
done
