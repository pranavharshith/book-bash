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
