---
inclusion: always
---

# Book Bash — Product Overview

A stylized 3D mobile party-battle game: players throw books at each other across six themed
arenas (Sky Library, Classroom Chaos, Ancient Ruins, Tech Tower, Candy Island, Volcano Core),
try to knock opponents out, and progress via cosmetic unlocks (skins, hats, trails, emotes)
funded by a soft/premium currency + Battle Pass economy. Full design reference:
`docs/book-bash-3d-development-plan.md`.

## Build order (see plan §12 for full milestone table)

0. Foundation — repo scaffolded, project boots to an empty 3D scene, tools verified.
1. Core loop grey-box — mobile twin-stick controls, book-throw ballistics, bot opponent,
   round/knockout state machine, minimal HUD. Ugly but playable, no final art yet.
2. First real assets — procedural book model + Sky Library arena via Blender scripts,
   cel-shading applied.
3. Character in — rigged base character + Mixamo animations wired into AnimationTree.
4. Full UI loop — Lobby/Customize/Store/Battle Pass/Map Select, local save + inventory.
5. All six arenas generated + hazard-scripted.
6. LAN multiplayer (ENetMultiplayerPeer, high-level API).
7. Internet multiplayer via relay.
8. Audio & polish.
9. Store readiness (IAP hooks, Play Console assets, signed release build).

Bridged (non-code) steps that need a one-time human action: selecting/downloading a base
character mesh, one Mixamo upload/download per base body, sourcing audio files externally,
and any Play Console / Apple Developer account administration. Everything else is Kiro-coded.
