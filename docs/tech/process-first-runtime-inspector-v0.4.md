# PortMaster v0.4 — Process-first Runtime Inspector

Status: approved for implementation through Cursor, 2026-09-24.

## Deliverable and authority
A working local macOS Tauri/Rust/Svelte app implementing the six screens on https://www.figma.com/design/0ZTUdO0569Qi4mGusqJiTI?node-id=20-2 .
The page is now “v0.4 Redesign — Process-first Runtime Inspector”; the file title still says v0.3. Frames 20:3–20:8 are the visual source of truth.
This direction supersedes the port-first navigation in docs/product/portmaster-professional-user-prd-v0.3.md, which remains historical context.
User approved: Processes primary; Ports secondary; working macOS app (not fixture-only); verified CWD with explicitly labeled executable/app fallback; Terminal opens verified CWD; listeners first with All sockets retained.
Preserve existing uncommitted work. Do not commit, stage, reset, stash, clean, or overwrite unrelated work.

## Scope and non-goals
Reuse the existing Tauri 2, Svelte 5, TypeScript, plain CSS, sysinfo and netstat2 implementation.
Retain independent process/socket last-good caches, coalesced refreshes, and ProcessKey (pid/startSec/startUsec).
No process kill/restart, execution of inspected commands, database/history, upload/telemetry, repository introspection, framework replacement, or signing/notarization work.
“v0.4” is the product milestone; avoid unrelated package-version changes.

## Implementation sequence

### 1. Baseline and design preparation
Record frontend/Rust baseline checks; distinguish old failures from regressions.
Keep this workplan current and mark the v0.3 navigation superseded.
Extract reusable toolbar, process table, ports table, inspector, and status UI rather than adding to the monolithic route.
Use Figma context and screenshots for all six frames. Generated React/Tailwind is reference only: translate to Svelte/plain CSS. Bundle Inter/JetBrains Mono with licensing and required SVG assets locally, reuse exact existing matches. Generic macOS Code Connect snippets have no installed implementation here; use native window controls and Svelte controls.

### 2. Backend evidence
Implement a narrow macOS context reader with proc_pidinfo(PROC_PIDVNODEPATHINFO) for CWD and proc_pidpath for executable.
Read process context in the existing background refresh, not one invoke per visible row. Verify identity before/after context reads.
Extend ProcessEntry with explicit available/restricted/unavailable path evidence. Snapshot capturedAt timestamps the evidence. Do not reuse a failed prior CWD as newly observed.
Prefer CWD. If absent, show “App: …” or “Executable: …”; derive app bundle path only from observed executable path. Do not infer a repository or “System” from process name. Home-directory abbreviation is display-only.
Extend ProcessDetail with evidence, collection/verification timestamps, and observed parent ancestry. Commands remain on demand.
Read at most eight parent links, validate identities/relationships, stop on missing identity, exit or cycles, and label incomplete ancestry.
Keep selection keyed by the full ProcessKey; exited/changed process never silently follows PID reuse.
Refresh open detail after completed monitor cycles; allow one in-flight request, coalesce follow-up work and discard obsolete responses.

### 3. Terminal boundary
Add open_process_terminal(key: ProcessKey) Tauri command.
Resolve and reverify CWD in Rust at click time and require an existing directory. Do not trust a frontend-supplied path.
Use /usr/bin/open with fixed Terminal application arguments and the absolute directory as a separate argument; no shell interpolation, AppleScript execution of process commands, or executable-directory fallback.
Unavailable identity/CWD and launch failures are actionable inline states, not silent failures.

### 4. Layout and interactions
Match reference 760×520 layout: 52px toolbar, approximately 32–34px header, 46px rows, 24px status footer, 336px inspector and 424px master when selected.
Use real native macOS traffic lights with overlay title bar, hidden native title, reserved controls area and toolbar drag regions. No duplicated fake native controls. Browser fixtures may render clearly identified preview controls.
Minimum size 640×420. Compact overview hides PID; below 760px selected inspector replaces content with Back. Tables/inspector scroll vertically; no horizontal page overflow.
Default Processes to CPU descending; support CPU, memory and PID sort with unknown last and deterministic ties.
Search name, PID, local service port and available context paths. Numeric queries match exact PID/port; other queries are case-insensitive substrings.
Preserve per-view query, filters, sort, scroll, selection. Filtering out a selected process does not select another process.
Process row opens inspector; port chip opens Ports scoped to full process identity and port; port row opens verified owning-process inspector.
Deduplicate port numbers in chips only. Preserve address/protocol/owner rows and all socket attribution evidence.
Default Ports to TCP LISTEN and bound UDP endpoints. All sockets preserves existing connection inspection. Show UDP as BOUND, not LISTEN. Show protocol near state/address without disrupting the design.
Retain unverified-owner rows with explanation. Never manufacture owner context from matching PID alone.
Keep refresh interval/pause/protocol/visibility and relevant existing filters in a compact status-bar popover.
Keyboard-operable rows, aria-sort headers, visible focus, clear search, Escape/Back close, accessible disabled states.
Show inspector CWD, command, CPU, RSS, uptime, ancestry, endpoints, identity verification; expandable full executable/start time.
Copy a readable report of full paths, command arguments, process identity, endpoints, timestamps and unavailable states. Show copy success/failure. No auto-copy.
Use native Clipboard support if browser clipboard is not dependable in Tauri; validate actual native clipboard behavior.

### 5. Freshness and failures
Separate process/socket/detail freshness and validity. Relative age plus accessible exact timestamp.
Stale threshold = max(3 × refresh interval, 5000ms); failed source immediately stale. Paused/refreshing must not claim fresh verification.
Keep last-good data with stale labels; no error-to-zero conversion. CPU remains unknown until valid spaced samples.
Retain exited selections and last observations, label them, disable Terminal.
Harden bootstrap/event generation ordering: an older bootstrap, success, error, or completion must not overwrite newer state or clear a newer failure.
Retain independent process and socket sources; successful process refresh cannot make stale socket facts current.

## Validation and acceptance
- Rust: explicit CWD unavailable/permission/changed/exited paths, identity changes during reads, ancestry gaps/cycles, Terminal argument safety and refusal rules; existing collector tests remain passing.
- Vitest: exact numeric/text search, sort null/ties, port grouping/owner key, independent stale states, out-of-order events/bootstrap, late inspector replies and selection persistence.
- Playwright fixtures: all six reference screens, compact inspector, long paths, empty states, source failures, exited selection, keyboard flows. Fixtures must remain visibly identifiable as preview and never be native production evidence.
- Commands: pnpm check; pnpm build; frontend tests; cargo fmt --manifest-path src-tauri/Cargo.toml --check; cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings; cargo test --manifest-path src-tauri/Cargo.toml; git diff --check.
- Native macOS: two same-name development processes from different CWDs, search by name/port/path, inspect same identity; IPv4/IPv6, UDP, multi-owner/unknown attribution; Copy; Terminal opens correct CWD including spaces, quotes, Unicode; exit/stale/permission/pause/resume/rapid selection.
- Visual: six Figma frames at 760×520 and compact 640×420, no horizontal overflow, no duplicated window chrome. Record screenshots and scoped deviations.
- Performance: at least 1000 fixture processes, filter/sort within 100ms; full native refresh below configured interval on test Mac. Record timing rather than assert undocumented performance.
- Deliver runnable app, changed-files summary, tests/results, native evidence and explicit unresolved gates. Signing/notarization/Intel acceptance is separate.

## Planning evidence and risks
Read-only unsandboxed CLI probe on this Mac: 646 processes; 420 CWD available, 219 permission denied, 7 gone; CWD reads ~2ms. This is feasibility evidence only, not packaged-app acceptance.
Installed sysinfo 0.39.6 returns early after failed CWD read without clearing old cached CWD, so use explicit native per-read outcome rather than pretending its cached value is fresh.
Current worktree contains substantial prior process-monitor work on main. A baseline file snapshot is held outside the repository for review; preserve it, never restore over newer user work.

## Progress
- [x] Implementation and extracted six-screen UI delivered; existing dirty work preserved.
- [x] Verified native CWD/executable evidence, full ProcessKey, bounded ancestry, safe Terminal command and independently versioned process/socket refreshes.
- [x] Per-view selection/scroll/history, reactive coalesced details, stale/out-of-order event rejection and exact historical copy reports.
- [x] Final `pnpm check`, web build,27Vitest,18Playwright and13independent integration checks passed.
- [x] Final Rust formatting, clippy with warnings denied,25native tests and debug macOS app build passed.
- [x] Seven preview captures/geometry checks; final app launched; native CWD/search/endpoints/Copy/pause/resume/exit smoke completed. Owned fixture processes cleaned up.
- [ ] Terminal window CWD verification: computer-use tool blocks Terminal; backend argument/refusal tests passed.
- [ ] Native permission-denied/unknown-owner and sustained full-cycle performance acceptance; signing/notarization/Intel remain separate.
- Detailed evidence, changed-module summary, scoped visual deviations and Cursor/local-fix provenance: [v0.4 verification](../verification/v0.4-codex-acceptance.md).

## Handoff authentication (resolved)
Cursor CLI initially exited with “Authentication required” before implementation (`/private/tmp/portmaster-v04-cursor-handoff/cursor-retry-stderr.log`). The user completed re-authentication; this session resumed implementation successfully.
