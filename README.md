# Project Zomboid server

Dedicated Project Zomboid (Build 42) server with [Project Viewpoint](https://steamcommunity.com/sharedfiles/filedetails/?id=3809306528)
and the [PZVP Dogs Pack](https://steamcommunity.com/sharedfiles/filedetails/?id=3825483274) mod collection, on Kubernetes in
namespace `project-zomboid`. Flux reconciles `deploy/`.
Change things through git, not `kubectl edit`.

- `deploy/config.env`: server name, Steam branch, JVM heap, trusted ZombieBuddy authors and approved Java mod items,
  update check timing.
- `deploy/server.ini`: keys enforced in the server's ini on every start (ports, mods, Workshop items, maps). The mod
  lines are generated, see [Mods](#mods).
- `deploy/sandbox.ini`: sandbox options set in `<server>_SandboxVars.lua` on every start (multi-hit, infection, ...);
  options not listed keep the world's values.
- `deploy/spawnregions.lua`: the towns new characters can spawn in (all of them, plus "Random").
- `deploy/secrets.yaml`: join/admin/RCON passwords, SOPS-encrypted (`sops deploy/secrets.yaml`, key in the gitignored `age.agekey`).

Editing any of these rolls the pod (hashed ConfigMap names).

## How it runs

StatefulSet `project-zomboid` on shitbox, everything as uid 1000 with no privilege escalation:

- `tools` init container: fetches `jq`, `rcon` and the ZombieBuddy agent jar into the PVC, pinned by SHA-256.
- `server`: `scripts/start.sh` runs `steamcmd app_update 380870` (plus the Workshop items in `ZB_APPROVED_ITEMS`), seeds
  ZombieBuddy (Viewpoint's Java loader) with its trusted-author list and Java mod approvals, applies `server.ini`, then
  starts the server with `-javaagent:ZombieBuddy.jar`. The server downloads the other Workshop items itself (about
  3.6 GB on a fresh volume).
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
the server follows `public` too. Viewpoint only accepts the game version it was built for (currently 42.21), so a game
update breaks it until Viewpoint updates too. Until then, set `STEAM_BRANCH` to the matching beta (e.g. `42.21`) and have
everyone pick the same beta in Steam.

## Mods

`Mods=`, `WorkshopItems=` and `Map=` in `deploy/server.ini` are generated from the Workshop collection named in
`tools/mods.conf`:

    tools/collection.py                # downloads the collection (podman + steamcmd, ~10 min), rewrites server.ini
    tools/collection.py --no-download  # after only editing mods.conf

It enables every mod in every item, minus the `exclude` lines in `mods.conf` (alternative variants of a mod that can't
be combined), orders them by their `require`/`loadModAfter`/`loadModBefore`, and adds mod maps ahead of
`Muldraugh, KY`. It prints `CHECK:` lines for requirements no enabled mod provides and for server-side Java mods that
aren't approved (below). To switch collections, change `collection` in `mods.conf`, rerun, and review the diff and
the excluded variants of new items.

Client-only mods (UI, shaders, 3D models) stay in the list: a PZ client only runs the mods the server lists, so
leaving them out would disable them for everyone. On the server they only cost disk space.

Every Workshop update restarts the server (see the updater above), and many of the Viewpoint add-ons are WIP and
update often. Project RV Interior's map (`map_distanciado`, its interior cells) was added to a world created without
it; its author has a guide for adding it mid-save if interiors misbehave.

## Java mods

ZombieBuddy prompts before loading a new or changed Java mod JAR. The server's stdin is closed, so any prompt is
answered "no". Two ways past that:

- Signed JARs from authors in `ZB_TRUSTED_AUTHORS` (Zed for ZombieBuddy) load without a prompt.
- For the unsigned server-side JARs of the items in `ZB_APPROVED_ITEMS` (Advanced Movement's server part, True
  Ballistics, True Weathers Gameplay, Rolling Hills Physics), start.sh downloads the items before the server starts and
  writes approvals for their current SHA-256 hashes into `/data/zombie_buddy/mod_approvals.json`. ZombieBuddy matches
  approvals by hash alone, so updates to those items keep loading. This trusts those items' authors with code on the
  server.

JARs under `media/java/client/` (Viewpoint itself and most of its add-ons) are client-only. ZombieBuddy 2.3.4 still
prompts for them on the server, the prompt is denied, and the server loads just their Lua side, which is what we want.
Approving them would load rendering code into the headless server.

ZombieBuddy 2.3.4 decides client vs server with Lua's `isServer()`, which is still false when it loads mods on a
dedicated server. That's why it prompts for client JARs, and it also skips JARs under `media/java/server/` as
"server-only". So `ViewpointAdvancedMovementServer` (optional: lets climbs and car riding past the server's noclip
checks) doesn't load yet, though its item stays approved for when ZombieBuddy fixes this. JARs directly under
`media/java/` load on both sides and work.

## Joining

[JOINING.md](JOINING.md) is the player-facing guide, written to paste into Discord.

- Connect to the same public address as the Valheim/RuneScape servers, port 16261. The join password is
  `SERVER_PASSWORD` in `sops -d deploy/secrets.yaml`.
- Players need ZombieBuddy installed as a Java agent on their own machine, not just subscribed. On Windows that's the
  [installer](https://github.com/zed-0xff/ZombieBuddy/releases); on Linux, copy `ZombieBuddy.jar` into the game folder and
  use the launch option `-javaagent:ZombieBuddy.jar --`. See the [ZombieBuddy README](https://github.com/zed-0xff/ZombieBuddy).
- The Viewpoint JARs are unsigned, so each player's ZombieBuddy asks them to approve about 30 of them the first time,
  and again for each one that updates.
- Joining makes players download the server's Workshop items (about 3.6 GB), at the versions the server runs.
  Subscribing to the collection beforehand saves the wait. Their game must be on the same branch as `STEAM_BRANCH`
  (normally the default, `public`).

## Console

    kubectl -n project-zomboid exec project-zomboid-0 -c server -- sh -c '/data/tools/rcon -a 127.0.0.1:27015 -p "$RCON_PASSWORD" players'
