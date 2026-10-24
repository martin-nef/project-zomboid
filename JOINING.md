# Joining Stray Dogs (Project Zomboid)

**Server:** `zomboid.nefcloud.top:16261`
**Password:** ask the host

It's a modded Build 42 server running **Project Viewpoint** (first and third person 3D) and the **PZVP Dogs Pack** collection: about 200 mods, mostly Viewpoint add-ons, KI5 vehicles and UI/QoL. Viewpoint and its add-ons need **ZombieBuddy**, a Java mod loader you install once.

## 1. Game version
Stay on the default branch, currently **42.21**: Steam → Project Zomboid → Properties → Betas → **None**.

## 2. Install ZombieBuddy
Subscribe to it first: <https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853>

**Windows:** get `ZombieBuddyInstaller.exe` from <https://github.com/zed-0xff/ZombieBuddy/releases/tag/windows_installer>, run it, pick **Install or update ZombieBuddy**, then **Both**, and confirm.

**Linux / macOS:**
1. Copy `ZombieBuddy.jar` from `steamapps/workshop/content/108600/3619862853/mods/ZombieBuddy/libs/` into the game folder (`steamapps/common/ProjectZomboid/projectzomboid/` on Linux, `Project Zomboid.app/Contents/Java/` on macOS).
2. Set the Steam launch options to `-javaagent:ZombieBuddy.jar --` (keep the `--`).

Start the game. If it worked, "ZombieBuddy vX.Y.Z loaded" shows in the top left.

## 3. Give the game more memory
The game's default 3 GB of memory isn't enough for this many mods. Open `SteamLibrary\steamapps\common\ProjectZomboid\ProjectZomboid64.json` in a text editor and change `-Xmx3072m` to `-Xmx8g` (this needs a PC with at least 16 GB of RAM; on Linux, the same file in the game folder). Change only that, and keep any ZombieBuddy line the installer added. A game update or Steam's "Verify integrity of game files" resets it, so check it again after one.

## 4. Pre-download the mods (recommended)
The mods are about **3.6 GB**. Subscribe to the collection and let Steam finish downloading before you join, or the join screen downloads it all first: <https://steamcommunity.com/sharedfiles/filedetails/?id=3825483274>

You don't need to enable the mods yourself: joining loads exactly the server's mod list.

## 5. Join
Multiplayer → Join → IP `zomboid.nefcloud.top`, port `16261`, plus the server password. Pick a username and password: your account is created on your first join, so remember them.

ZombieBuddy asks whether to load the mods' Java files (around 30 of them: Viewpoint and its add-ons). Approve all of them and choose to remember the decision, or those features silently don't work. It asks again for each mod that updates. Holding **Shift** while the game starts reopens the approval window if you clicked No by mistake.

The first load with this many mods takes a few minutes, and Rolling Hills takes a minute or so to generate terrain.

## Viewpoint controls
**O** first person · **Shift+O** first ↔ third person · **Delete** settings · **Middle mouse** toggle cursor

Advanced Movement moves some vanilla keys: **Q / E** lean (shout is now **N**, interact **F**, flashlight **Z**), **Space** jump/vault/climb (shove is now **Mouse 5**), double-tap **Shift** to sprint, hold **Crouch** to go prone. Rebind them under Options → Keybinds.

For hills that match the server's vehicle physics, select the **Rolling Hills** terrain in Viewpoint's settings (Delete).
