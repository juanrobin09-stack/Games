# Porting EMBERFALL: LAST LIGHT to Steam / Desktop

This document describes what would genuinely be required to ship EMBERFALL as a commercial desktop title on Steam. **Nothing described here is implemented in this repository** — there is no Steamworks SDK call, no achievement stub, no fake overlay hook anywhere in the code. This is a plan, not a pretend integration.

## 1. Desktop shell

The game is a static web build (`dist/`: one HTML file, one CSS bundle, one JS bundle, zero network calls at runtime). Two realistic paths to a desktop executable:

- **Electron / Tauri wrapper.** Wrap `dist/` in a minimal desktop shell. Tauri produces a much smaller binary (no bundled Chromium) and has a smaller attack surface, at the cost of using the OS's system webview (behavior can vary slightly by platform); Electron guarantees a consistent Chromium version everywhere at the cost of a much larger install size. For a small, canvas+Web-Audio-only game like this with no exotic browser API usage, **Tauri is the better default recommendation** — the game doesn't need anything Electron uniquely provides.
- **Native reimplementation (Godot).** See `GODOT_MIGRATION.md`. This is the better long-term path if the game will receive substantial post-launch content, since it gets native performance, real input remapping, and first-party Steamworks GDExtension support instead of a JS↔native bridge.

Either way, the *game logic* (everything outside `rendering/`, `audio/` synthesis, and `ui/`) does not change — that separation was the point of the current architecture.

## 2. What must change vs. the web build

| Concern | Web build today | Desktop/Steam requirement |
|---|---|---|
| Save location | `localStorage`, one browser-scoped slot | A real file under the OS's per-user app-data directory (e.g. `%APPDATA%/Emberfall/`, `~/Library/Application Support/Emberfall/`, `~/.local/share/Emberfall/`), or Steam Cloud (see §4) |
| Resolution | Fills the browser viewport, responsive via `ResizeObserver` | A real display-mode setting (windowed / borderless / exclusive fullscreen) with a resolution list from the OS, persisted in settings |
| Fullscreen | `document.documentElement.requestFullscreen()`, best-effort | Native fullscreen toggle owned by the shell (Tauri/Electron window API, or the engine if reimplemented) — must work reliably, not "best effort" |
| Input | Keyboard/mouse + a touch overlay for mobile browsers | Add real **gamepad support** (Steam's primary controller expectation) and **key rebinding**; the touch overlay becomes irrelevant on desktop and should be disabled outright, not just hidden |
| Audio unlock | Requires a user gesture before `AudioContext` starts (a browser restriction) | Not applicable on desktop — audio can start immediately on launch |
| Update delivery | Redeploy the static site | Steam's own build/depot system (or the shell's auto-updater) |
| Process lifetime | A browser tab; closing it forfeits an in-progress run by design | Desktop players will expect *at least* a "resume where you left off" confirmation on relaunch after a crash — see §5 |

## 3. Resolution & display

- Replace the `ResizeObserver`-driven canvas sizing with an explicit **Settings → Display** panel: resolution dropdown (populated from the OS/monitor), Windowed / Borderless / Fullscreen mode, and a separate UI-scale slider (already partially present as the accessibility "Text Size" setting — extend it to scale the whole HUD, not just text).
- The adaptive camera zoom (`Game.ts`'s `updateCameraZoom`) already targets "fill the viewport well at any aspect ratio," which is the correct behavior to keep — it just needs to react to real display-mode changes instead of only browser window resizes.
- Support ultrawide and 4K explicitly in QA; the room-based camera (fixed room size, adaptive zoom, clamped pan) already scales cleanly to unusual aspect ratios by construction, but should be verified at 21:9 and 4K before launch.

## 4. Save data & Steam Cloud

- Keep the existing versioned JSON shape and the defensive load/validate/migrate pattern in `progression/SaveSystem.ts` — that logic is engine-agnostic and already handles corruption gracefully; only the storage backend changes (see §1 comparison table).
- For Steam Cloud: register the save file's local path with Steam's auto-cloud feature (via `steam_appid.txt` + the app's Steamworks configuration — no code changes needed for basic file sync) or use the explicit `ISteamRemoteStorage` API if finer control over conflict resolution is wanted.
- **Conflict resolution is the one real design decision here**: if the same save is played on two machines and both go offline, whose changes win? At minimum, compare the save's own internal counters (`stats.totalRuns`, Soul Ash totals) and refuse to silently overwrite a save that looks "further along" than the incoming cloud copy; surface a manual choice to the player if the two saves genuinely disagree.

## 5. Process lifetime & run persistence

The current design intentionally forfeits an in-progress run if the tab is closed (a genre convention — Soul Ash from *completed* runs is never lost, only the active run). On desktop, players will crash their machine, close the game by accident, or want to quit mid-run without being punished for something that wasn't a deliberate "abandon." Two reasonable options, in order of recommendation:

1. **Auto-save the active run's state on quit/crash** (current room, player stats/HP, owned upgrades, embers) and offer "Resume Run" on next launch alongside "New Run." This is the most player-friendly option and doesn't compromise the roguelite's permadeath identity — permadeath means *death* ends the run, not *closing the application*.
2. At minimum, a confirmation dialog on quit while a run is active ("Quit now and forfeit this run?"), so an accidental Alt+F4 doesn't feel like a bug.

## 6. Input

- Add a real **gamepad** binding layer (Steam Input / the Gamepad API if staying in a webview shell) — this is close to mandatory for Steam, where controller usage is high. The existing action model (`InputManager`'s `move` / `attack` / `dodge` / `ability` / `interact` / `pause`) already maps cleanly onto a controller (left stick move, right stick or face-button-relative aim, shoulder buttons for attack/ability, a face button for dodge/interact) — the abstraction doesn't need to change, only the concrete bindings.
- Add **key/button rebinding** in Settings; PC players expect this as standard, and it's a small addition on top of the existing action-based input model.
- Retire the touch overlay (`ui/TouchControls.ts`) entirely on desktop builds rather than hiding it — it should never be reachable via the pointer/coarse detection on a desktop target.

## 7. Performance targets

- The web build already follows the practices that matter for a native port: object pooling for particles/damage numbers, a capped particle budget, spatial partitioning for enemy separation, and delta-time-based movement throughout — none of that needs to be re-derived for desktop.
- Desktop hardware variance is still real (a Steam Deck vs. a high-end desktop). Keep the existing Graphics/Particle quality settings and validate the "Low" tier specifically against Steam Deck-class integrated graphics; the canvas backing-resolution scale (`Renderer.setQualityScale`) is the right lever and should map directly to whatever the target renderer's resolution-scale equivalent is.
- If reimplemented in Godot: profile `_physics_process` cost with a full room of enemies + boss adds + a wave of projectiles before assuming the web build's numbers (enemy counts, particle caps) transfer as-is — engine overhead per node differs from a flat-array update loop.

## 8. Steamworks integration — what would actually be needed

None of this exists in the repo. If pursued, in priority order:

1. **Steamworks SDK initialization** (`SteamAPI_Init`) at process start, with a graceful "Steam is required / not running" fallback message rather than a crash — required by Steam's distribution terms for any app using the SDK.
2. **Rich Presence** (what zone/state the player is in) — cheap to add given the existing `GameStateMachine` and `RunState` already track exactly this.
3. **Achievements** mapped to existing, real milestones the game already tracks: first Colossus kill, a full run without dying, unlocking every weapon/ability, reaching each zone, a given Soul Ash total. No new tracking systems needed — `SaveSystem`'s `stats` object already has most of the raw numbers.
4. **Steam Cloud** for saves (§4).
5. **Steam Input** for controller configuration (§6), including default binding templates (Steam Deck, standard Xbox/PlayStation layouts).
6. *(Optional, lower priority)* Leaderboards for fastest Colossus kill / deepest run — would need a small addition to `RunState`/`SaveSystem` to track a "best run" record beyond the current lifetime stats, but nothing architecturally new.

## 9. Recommendation summary

For a genuine commercial release: reimplement in Godot (per `GODOT_MIGRATION.md`) rather than shipping a wrapped web build long-term. A wrapped build is a reasonable **first Early Access build** to validate demand with minimal extra engineering, but native Steamworks support (achievements, cloud saves, Steam Input, Deck verification) is meaningfully easier to build and maintain in an engine with first-party GDExtension/plugin support than through a JS↔native bridge in a wrapped webview.
