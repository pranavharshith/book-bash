# Book Bash implementation status

Validated against `book-bash-3d-development-plan.md` on September 10, 2026.

## Implemented

- Mobile-landscape Godot project, Android debug export, launcher configuration, and Internet permission.
- Shared human/bot `CharacterBody3D` combat controller with acceleration, friction, dodge i-frames, hit stun, directional knockback, three stocks, safe respawns, and ring-out handling.
- Camera-relative keyboard/touch movement, independent touch drag aim/charge, desktop mouse aim, ballistic assist, responsive camera framing, camera shake, and survivor focus.
- Dynamic per-model `AnimationTree` state machine for Idle, Walk, Run, Throw, Hit, Dodge, and KO. The current GLBs contain every graph clip; a direct `AnimationPlayer` fallback protects future incomplete cosmetic imports.
- Swept projectile collision, imported book visuals, host-authoritative pickup claims/availability, local pickup respawns, bot state machine, line-of-sight throwing, stuck recovery, and incoming-projectile dodging.
- Countdown/live/end gating, timer, dynamic six-player stock/health HUD, saved-result feedback, and post-match return flow.
- Six selectable arenas with generated layouts, toon-shaded cover, unique palettes, and host-authoritative hazards: Sky gusts/ring-outs, Classroom chalkboard power-up reveals, Ancient Ruins collapsing shelf lanes, Tech conveyors, Candy syrup/gumdrop bounce, and Volcano safe-zone shrink.
- Imported character, book, and bookshelf GLBs; procedural accessories; paper trails; impact particles; positional footsteps/impacts; and randomized impact variants.
- Versioned local JSON profile with transactional in-memory commits and on-disk temporary/backup rotation; two currencies; inventory/equipment; cosmetic catalog; purchases; match rewards; XP; player stats; Battle Pass lanes; and persistent map selection.
- Functional Lobby, Customize, Store, Battle Pass, Map Select, Multiplayer, and match HUD screens, including clear feedback when a profile save fails.
- ENet host/join lobby for 2–6 players, peer registration, bot-filled roster, LAN/public endpoint joining, late-join lockout, owner movement prediction, bounded host correction, reliable action replication, host-authoritative combat/results, disconnect forfeits, and dedicated-server command-line startup.
- `tools/import_character.py`: a local Blender FBX-to-GLB helper for licensed character sources and their imported animation actions.

## Validation completed

- Godot 4.7 headless project import and script/resource parse: passed after the final AnimationTree conversion.
- Lobby plus Customize, Store, Battle Pass, Map Select, and Multiplayer scene smoke runs: passed.
- All six arena scene smoke runs: passed. Classroom Chaos and Ancient Ruins were also run long enough to enter their timed hazard windows.
- Six-fighter Sky Library bot-match smoke after the AnimationTree conversion: passed without script/runtime errors.
- Concurrent two-process ENet localhost session after the final code changes: passed. Host admitted two of six human slots, synchronized the lobby, autostarted a match, and handled client departure without script/RPC errors.
- Android debug export: passed; the APK was aligned, debug-signed, verified, and includes `android.permission.INTERNET`.
  - Artifact: `build/book-bash-debug.apk`
  - Size: 92,837,806 bytes
  - SHA-256: `170ADB14E268CBFFDA6734E397A5E0BD8F3F8136F84584AA0048B8AFAC7C67F7`

Forced `--quit-after` scene checks can report active OGG playback resources during shutdown. Verbose inspection ties those warnings to active footstep/impact playback, not gameplay-script failures. A normal device-session exit remains part of physical QA.

## External or human-only release requirements

1. **Internet hosting/relay:** LAN and direct public-endpoint play are complete. Production Internet play still needs a publicly reachable UDP host/dedicated instance or relay, firewall/NAT setup, operational monitoring, and a service budget/domain as applicable.
2. **Real-money purchases:** the premium balance and purchase seam exist, but real-money grants are disabled. Configure Google Play/App Store products, platform billing, receipt validation, restore behavior, tax/privacy disclosures, and sandbox testing before enabling them.
3. **Release signing and store administration:** create and protect a release keystore, provide final versioning/icons/listing assets, complete Play Console declarations/testing tracks, and use a Mac plus an Apple Developer account for iOS release work.
4. **Final animation art:** existing GLBs fully drive the current combat graph. A one-time licensed Mixamo/retargeting pass is needed only for final authored clips that are not supplied (notably Victory, and optional distinct Knockback/Stumble or split throw windup/release clips) and to validate final hat bone sockets.
5. **Music/audio sourcing:** all supplied runtime SFX are integrated. No music asset exists in `assets/audio/music`; licensed or original music must be supplied externally before a final audio pass.
6. **Third-party provenance:** archives under `SOME ASSESTS/` remain staging-only because `.gdignore` excludes them and their filenames do not establish license/provenance. Do not ship their contents until each license is verified and retained. Runtime integration intentionally uses the imported GLBs/OGGs plus code-generated geometry and VFX.
7. **Physical-device QA:** test representative low/mid/high Android devices, ultrawide/notched displays, tablets, touch sampling rates, Wi-Fi latency/loss, thermal behavior, animation appearance, audio mix, accessibility, and readability before store release.

## Security boundary

The host validates damage, stocks, hazards, bots, pickups, and results. Movement submissions are finite-checked and distance-bounded. Friendly direct-host games are supported; a competitive economy should use an authenticated dedicated service and server-side profile persistence rather than trusting local save files.
