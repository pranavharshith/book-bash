# BOOK BASH — Full 3D Mobile Game Master Build Plan
### AI-Executed Pipeline for Kiro (Pro, $20/mo) + Godot 4 + Blender

---

## 0. How To Use This Document

This is written to be **fed directly into Kiro** as the source material for a Kiro **Spec**. Kiro is spec-driven — it works best when you give it a persistent "steering" document plus a sequence of formal specs it can execute, checkpoint, and resume. Everything below is organized so you can:

1. Drop this whole file into your repo as `docs/GAME_PLAN.md`.
2. Tell Kiro: *"Read docs/GAME_PLAN.md. Create a steering file summarizing the tech stack and constraints, then generate a spec for Phase 0."*
3. Approve each spec, let Kiro execute the tasks, and move to the next phase.

You will not need to write code, model anything in Blender, or touch Godot's editor by hand. Your job is limited to: clicking "install" on a few programs, keeping Godot open so Kiro can hot-reload/verify, and occasionally re-authorizing Kiro when it needs Android SDK licenses accepted or a device plugged in for testing.

One honest note before we start, so expectations are calibrated correctly: a **live multiplayer 3D mobile game with full monetization** is one of the largest scopes in solo game dev. Kiro Pro gives you ~1,000 credits/month, and 3D asset-generation loops (Blender script → render check → fix → re-render) burn credits faster than pure UI/logic code. The plan below is sequenced so the **single-player-feeling core loop with local "bot" opponents** is playable first, and true networked multiplayer is a later phase you can pace against your credit budget. Nothing about the game concept is being changed or scaled down — this is purely about the *order* things get built in, so you always have something running.

---

## 1. The Tech Stack, and Why

| Layer | Tool | Why it fits an AI-agent pipeline |
|---|---|---|
| Game engine | **Godot Engine 4.7** (current stable; 4.6.x also fine if 4.7 has a regression you hit) | Scenes (`.tscn`), resources (`.tres`), and scripts (`.gd`) are plain UTF-8 text. Kiro can read, diff, write, and `grep` through them exactly like source code. No proprietary binary project format to fight with. |
| 3D asset generation | **Blender 5.1 / 5.2 LTS**, run **headless** via `bpy` | Kiro never opens the Blender GUI. It writes Python scripts that use Blender's `bpy` module to construct geometry procedurally and export `.glb`, then runs them from the terminal. This is 100% code — no manual clicking, dragging, or sculpting. |
| Coding agent | **Kiro Pro ($20/mo, ~1,000 credits/mo)** | Kiro is AWS's spec-driven agentic IDE (built on the same open-source base as VS Code). It plans work as formal **specs**, executes multi-step **tasks** against your repo, and can run terminal commands — including `blender --background --python …` and the Godot CLI/headless exporter. Routing sends heavy reasoning (spec authoring, architecture, tricky bugs) to a stronger model and mechanical work (boilerplate, fixture generation) to a cheaper/faster one, which is what keeps your credit spend sane. |
| Android build/test | **Android Studio + command-line SDK/NDK + OpenJDK 17** | Required by Godot's Android export templates. Also gives you a device emulator so Kiro-built APKs can be installed and smoke-tested without a physical phone. |
| Base character mesh | **Kenney.nl / Synty POLYGON packs / Sketchfab (CC0 or commercial license)**, OR an AI mesh generator (Meshy, Tripo) | The one thing current AI code-agents cannot do well: sculpt an appealing stylized face/body from nothing. Bridged in, not hand-modeled by you. |
| Character animation | **Adobe Mixamo (free)** | Auto-rigs the base mesh and provides run/idle/throw/hit/knockback animation clips as `.glb`/`.fbx`, which Kiro imports and wires into Godot's `AnimationTree`. |
| Version control | **Git + GitHub** (free) | Kiro commits after every completed spec task, so you get a full history and can roll back if an AI-generated change breaks something. |
| Audio | **Freesound.org (CC0) for SFX, or an AI music/SFX generator (e.g. ElevenLabs Sound Effects, Suno for music)** | Not covered in the original brief but necessary for a finished game — see §12. Kiro can script the *integration* (audio bus setup, `AudioStreamPlayer3D` nodes, mixing) but cannot compose original audio from a text prompt the way it can write GDScript. |

---

## 2. Environment Setup (One-Time, ~45–90 minutes)

Do these once, in order. Kiro can run terminal commands for you for the CLI-only steps, but the GUI installers below need a human click (this is the only "hands-on" part of the whole project).

### 2.1 Git
- Windows: install **Git for Windows**. macOS: `brew install git` or Xcode Command Line Tools. Linux: `sudo apt install git`.
- Configure once: `git config --global user.name "..."` / `git config --global user.email "..."`.
- Create a private GitHub repo called `book-bash` and clone it locally. This is the folder Kiro will live in.

### 2.2 Kiro
- Download Kiro for your OS from the official AWS Kiro site, sign in, and confirm you're on the **Pro** tier (1,000 credits/month at $20).
- Open the `book-bash` folder as your Kiro workspace.
- Inside Kiro, create a **steering file** (Kiro's persistent project-memory mechanism) named something like `product.md` / `tech.md` that pins: "This project targets Godot 4.7, GDScript only (no C#), Blender 5.x via headless `bpy` for all 3D assets, Android as the primary export target, and must never require manual Blender/Godot GUI work from the user." This single step is what makes every future spec inherit the constraints automatically instead of you re-explaining them each time.

### 2.3 Godot Engine 4.7
- Download the **Standard** (non-.NET) build for your OS from godotengine.org. Do **not** grab the .NET/Mono build — GDScript-only keeps the whole codebase text-diffable and avoids a C#/.NET toolchain Kiro would otherwise have to manage.
- Also download the matching **Android export templates** from the same release page (Godot prompts for this the first time you try an Android export).
- Launch Godot once manually just to confirm it opens — after that, Kiro will create and edit the project files directly and you'll mostly just keep the editor open in the background so it can validate scenes.

### 2.4 Blender 5.1 or 5.2 LTS
- Install the standard build for your OS from blender.org.
- Confirm `blender --version` works from a terminal — Kiro needs the executable on PATH so it can invoke `blender --background --python tools/generate_books.py`.
- No add-ons need to be installed manually; if a script needs a specific Blender Python package, Kiro will `pip install --target` it into Blender's bundled Python or use `bpy`-native calls only.

### 2.5 Android Studio, SDK, NDK, OpenJDK 17
- Install Android Studio (this bundles the SDK Manager).
- In SDK Manager, install: **Android SDK Platform 34 or 35**, **Android SDK Build-Tools**, **Android SDK Command-line Tools**, **NDK (side by side)**, **CMake**.
- Install **OpenJDK 17** (Android Studio can install this for you, or use Temurin 17).
- Accept the SDK licenses (`sdkmanager --licenses` — Kiro can run this for you from the terminal).
- Create/start one Android Virtual Device (e.g. Pixel 8, API 34) in the Device Manager so there's an emulator target for Kiro to deploy test builds to.
- In Godot: **Editor → Editor Settings → Export → Android**, point it at your Android SDK path. Ask Kiro to also write these paths into `export_presets.cfg` inside the repo so the whole export config is versioned, not stuck in your local machine's settings only.

### 2.6 Mixamo account
- Create a free Adobe account and log into mixamo.com. This is used a handful of times per character (upload mesh → download animations), not automated per-build, so it's fine that it's the one manual web step in the pipeline.

**Setup is done.** Everything past this point is Kiro writing files, running scripts, and committing to git.

---

## 3. Repository Architecture

```text
book-bash/
├── docs/
│   ├── GAME_PLAN.md              # this document
│   ├── design/                   # per-map design briefs (see §11)
│   └── specs/                    # Kiro spec history, auto-generated
├── project.godot                 # Godot project root
├── assets/
│   ├── models/
│   │   ├── props/                # generated .glb: books, tables, shelves, podiums
│   │   ├── arenas/                # per-map architecture kits (§11)
│   │   └── characters/            # Mixamo-rigged base humanoid meshes + variants
│   ├── shaders/                   # .gdshader cel-shading, VFX
│   ├── textures/                  # book skins, UI atlases, hat textures
│   ├── audio/
│   │   ├── sfx/
│   │   └── music/
│   └── ui/                        # icons, portraits, HUD art
├── scripts/
│   ├── player/
│   │   ├── player_controller.gd
│   │   ├── player_input_mobile.gd
│   │   └── player_animation_state.gd
│   ├── combat/
│   │   ├── book_projectile.gd
│   │   ├── book_spawner.gd
│   │   ├── power_up.gd
│   │   └── hit_reaction.gd
│   ├── game/
│   │   ├── game_manager.gd
│   │   ├── round_manager.gd
│   │   ├── match_state.gd
│   │   └── spawn_director.gd
│   ├── net/
│   │   ├── network_manager.gd
│   │   ├── matchmaking_client.gd
│   │   └── replication.gd
│   ├── economy/
│   │   ├── currency_manager.gd
│   │   ├── inventory.gd
│   │   ├── unlock_system.gd
│   │   └── battle_pass.gd
│   ├── ui/
│   │   ├── lobby_screen.gd
│   │   ├── customize_screen.gd
│   │   ├── store_screen.gd
│   │   ├── map_select_screen.gd
│   │   ├── hud.gd
│   │   └── touch_controls.gd
│   └── util/
│       └── save_system.gd
├── scenes/
│   ├── main.tscn
│   ├── boot.tscn
│   ├── ui/
│   │   ├── Lobby.tscn
│   │   ├── Customize.tscn
│   │   ├── BattlePass.tscn
│   │   ├── Store.tscn
│   │   └── MapSelect.tscn
│   ├── arenas/
│   │   ├── SkyLibrary.tscn
│   │   ├── ClassroomChaos.tscn
│   │   ├── AncientRuins.tscn
│   │   ├── TechTower.tscn
│   │   ├── CandyIsland.tscn
│   │   └── VolcanoCore.tscn
│   ├── characters/
│   │   └── PlayerCharacter.tscn
│   └── props/
│       ├── BookPickup.tscn
│       └── PowerUpPickup.tscn
├── tools/
│   ├── generate_books.py          # Blender bpy: procedural book meshes
│   ├── generate_props.py          # Blender bpy: shelves, tables, podiums
│   ├── generate_arena_kit.py      # Blender bpy: per-theme modular kit pieces
│   └── import_character.py        # Blender bpy: cleans/re-exports Mixamo FBX → .glb
├── addons/                        # any Godot plugins Kiro decides are worth adding (e.g. GUT for testing)
├── export_presets.cfg
└── README.md
```

Kiro should be instructed to **never** hand-place binary asset files outside of `assets/` and to keep every generator script re-runnable and idempotent (running `generate_books.py` twice produces the same output, so assets are always reproducible from code — this is the whole point of the pipeline).

---

## 4. What Kiro Can Build 100% In Code (No Bridging Needed)

This is the bulk of the game. Treat each bullet as its own spec/task group.

**Movement & Physics**
- Mobile twin-stick controller: left virtual joystick for run direction, right-side drag/tap for aim + throw power.
- `CharacterBody3D`-based locomotion with acceleration/friction tuned for a snappy arcade feel (not a realistic walk).
- Throwing ballistics: velocity vector computed from aim direction + a charge-up power meter, gravity-arced trajectory, spin animation on the book mesh in flight, `Area3D`/`RigidBody3D` collision against player hit-boxes.
- Dodge roll with i-frames, knockback impulse on hit, brief hit-stun.

**Procedural 3D Props (via Blender `bpy`, fully scripted)**
- Books: beveled hardcover, page-block extrusion, ribbon bookmark, UV-unwrapped into swappable skin zones (Ancient / Flame / Frosted / etc. — matches the Store screen in your reference image).
- Arena furniture: bookshelves (parametrized by row/column count so every arena's shelving looks unique from the same generator), reading tables, podiums, ladders, floating "ritual carpets," candy-cane pillars for Candy Island, obsidian pillars for Volcano Core, server racks for Tech Tower, etc.

**Shaders & VFX** (Godot Shading Language, `.gdshader`)
- Cel-shaded toon outline + banded lighting for characters and props, matching the stylized reference art.
- Cartoon speed-line trail on thrown books.
- Impact "star burst" and screen-shake on a landed hit.
- Glowing floor rune shader for the ritual-carpet spawn circle seen in the reference image.
- Simple particle systems (`GPUParticles3D`) for dust kick-up on landing, page-flutter on a book breaking apart.

**Game Systems & UI**
- Match/round state machine: lobby → countdown → live round → knockout resolution → post-match rewards.
- Health/stock (knockout) tracking per player, score display, round timer.
- Inventory + equip system for book skins, hats, trails, emotes.
- Touch-responsive Control-node UI: Lobby, Customize, Battle Pass, Store, Map Select screens, and the in-match HUD (portraits + damage numbers + timer + ammo/charge meter), mirroring the exact screen set in your reference mockups.
- Save/load of local player profile, currency balances, and unlocked cosmetics.

**AI Bots (for solo practice / filling matches before real matchmaking exists)**
- Simple state-machine bots (seek nearest book → pick up → track nearest opponent → throw when in range → dodge incoming books probabilistically) so the game is fun and testable before real networking is finished.

---

## 5. Character & Animation Pipeline (The Bridged Part)

This is the **one** part of the pipeline that isn't pure "Kiro writes code and it's done," because a stylized, appealing cartoon-kid face is not something a code agent can safely generate as raw geometry — attempts to hand-code a face mesh from vertex math produce something uncanny, not charming. Here's the bridge, kept as automated as possible:

1. **Source a base mesh.** Pick one:
   - *Free route:* a CC0/permissively-licensed stylized low-poly humanoid from Kenney.nl or a similar asset pack. Zero cost, instantly usable, matches a "cute low-poly kid" look reasonably well.
   - *Closer-to-reference route:* generate a base mesh with an AI 3D tool (Meshy, Tripo) from a reference image/prompt describing "stylized cartoon kid, big head, hoodie, sneakers, low-poly game-ready." You (or Kiro, if the tool has an API) upload the reference and download a `.glb`.
   - Either way, this download happens **once per base body type** (you likely only need 1–3 base bodies — e.g., "kid A," "kid B" — and then reskin/recolor/accessorize them via code for all the different player looks, exactly like the hats/skins system in your reference image implies).
2. **Rig + animate via Mixamo.** Upload the base mesh to mixamo.com, let Mixamo auto-rig it, then download the animation set you need: Idle, Run, Throw (windup + release), Hit Reaction, Knockback/Stumble, Victory emote, Dodge Roll. Mixamo exports as FBX with the skeleton baked in.
3. **Hand off to Kiro from here on.** Drop the downloaded FBX files into a staging folder; Kiro's `tools/import_character.py` (a headless Blender script) cleans the FBX (fixes scale/orientation, strips unused Mixamo bones, re-exports as `.glb`) and Kiro then writes the Godot `AnimationTree`/`AnimationPlayer` state machine (`player_animation_state.gd`) that blends between these clips based on player input — run speed blending, throw-windup triggering on charge, hit-reaction interrupting movement, etc. All of *that* logic is 100% Kiro-coded.
4. **Hats, skins, accessories** (per your Customize/Store screens) are built as small separate meshes that Kiro's Blender scripts generate procedurally (witch hat, panda hood, cat ears, sunglasses, etc.) and attach to a bone socket on the rig at runtime — this part is fully proceduralizable in code, since simple prop shapes (unlike a character's face) are well within what `bpy` scripting can produce convincingly.

---

## 6. Multiplayer Networking Plan

Your reference mockups show 4–6 player free-for-all battles. Real-time multiplayer is a distinct engineering track from the core game, so it's staged:

**Phase A — Local/LAN multiplayer (build this first).** Godot's built-in **High-Level Multiplayer API** (`ENetMultiplayerPeer`) lets one device host and others join over local Wi-Fi or direct IP. This is enough to fully validate the throwing/hit/knockback netcode, UI flows, and match state machine with real human players (e.g., you and friends on the same network) with **zero backend cost**.

**Phase B — Internet play via a relay.** Once the game feels good on LAN, add a lightweight relay so players don't need to port-forward. Two low-cost options Kiro can wire up:
- A small always-on VM (e.g., a $5–6/mo cloud instance) running a bare ENet relay/rendezvous script — cheap, fully within Kiro's ability to write and deploy.
- Or a managed service with a generous free tier built for exactly this (e.g., Nakama's open-source server self-hosted for free, or a similar game-backend-as-a-service). Kiro can scaffold the client integration either way; you'd just need to decide the budget for the relay/server, separate from your Kiro subscription.

**Phase C — Matchmaking & persistence.** Simple queue-based matchmaking (join queue → matched at 4–6 players → spawn into a match) plus server-authoritative currency/inventory (so cosmetic unlocks can't be tampered with client-side) — this is a later-phase spec once A and B are solid.

This staging means you get a genuinely playable, good-feeling multiplayer prototype (Phase A) almost immediately, without the project stalling on backend infrastructure before there's even a fun game to network.

---

## 7. UI/UX System — Screen-by-Screen

Matches the mockups you provided (Lobby, Customize, Battle Pass, Store, Maps, in-match HUD):

- **Lobby:** player's currently-equipped look front and center, currency balances (soft coin + premium gem, top bar), big "PLAY" button, side-nav icons for Customize/Battle Pass/Store/Maps/Friends.
- **Customize:** category tabs (Face/Skin, Book, Hat, Trail, Emote), grid of owned/locked items, tap-to-preview on the 3D character before equipping.
- **Battle Pass:** level/XP bar, tiered reward track (free + premium lanes), "Upgrade" CTA.
- **Store:** tabbed by item type (Skins/Books/Trails/Emotes), each item priced in soft or premium currency, "featured/rotating" section at the top.
- **Map Select:** grid of the six arenas (see §11) with thumbnail art and a name label, tap to queue into that map.
- **In-match HUD:** top strip of player portraits + stock/health pips, round timer center-top, virtual joystick bottom-left, throw-charge + dodge buttons bottom-right, damage/knockout popups.

All of this is standard Godot `Control`-node UI (`CanvasLayer`, `TextureButton`, `ProgressBar`, `GridContainer`, etc.) — entirely scriptable, no art tool required beyond the icon/texture assets Kiro generates or you drop in.

---

## 8. Progression, Economy & Monetization

- **Two currencies:** a soft currency earned from playing (post-match rewards) and a premium currency purchasable via IAP, mirroring the coin/gem pattern in your reference mockups.
- **Unlock system:** `unlock_system.gd` gates cosmetics behind soft-currency price, premium-currency price, or Battle Pass tier — data-driven from a resource file so adding a new skin later is just adding a row, not new code.
- **Battle Pass:** seasonal XP track with free and premium reward lanes; XP awarded per match played/won.
- **IAP hooks:** Kiro can scaffold the Google Play Billing integration points (purchase requests, receipt validation stubs) even before you have a live store listing — you'll need a Google Play Console developer account ($25 one-time) when you're ready to actually publish and test real purchases, which is outside Kiro/Godot's own scope.

---

## 9. The Six Arenas — Design Briefs

Each map gets its own Blender generator variant (built from the same modular shelving/pillar/prop generators in §4, just re-themed) plus unique hazards for gameplay variety:

1. **Sky Library** — floating stone platforms connected by bridges of stacked books high above the clouds; falling off a platform = elimination, adding a positioning-risk layer to throws.
2. **Classroom Chaos** — desks and chairs as cover, a chalkboard that occasionally "erases" and reveals a temporary power-up; low, cramped sightlines that reward close-range dodging.
3. **Ancient Ruins** — crumbling stone library with collapsing bookshelf hazards that periodically topple and deal area damage.
4. **Tech Tower** — glowing server-rack cover and moving conveyor-belt floor sections that push players' aim off if they're not careful.
5. **Candy Island** — bouncy gumdrop platforms that add extra height to jumps/dodges, sticky "syrup" zones that slow movement.
6. **Volcano Core** — lava-glow lighting, periodic rising-lava hazard at the arena edges that shrinks the safe zone late in a round (a light battle-royale-style tension beat).

Each is a self-contained `.tscn` built from the shared prop kit + a themed skybox/lighting rig + 1–2 unique hazard scripts, so adding a *seventh* map later is a small, well-scoped spec rather than a from-scratch effort.

---

## 10. Audio (The Other Bridged Piece)

Kiro can wire up every *system* around audio — 3D positional `AudioStreamPlayer3D` nodes on impacts/footsteps, a music bus with ducking during a match, UI click/tap sounds — but it cannot compose original music or sound effects from nothing the way it writes code. Two practical options, both cheap/free and both fine to hand to Kiro as "download these and integrate them":
- **Freesound.org**, filtered to CC0 (public domain) sounds, for impact thuds, page-flutter, footsteps, UI clicks.
- An AI audio generation tool (text-to-SFX or text-to-music) if you want fully original, license-clean audio rather than curated free sounds — you'd generate the files externally and Kiro imports/integrates them, same as the character mesh bridge in §5.

---

## 11. Build, Export & Testing Pipeline

- Kiro maintains `export_presets.cfg` for Android (and can add an iOS preset later, though iOS builds and App Store submission require a Mac and an Apple Developer account — a hard platform requirement, not an AI limitation).
- Every completed feature milestone: Kiro runs Godot's **headless export** from the terminal (`godot --headless --export-debug "Android" build/book-bash-debug.apk`) and installs it to your running emulator/device (`adb install -r ...`) so you can tap through and confirm it feels right — no manual export dialog needed.
- For automated regression checks, Kiro can add **GUT** (Godot Unit Test), a free Godot testing addon, and write unit tests for pure-logic systems (damage calc, currency math, unlock gating) so future changes don't silently break them.

---

## 12. Milestone Roadmap

| Phase | Goal | Roughly maps to |
|---|---|---|
| **0 — Foundation** | Environment set up, repo scaffolded, project boots to an empty 3D scene on device. | §2–§3 |
| **1 — Core Loop, Grey-box** | Player moves, throws a placeholder cube "book," hits a bot, round timer/knockout works — ugly but fun, no art yet. | §4, bots from §4 |
| **2 — First Real Assets** | Procedural book model + one arena (Sky Library) generated via Blender scripts; cel-shader applied. | §5 (props only), §11 (1 map) |
| **3 — Character In** | Base character rigged, Mixamo animations wired into an `AnimationTree`; hats/skins swap on the model. | §5 full |
| **4 — Full UI Loop** | Lobby/Customize/Store/Battle Pass/Map Select screens live and wired to a real (local) save file and inventory. | §7, §9 |
| **5 — All Six Arenas** | Remaining five maps generated and hazard-scripted. | §11 full |
| **6 — LAN Multiplayer** | Real 2–6 player matches over local Wi-Fi. | §6 Phase A |
| **7 — Internet Multiplayer** | Relay-based online play. | §6 Phase B/C |
| **8 — Audio & Polish** | SFX/music integrated, VFX passes, screen-shake/juice tuning. | §10 |
| **9 — Store Readiness** | IAP hooks finalized, Play Console listing assets, signed release build. | §9, §11 |

Pace Phases 6–9 against your actual monthly credit usage — Phases 0–5 give you a fully playable, good-looking, single-device game, which is the right point to pause and evaluate before committing more budget to the networking/monetization phases.

---

## 13. Exact Kickoff Sequence — What To Literally Tell Kiro, In Order

1. *"Read docs/GAME_PLAN.md in full. Create steering files for tech stack, code style (GDScript only, no C#), and project constraints."*
2. *"Create a spec for Phase 0: install/verify Godot and Blender are reachable from the terminal, scaffold the full repo structure from §3, initialize the Godot project targeting mobile landscape with the Forward+ or Mobile renderer, set up Android export presets, and commit."*
3. *"Create a spec for Phase 1: implement the grey-box core loop — mobile twin-stick controller, book-throw ballistics with a placeholder cube mesh, a basic bot opponent, round/knockout state machine, and a minimal HUD. Build and deploy to the emulator when done."*
4. *"Create a spec for Phase 2: write tools/generate_books.py and tools/generate_props.py per §4/§5, generate the first pass of book + Sky Library prop assets, import them into Godot replacing the placeholders, and write the cel-shading gdshader."*
5. Continue phase-by-phase down the table in §12, letting Kiro propose each spec's task breakdown and approving before it executes.

At each phase boundary, ask Kiro to **build and deploy to your device/emulator** so you're always looking at a running game, not just reading a diff.

---

## 14. Honest Recap of What Needs a Human Touch (Kept Minimal On Purpose)

- One-time selection/download of a base character mesh (§5, step 1) — everything downstream of that is Kiro-automated.
- One-time Mixamo upload/download per base body (§5, step 2) — a few minutes of clicking on a website, not game development.
- Downloading or generating audio files externally (§10) — Kiro integrates them, doesn't compose them.
- Google Play Console / Apple Developer accounts and any real-money IAP compliance steps — administrative/legal, not something an AI agent can or should do on your behalf.
- Accepting Android SDK license prompts and keeping an emulator/device available for Kiro to deploy test builds to.

Everything else — every script, every shader, every procedural 3D prop, every UI screen, every system in §4 and beyond — is fully within what Kiro can generate and wire together in code, exactly as you asked.





MAYBE HELPFUL USE THEM AND FREE ONES ONLY AND GOOD ONES WHICH MATCH THE IMAGES( D:\Book-bash\image.png       ,       ) ONLY


Yes. I searched current 2026 asset libraries and, for **Book Bash specifically**, there is a much better route than making every asset yourself.

The key is to build an **asset stack**: one character system, one animation system, one environment/prop family, then books + hats + VFX on top.

## My recommended Book Bash asset stack

| Need                                | Asset / Source                           | Why I would use it                                                                                                                                                                            |
| ----------------------------------- | ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Main characters**                 | **Quaternius Universal Base Characters** | 6 game-ready humanoids, multiple proportions, 20 hairstyles, humanoid rig, FBX + glTF, CC0. Very good base for your players. ([quaternius.com][1])                                            |
| **Lots of character variations**    | **Quaternius Ultimate Modular Men**      | 11 characters, 24 animations, modular body parts/clothing, FBX/OBJ/glTF/Blend, CC0. ([quaternius.com][2])                                                                                     |
| **Female variations**               | **Quaternius Ultimate Modular Women**    | 10 characters + 24 animations, modular parts, CC0. ([quaternius.com][3])                                                                                                                      |
| **Characters + clothing + hats**    | **Creative Characters FREE**             | 30 modular character assets including hats, hairstyles, outfits, shoes, glasses, accessories + 30 animations. FBX/glTF/OBJ. ([Fab.com][4])                                                    |
| **Animations — my #1 choice**       | **Universal Animation Library 2**        | 130+ animations, humanoid retargeting, locomotion, combat, combos, parkour, root-motion and non-root-motion versions; Unity/Godot/Unreal; CC0. ([itch.io][5])                                 |
| **Animations — older huge library** | **Universal Animation Library**          | 120+ animations including 8-direction locomotion, sprint, combat, emotes, death, etc. CC0. ([itch.io][6])                                                                                     |
| **Animation alternative**           | **Mixamo**                               | Thousands of mocap animations, automatic humanoid rigging and downloadable game-ready animations. Adobe says it can be used for personal/commercial games subject to its terms. ([Mixamo][7]) |
| **Books**                           | **Quaternius Fantasy Props MegaKit**     | Their current catalogue explicitly includes books, crates, potions, furniture, etc. and is CC0. ([quaternius.com][8])                                                                         |
| **Book projectile**                 | **Book – Low Poly**                      | 528 triangles; excellent starting point for the actual throwable book. ([Sketchfab][9])                                                                                                       |
| **Better book**                     | **FREE Simple Opening Book**             | ~1k triangles, low-poly, 4K textures, FBX; useful for hero book models. ([Sketchfab][10])                                                                                                     |
| **Book collection**                 | **Books Essentials**                     | Collection of free low-poly books with Blend/DAE/OBJ/FBX/GLB/STL. ([Sketchfab][11])                                                                                                           |
| **Bookshelves**                     | **Bookshelf – FractalSpace**             | Only ~1.6k tris; very good for mobile. ([Sketchfab][12])                                                                                                                                      |
| **Bookshelf alternative**           | **Bookshelf – Yağız Solmaz**             | 4.7k tris, textured, explicitly described for direct use in scenes. ([Sketchfab][13])                                                                                                         |
| **Furniture**                       | **Kenney Furniture Kit**                 | 140+ 3D assets, CC0. Excellent for tables/chairs/interior props. ([kenney.nl][14])                                                                                                            |
| **Environment pieces**              | **Kenney Building Kit**                  | 80+ walls/floors/doors/windows, OBJ/FBX/glTF, CC0. ([itch.io][15])                                                                                                                            |
| **VFX / impacts**                   | **Magic Effects FREE**                   | Free stylized Unity VFX with explosions, sparks, magic circles, slash/impact-style effects. ([marketplace.unity.com][16])                                                                     |
| **Impact feedback**                 | **Easy Impact Frames**                   | Free stylized impact-frame system for making hits feel much more powerful. ([marketplace.unity.com][17])                                                                                      |

## 🔗 Direct places to download / preview

### 1. Characters

**Best overall:**
[Quaternius Universal Base Characters](https://quaternius.com/packs/universalbasecharacters.html?utm_source=chatgpt.com)

This is probably where I'd start. It gives us the **base player skeleton** rather than grabbing random characters from 20 different artists. It is designed for retargeting and has customizable hairstyles. ([quaternius.com][1])

**More character variety:**
[Ultimate Modular Men Pack](https://quaternius.com/packs/ultimatemodularcharacters.html?utm_source=chatgpt.com)
[Ultimate Modular Women Pack](https://quaternius.com/packs/ultimatemodularwomen.html?utm_source=chatgpt.com)

**Characters + clothing + hats + accessories:**
[Creative Characters FREE](https://www.fab.com/listings/94fd60a2-5659-4fc4-af1d-a8cdd2681c2e?utm_source=chatgpt.com)

That last one is particularly interesting for **Book Bash cosmetics** because it includes hats, hairstyles, clothing, shoes, glasses and accessories. ([Fab.com][4])

---

# 2. Animations

### The one I'd download first

[Quaternius Universal Animation Library 2](https://quaternius.itch.io/universal-animation-library-2?utm_source=chatgpt.com)

This is extremely useful for Book Bash.

It has **130+ animations**, including:

```text
Idle
Walk
Run
8-direction movement
Jump
Fall
Parkour
Combat
3-hit combos
4-hit combos
Recovery
Root motion
Non-root motion
```

and it supports Unity, Godot and Unreal with retargeting. It's CC0. ([itch.io][5])

### First animation library

[Universal Animation Library](https://quaternius.itch.io/universal-animation-library?utm_source=chatgpt.com)

120+ animations and especially useful for basic locomotion/combat. ([itch.io][6])

### Mixamo

[Mixamo](https://www.mixamo.com/?utm_source=chatgpt.com)

This is the place I'd use when we specifically need an animation such as:

```text
Throw
Dodge
Roll
Jump
Sprint
Celebrate
Taunt
Hit reaction
Fall
Get up
```

Mixamo supports automatic rigging and has thousands of motion-captured animations. ([Mixamo][7])

**Important for your project:** don't build every character separately around Mixamo. Use **one humanoid base rig**, then retarget animations onto your characters.

---

# 3. Books

For Book Bash, I'd actually use **multiple book assets**.

### Lightweight projectile

[Book — Low Poly](https://sketchfab.com/3d-models/book-low-poly-bc2e219d4e4546b3b37c9cde7425691a?utm_source=chatgpt.com)

Only 528 triangles. That's excellent for a projectile that might be flying around constantly. ([Sketchfab][9])

### Hero book

[FREE Simple Opening Book](https://sketchfab.com/3d-models/free-simple-opening-book-334ac25cb42f484bae059b920aed0e4f?utm_source=chatgpt.com)

~1k triangles, low-poly and has textures. ([Sketchfab][10])

### Collection

[Books Essentials](https://sketchfab.com/3d-models/books-essentials-1b5fe01e6d464837ae7e03745fd58ff5?utm_source=chatgpt.com)

This gives you a collection rather than one identical book repeated everywhere. ([Sketchfab][11])

---

# 4. Bookshelves / Library

### Very lightweight bookshelf

[Low-Poly Bookshelf](https://sketchfab.com/3d-models/bookshelf-e271b784fb9449b78771e21518368ba0?utm_source=chatgpt.com)

Only around **1.6k triangles**, which is much more sensible for a mobile game than importing giant 100k+ triangle furniture models. ([Sketchfab][12])

### More detailed bookshelf

[Textured Bookshelf](https://sketchfab.com/3d-models/bookshelf-b622a0d9698d4c52ae2b9e06376adfe1?utm_source=chatgpt.com)

~4.7k tris with textures. ([Sketchfab][13])

---

# 5. Tables, chairs, interior props

### Kenney Furniture Kit

[Kenney Furniture Kit](https://kenney.nl/assets/furniture-kit?utm_source=chatgpt.com)

This one is a **very good foundation** for the library because it's 140+ furniture assets and CC0. ([kenney.nl][14])

Use it for:

```text
Tables
Chairs
Benches
Beds
Shelves
Cabinets
Small props
```

---

# 6. Environment construction

### Kenney Building Kit

[Kenney Building Kit](https://kenney.nl/assets/building-kit?utm_source=chatgpt.com)

80+ modular pieces and CC0, including walls, floors, doors and windows. ([itch.io][15])

This is useful because instead of downloading **one giant library scene**, we construct:

```text
Wall
+
Floor
+
Window
+
Door
+
Shelf
+
Pillar
+
Stairs
+
Props
=
OUR LIBRARY
```

That gives us much more control.

---

# 7. Hit effects / book impact VFX

### Magic Effects FREE

[Magic Effects FREE](https://marketplace.unity.com/packages/vfx/particles/spells/magic-effects-free-247933?utm_source=chatgpt.com)

It includes stylized effects useful for impacts, sparks, magic and exaggerated hits. ([marketplace.unity.com][16])

### Impact frames

[Easy Impact Frames](https://marketplace.unity.com/packages/vfx/shaders/easy-impact-frames-355376?utm_source=chatgpt.com)

This is particularly relevant to Book Bash because **the impact is supposed to feel hilarious and satisfying**. ([marketplace.unity.com][17])

### Browse more VFX

[Unity VFX library](https://assetstore.unity.com/vfx?utm_source=chatgpt.com)

Unity separates particles, shaders, free VFX, toon VFX, magic VFX, etc. ([Unity Asset Store][18])

---

# 8. A very useful giant source: Quaternius

[Quaternius Free Game Assets](https://quaternius.com/?utm_source=chatgpt.com)

This is probably the **single website I'd spend the most time on for Book Bash**.

It currently has:

```text
Characters
Animated characters
Buildings
Furniture
Fantasy props
Nature
Vehicles
Animation libraries
Modular environments
```

and many of the packs are CC0. ([quaternius.com][8])

---

# 9. Another excellent source: Kenney

[Kenney 3D Assets](https://kenney.nl/assets?utm_source=chatgpt.com)

Kenney is fantastic for filling all the boring-but-important gaps:

```text
Furniture
Buildings
Props
Nature
Roads
Decoration
Environment pieces
```

Many of its packs are CC0. For example, the Furniture Kit and Building Kit are CC0. ([kenney.nl][14])

---

# 10. Sketchfab — use this for individual hero assets

[Sketchfab downloadable 3D models](https://sketchfab.com/3d-models?features=downloadable&utm_source=chatgpt.com)

It is particularly useful when we need something very specific:

```text
special hat
rare book
ornate bookshelf
owl
cat
lamp
globe
clock
statue
special prop
```

But **check the license on every model**. Sketchfab has many different licenses; don't assume every downloadable model is commercially reusable.

For example, the low-poly book listings above have different licensing terms, so check the individual page before shipping. ([Sketchfab][9])

---

# What I would actually download for Book Bash

I wouldn't download 500 random assets.

I'd start with this exact stack:

```text
CHARACTER
    ↓
Quaternius Universal Base Characters
    ↓
ANIMATION
    ↓
Universal Animation Library 2
    ↓
OPTIONAL EXTRA ANIMATION
    ↓
Mixamo
    ↓
LIBRARY
    ↓
Kenney Furniture Kit
+
Kenney Building Kit
+
Low-poly Bookshelves
    ↓
BOOK
    ↓
Low-poly Book
+
Books Essentials
    ↓
COSMETICS
    ↓
Creative Characters FREE
    ↓
VFX
    ↓
Magic Effects FREE
+
Impact Frames
```

That gives you a **coherent asset ecosystem** instead of the ugly situation you just saw where every object looks like it came from a completely different game.

### One especially important recommendation

For **your actual Book Bash character**, I would use **Quaternius Universal Base Characters + Universal Animation Library 2 + modular cosmetics** rather than hunting for a finished character.

That lets you build:

```text
             BOOK BASH CHARACTER
                     │
        ┌────────────┼────────────┐
        ↓            ↓            ↓
      BODY          CLOTHES       HAIR
        │            │            │
        └────────────┼────────────┘
                     ↓
                  HAT
                     ↓
                BACKPACK
                     ↓
               BOOK SKIN
                     ↓
                TRAIL
```

So the **same character skeleton** can become 50+ visually different characters without creating 50 completely different rigs.

And for the web version you're building, prioritize **GLB/glTF** wherever available; it keeps the pipeline much cleaner than repeatedly converting FBX assets.

[Quaternius Universal Base Characters](https://quaternius.com/packs/universalbasecharacters.html?utm_source=chatgpt.com) · [Universal Animation Library 2](https://quaternius.itch.io/universal-animation-library-2?utm_source=chatgpt.com) · [Mixamo](https://www.mixamo.com/?utm_source=chatgpt.com) · [Kenney Furniture Kit](https://kenney.nl/assets/furniture-kit?utm_source=chatgpt.com) · [Kenney Building Kit](https://kenney.nl/assets/building-kit?utm_source=chatgpt.com)

[1]: https://quaternius.com/packs/universalbasecharacters.html?utm_source=chatgpt.com "Quaternius • Universal Base Characters"
[2]: https://quaternius.com/packs/ultimatemodularcharacters.html?utm_source=chatgpt.com "Quaternius • Ultimate Modular Men Pack"
[3]: https://quaternius.com/packs/ultimatemodularwomen.html?utm_source=chatgpt.com "Quaternius • Ultimate Modular Women Pack"
[4]: https://www.fab.com/listings/94fd60a2-5659-4fc4-af1d-a8cdd2681c2e?utm_source=chatgpt.com "Creative Characters FREE - Animated Low Poly 3D Models | Fab"
[5]: https://quaternius.itch.io/universal-animation-library-2?utm_source=chatgpt.com "Universal Animation Library 2 by Quaternius"
[6]: https://quaternius.itch.io/universal-animation-library?utm_source=chatgpt.com "Universal Animation Library by Quaternius"
[7]: https://www.mixamo.com/?modal=S&redir=%2Fmystuff%2Fcharacters&utm_source=chatgpt.com "Mixamo"
[8]: https://quaternius.com/?utm_source=chatgpt.com "Quaternius • Free Game Assets"
[9]: https://sketchfab.com/3d-models/book-low-poly-bc2e219d4e4546b3b37c9cde7425691a?utm_source=chatgpt.com "Book (Low Poly) - Download Free 3D model by game_travel [bc2e219] - Sketchfab"
[10]: https://sketchfab.com/3d-models/free-simple-opening-book-334ac25cb42f484bae059b920aed0e4f?utm_source=chatgpt.com "FREE Simple Opening Book - Download Free 3D model by Cécile Amstad (@c.m.a) [334ac25]"
[11]: https://sketchfab.com/3d-models/books-essentials-1b5fe01e6d464837ae7e03745fd58ff5?utm_source=chatgpt.com "Books Essentials - Download Free 3D model by Daniel.Riches [1b5fe01] - Sketchfab"
[12]: https://sketchfab.com/3d-models/bookshelf-e271b784fb9449b78771e21518368ba0?utm_source=chatgpt.com "Bookshelf - Download Free 3D model by FractalSpace [e271b78] - Sketchfab"
[13]: https://sketchfab.com/3d-models/bookshelf-b622a0d9698d4c52ae2b9e06376adfe1?utm_source=chatgpt.com "Bookshelf - Download Free 3D model by Yağız Solmaz (@yagiz.slz) [b622a0d] - Sketchfab"
[14]: https://kenney.nl/assets/furniture-kit?utm_source=chatgpt.com "Furniture Kit · Kenney"
[15]: https://kenney-assets.itch.io/building-kit?utm_source=chatgpt.com "Building Kit by Kenney (Assets)"
[16]: https://marketplace.unity.com/packages/vfx/particles/spells/magic-effects-free-247933?utm_source=chatgpt.com "Magic Effects FREE | Spells | Unity Asset Store"
[17]: https://marketplace.unity.com/packages/vfx/shaders/easy-impact-frames-355376?utm_source=chatgpt.com "Easy Impact Frames | VFX Shaders | Unity Asset Store"
[18]: https://assetstore.unity.com/vfx?utm_source=chatgpt.com "The Best Assets for Game Making | Unity Asset Store"
