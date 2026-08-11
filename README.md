# CS Stick Arena

A top-down, Hotline-Miami-style stick-figure shooter made with **Godot 4** and
CS-flavored weapons. No art assets — everything (stick figures, arena, blood,
HUD) is drawn procedurally in GDScript.

## Modes

- **PLAY · PVE ARENA** — endless wave survival against bot stickmen. Enemies get
  more numerous, tougher, and better armed each wave. +25 HP and a score bonus
  between waves. Dead enemies sometimes drop their gun or a medkit.
- **MULTIPLAYER · PVP** — free-for-all deathmatch over LAN or direct IP
  (port `7777`, up to 8 players). One player clicks **HOST GAME**, everyone else
  enters the host's IP and clicks **JOIN GAME**. First to 15 frags wins, then the
  round resets automatically.

## Running it

1. Install [Godot 4.3+](https://godotengine.org/download) (standard build, no .NET needed).
2. Open Godot's Project Manager → **Import** → select this folder's `project.godot`.
3. Press **F5** (Run Project).

To test multiplayer on one machine: in the editor use **Debug → Customize Run
Instances… → 2 instances**, then run; host in one window and join `127.0.0.1`
in the other. Over LAN, allow the game through Windows Firewall when prompted
(the multiplayer screen shows your LAN IP).

## Controls

| Input | Action |
|---|---|
| WASD / arrows | Move |
| Mouse | Aim |
| Left mouse button | Shoot (hold for automatics) |
| R | Reload |
| Walk over a gun | Pick it up (swaps your weapon, full ammo) |
| Esc | Quit to menu |

## Arsenal

Glock-18, USP-S, MP5-SD, M4A4, AK-47, Nova (shotgun), AWP (one-shot sniper).
You spawn with the Glock; better guns sit at fixed spots around the arena and
respawn ~14 s after being taken.

## Project layout

```
scenes/main_menu.tscn   menu scene (UI built in code)
scenes/game.tscn        arena scene (world built in code)
scripts/net.gd          autoload: session mode + ENet host/join plumbing
scripts/game.gd         arena, PvE wave director, PvP deathmatch logic, gore
scripts/player.gd       movement, shooting, reload, health, network sync
scripts/enemy.gd        bot AI (line of sight, strafing, handicapped aim)
scripts/bullet.gd       raycast-stepped projectiles (server applies damage)
scripts/pickup.gd       walk-over weapon/medkit pickups
scripts/weapons.gd      weapon stat table
scripts/stick_render.gd shared top-down stick-figure drawing
scripts/hud.gd          health/ammo/scoreboard HUD + overlays
scripts/main_menu.gd    menu UI
```

## Ideas for later

- Sounds (gunshots, reloads) and music
- Co-op PvE over the same networking layer
- More maps, team modes, bomb-defusal objective
