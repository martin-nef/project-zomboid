# Project Zomboid server

Dedicated Project Zomboid (Build 42) server with the [pz3d](https://steamcommunity.com/sharedfiles/filedetails/?id=3807334881)
mod, on Kubernetes in namespace `project-zomboid`. Flux reconciles `deploy/`.
Change things through git, not `kubectl edit`.

- `deploy/config.env`: server name, Steam branch, JVM heap, trusted ZombieBuddy authors, update check timing.
- `deploy/server.ini`: keys enforced in the server's ini on every start (ports, mods, Workshop items).
- `deploy/secrets.yaml`: join/admin/RCON passwords, SOPS-encrypted (`sops deploy/secrets.yaml`, key in the gitignored `age.agekey`).

Editing any of these rolls the pod (hashed ConfigMap names).

## How it runs

StatefulSet `project-zomboid` on shitbox, everything as uid 1000 with no privilege escalation:

- `tools` init container: fetches `jq`, `rcon` and the ZombieBuddy agent jar into the PVC, pinned by SHA-256.
- `server`: `scripts/start.sh` runs `steamcmd app_update 380870`, seeds ZombieBuddy (pz3d's Java loader) and its
  trusted-author list, applies `server.ini`, then starts the server with `-javaagent:ZombieBuddy.jar`.
- `updater` sidecar: `scripts/updater.sh` checks every 10 min for a newer server build on the branch, or a
  Workshop item updated since the server started. It warns players over RCON, saves, and quits. The container restart
  then updates the game, and the server re-downloads Workshop items itself on boot.

Health: liveness asks RCON for `players`. RCON commands run on the server's main loop, so a hung server stops
answering even though the process is alive. Five missed minutes restarts the container. preStop saves and quits
over RCON.

Ports: UDP 16261 (game) and 16262 (direct) through Traefik entrypoints `zomboid-1`/`zomboid-2` on the gateway
(cluster-infra). RCON (27015) is not exposed.

## Versions

Players' clients follow the `public` branch, and PZ refuses a client whose version differs from the server's, so
the server follows `public` too. If a game update breaks pz3d, set `STEAM_BRANCH` to the matching beta (e.g. `42.19`)
and have everyone pick the same beta in Steam.

## Java mods

ZombieBuddy prompts before loading a new or changed Java mod JAR. The server's stdin is closed, so any prompt is
answered "no". Signed JARs from authors in `ZB_TRUSTED_AUTHORS` (kolpaque for pz3d, Zed for ZombieBuddy) load without
a prompt, so pz3d's frequent updates need no manual approval. Adding another Java mod means adding its author there.

## Joining

- Connect to the same public address as the Valheim/RuneScape servers, port 16261. The join password is
  `SERVER_PASSWORD` in `sops -d deploy/secrets.yaml`.
- Players need ZombieBuddy installed as a Java agent on their own machine, not just subscribed. On Windows that's the
  [installer](https://github.com/zed-0xff/ZombieBuddy/releases); on Linux, copy `ZombieBuddy.jar` into the game folder and
  use the launch option `-javaagent:ZombieBuddy.jar --`. See https://pz3d.dev/install/.
- The server lists ZombieBuddy and pz3d as Workshop items, so joining subscribes players to the same versions the server
  runs. Their game must be on the same branch as `STEAM_BRANCH` (normally the default, `public`).

## Console

    kubectl -n project-zomboid exec project-zomboid-0 -c server -- sh -c '/data/tools/rcon -a 127.0.0.1:27015 -p "$RCON_PASSWORD" players'
