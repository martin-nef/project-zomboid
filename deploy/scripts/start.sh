#!/bin/bash
# Server container entrypoint: installs or updates the game, applies the
# managed config, then runs the server in the foreground. When the server
# quits (the updater sidecar asks it to when an update is out) the container
# exits and the kubelet restarts it, which lands back here and updates.
set -euo pipefail

install=/data/server
cachedir=/data/Zomboid
zb=/data/zombie_buddy
tools=/data/tools
ini="$cachedir/Server/$SERVER_NAME.ini"

log() { echo "[start] $*"; }

# Runs a command in the background so a SIGTERM (pod deletion while steamcmd
# is busy) is handled at once instead of after the download finishes.
child=
trap '[ -n "$child" ] && kill "$child" 2>/dev/null; exit 143' TERM INT
run() {
  "$@" &
  child=$!
  wait "$child"
}

# --- Game ---------------------------------------------------------------------

args=(+force_install_dir "$install" +login anonymous +app_update 380870)
# Passing "-beta public" makes steamcmd look for a beta of that name and do nothing.
if [ "${STEAM_BRANCH:-public}" != public ]; then
  args+=(-beta "$STEAM_BRANCH")
fi
if [ ! -f "$install/start-server.sh" ] || [ "${STEAM_VALIDATE:-0}" = 1 ]; then
  args+=(validate)
fi
args+=(+quit)

# steamcmd tends to fail its first run on a fresh home ("Missing configuration").
for attempt in 1 2 3; do
  log "steamcmd app_update 380870 (branch ${STEAM_BRANCH:-public}, attempt $attempt)"
  if run /home/steam/steamcmd/steamcmd.sh "${args[@]}"; then
    break
  fi
  if [ "$attempt" = 3 ]; then
    if [ -f "$install/start-server.sh" ]; then
      log "steamcmd failed, starting the installed build"
      break
    fi
    log "steamcmd failed and nothing is installed"
    exit 1
  fi
  sleep 10
done

# --- ZombieBuddy (Java agent that pz3d needs) -------------------------------------

if [ ! -f "$zb/ZombieBuddy.jar" ]; then
  log "seeding ZombieBuddy.jar"
  cp "$tools/ZombieBuddy.jar" "$zb/ZombieBuddy.jar"
fi

# The author list is authoritative: trust follows ZB_TRUSTED_AUTHORS, and the
# rest of the file (e.g. preload_mods, which ZombieBuddy writes) is kept.
cfg="$zb/config.json"
[ -s "$cfg" ] || echo '{}' >"$cfg"
"$tools/jq" --argjson ids "[${ZB_TRUSTED_AUTHORS}]" '.trusted_authors = $ids' "$cfg" >"$cfg.tmp"
mv "$cfg.tmp" "$cfg"

# --- Server config ---------------------------------------------------------------

mkdir -p "$(dirname "$ini")"
touch "$ini"

# set_ini <key> <value>. Values go through the environment so awk doesn't
# interpret backslashes (Mods=\pz3d) or anything in the passwords.
set_ini() {
  K="$1" V="$2" awk '
    BEGIN { k = ENVIRON["K"]; v = ENVIRON["V"] }
    index($0, k "=") == 1 { print k "=" v; found = 1; next }
    { print }
    END { if (!found) print k "=" v }
  ' "$ini" >"$ini.tmp"
  mv "$ini.tmp" "$ini"
}

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in '' | '#'*) continue ;; esac
  set_ini "${line%%=*}" "${line#*=}"
done </config/server.ini
set_ini Password "$SERVER_PASSWORD"
set_ini RCONPassword "$RCON_PASSWORD"

# --- Run ---------------------------------------------------------------------

# The updater compares Workshop update times against this.
date +%s >/data/.server-started

cd "$install"
log "starting $SERVER_NAME"
# Arguments before "--" go to the JVM. stdin stays closed, so a ZombieBuddy
# approval prompt for an untrusted Java mod reads EOF and denies it.
exec ./start-server.sh \
  "-Xmx$JAVA_XMX" \
  "-javaagent:$zb/ZombieBuddy.jar=frontend=console,config_dir=$zb" \
  -- \
  -servername "$SERVER_NAME" \
  -cachedir="$cachedir" \
  -adminusername admin \
  -adminpassword "$ADMIN_PASSWORD" \
  </dev/null
