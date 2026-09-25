# Live Process Monitor v0.2 — implementation workplan

Status: implemented; signed-distribution acceptance remains open, 2026-09-24. Source of truth: `../product/live-process-monitor-v0.2.md` and `live-process-monitor-v0.2.md`; Figma nodes `28:2`, `33:2`, `38:4`, `45:2`. This phase implements the feature, not a new release channel. Existing uncommitted repository changes belong to the user; preserve unrelated work and do not commit.

## Deliverable and acceptance

A runnable macOS Tauri app with an independent all-process view, CPU/RSS/status/sockets columns, on-demand command detail, process-scoped socket navigation, and separate process/socket failure handling. The existing socket view remains the launch view. Browser preview uses explicit fixture data.

Acceptance completed: current-PID identity read and all-process enumeration work on this Mac; CPU warms up before reporting a value; zero-socket processes appear; PID plus start token guards detail and socket attribution; search/filter/sort/detail/navigation work; source caches preserve last-good readings. Rust tests: 12 passed; `cargo fmt --check`, `pnpm check` (0 errors/warnings), `pnpm build`, and `git diff --check` pass. An unsigned debug `.app` passed native live-list, detail, and scoped-socket smoke checks at the 760×520 logical size. Remaining release gates: signed outside-store bundle/entitlements, Intel, forced-source-failure coverage, systematic permission-gap checks, and sustained performance measurements.

## Sequence and ownership

1. Spike macOS process availability and high-resolution identity using the already-cached `libc` binding; verify current PID and real process enumeration before committing to the collector design. If it fails, stop identity-sensitive work and report the exact limit.
2. Backend: process snapshot collector owns one `sysinfo::System`; socket collector remains `netstat2`. State owns latest successful snapshot and error per source. A single refresh request/timer coalesces cycles, samples process first, then sockets, and emits independent results. No subprocess `top`.
3. Data contracts: process instance key includes PID plus macOS start seconds/microseconds when available. Commands/executable are requested only for a selected, identity-verified process. Socket rows retain raw PID and attach a verified process key only when the latest process inventory and OS identity agree.
4. Frontend: separate view-specific filters and sort; reuse existing shell/tokens/local Figma icons. Add process table, detail, socket drill-down, loading/sampling/paused/stale/partial states. Do not install Tailwind or paste generated React code.
5. Validate with focused unit tests, workspace checks, native smoke, and a 760×520 visual comparison. Keep an unresolved list for packaged signing/notarization and any per-field OS access limits.

## Non-goals and risks

No Mac App Store, root/helper, kill/stop, history, network throughput, exact `top MEM` parity, database, or broad collector rewrite beyond what the new flow requires. Main risks: mixed-generation socket/process joins, macOS permission gaps, stale event ordering, per-PID sampling cost, command-line secrets, and the existing dirty worktree.
