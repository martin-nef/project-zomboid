# Joining Stray Dogs (Project Zomboid)

**Server:** `zomboid.nefcloud.top:16261`
**Password:** ask the host

It's a modded Build 42 server running **Project Viewpoint** (first and third person 3D). Viewpoint needs **ZombieBuddy**, a Java mod loader you install once.

## 1. Game version
Stay on the default branch, currently **42.21**: Steam → Project Zomboid → Properties → Betas → **None**.

## 2. Install ZombieBuddy
Subscribe to it first: <https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853>

**Windows:** get `ZombieBuddyInstaller.exe` from <https://github.com/zed-0xff/ZombieBuddy/releases/tag/windows_installer>, run it, pick **Install or update ZombieBuddy**, then **Both**, and confirm.

**Linux / macOS:**
1. Copy `ZombieBuddy.jar` from `steamapps/workshop/content/108600/3619862853/mods/ZombieBuddy/libs/` into the game folder (`steamapps/common/ProjectZomboid/projectzomboid/` on Linux, `Project Zomboid.app/Contents/Java/` on macOS).
2. Set the Steam launch options to `-javaagent:ZombieBuddy.jar --` (keep the `--`).

Start the game. If it worked, "ZombieBuddy vX.Y.Z loaded" shows in the top left.

## 3. Pre-download the mods (optional)
Subscribe to the collection so you don't sit through the downloads when you join: <https://steamcommunity.com/sharedfiles/filedetails/?id=3820722411>

## 4. Join
Multiplayer → Join → IP `zomboid.nefcloud.top`, port `16261`, plus the server password. Pick a username and password: your account is created on your first join, so remember them.

ZombieBuddy asks whether to load **Viewpoint.jar**. Click **Yes** and choose to remember it. It asks again after each Viewpoint update.

## Viewpoint controls
**O** first person · **Shift+O** first ↔ third person · **Delete** settings · **Middle mouse** toggle cursor
