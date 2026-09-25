# Live Process Monitor — macOS implementation design

Status: implemented; signed distribution acceptance remains open, updated 2026-09-24. Product source of truth: [live-process-monitor-v0.2.md](../product/live-process-monitor-v0.2.md). Versions verified in this checkout: `sysinfo 0.39.6`, `netstat2 0.11.2`, `Tauri 2.11.6` (`src-tauri/Cargo.lock`). The current app is a Tauri/Svelte macOS utility window. The design rationale below includes pre-implementation baseline notes; the implementation record near the end is authoritative for what has actually been built and tested.

Distribution decision (user-confirmed): **do not ship through the Mac App Store**. The intended path is distribution outside the store; the exact packaging channel is not yet chosen. Developer ID signing/notarization is compatible with that path and does not itself require App Sandbox, but the final entitlements and bundled app must be checked. [Apple distribution guidance](https://developer.apple.com/documentation/Xcode/preparing-your-app-for-distribution), [notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Decision

Use the existing `sysinfo` crate for a persistent, all-process CPU/RSS/status sampler. Keep `netstat2` for sockets. Do **not** execute or parse `top` as a production feed. A narrow macOS adapter uses `libc::proc_pidinfo(PROC_PIDTBSDINFO)` for a high-resolution process start token; the focused spike passed on this Apple Silicon Mac, so a separate `libproc` dependency was unnecessary. Collect command and executable **on demand** when a detail pane opens, not for every process on every tick. Publish process and socket snapshots as independently successful/erroring data sources, even if the same timer triggers both.

This is an intentional expansion of the current selected-socket process inspector; simply changing its PID query to `All` would leave process visibility dependent on `netstat2` succeeding and would put every command line into each socket event.

## Pre-implementation baseline and gap

- `collector/netstat2.rs` uses `netstat2::get_sockets_info` and its `associated_pids`; no OS shell command is involved. [`netstat2` documents its low-level OS API approach and PID field](https://docs.rs/netstat2/latest/netstat2/).
- `collector/process_info.rs` owns one `sysinfo::System`, but refreshes only PIDs found in socket rows. It already handles the two-sample CPU warm-up for these PIDs. `ProcessInfo` currently carries `cpu_percent`, `memory_bytes`, and *all command arguments*.
- `refresh/coordinator.rs` is `netstat2 → PID association → sysinfo → SocketSnapshot`; a socket error prevents any process update. `app_state.rs` caches one `SocketSnapshot`. `refresh_now` is a synchronous Tauri command and the background timer emits `snapshot` or `snapshot-error`.
- `src/lib/render-state.svelte.ts` owns one socket-oriented render state. `src/routes/+page.svelte` has a selected-socket process inspector, but no independent all-process list.

The existing `docs/process-metrics-plan.md` is for v0.1, *socket-associated* process metrics. It is not evidence that the all-process feature is present.

## Why these data sources

| Candidate | Decision and reason |
| --- | --- |
| Spawn `/usr/bin/top` | Reject for the live feed. It is human-formatted output with mode/field choices and a deliberately invalid first `%CPU` sample; parsing it adds a subprocess lifecycle and locale/format dependency without giving us a stable process identity or a clean socket join. The installed macOS `man top` says default CPU is calculated between samples, its first displayed sample is invalid, and its `mem` field is *physical memory footprint*. `top` remains a manual comparison tool. |
| Existing `sysinfo 0.39.6` | Choose for the inventory and CPU/RSS/status. `System::refresh_processes_specifics(ProcessesToUpdate::All, true, kind)` refreshes all visible processes and removes exited records; retain the same `System` for CPU deltas. Use `ProcessRefreshKind::nothing().with_cpu().with_memory()` rather than `refresh_all()`. [System API](https://docs.rs/sysinfo/latest/sysinfo/struct.System.html), [performance guidance](https://docs.rs/crate/sysinfo/latest/source/README.md). |
| Existing `netstat2 0.11.2` | Retain for IPv4/IPv6, TCP/UDP, endpoints, and associated PIDs. It does not provide CPU, RSS, or commands. [Crate API](https://docs.rs/netstat2/latest/netstat2/). |
| `libc` macOS adapter | Chosen after a focused spike. `libc::proc_pidinfo(PROC_PIDTBSDINFO)` reads `proc_bsdinfo.pbi_start_tvsec`/`pbi_start_tvusec`; the current PID's seconds matched `sysinfo::Process::start_time()` on this Mac. The adapter does not replace the full `sysinfo` sampler. The struct fields come from [Darwin/XNU](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info.h). Restricted PIDs may return no token. |
| Native physical-footprint API | Defer. `libproc` exposes `ri_phys_footprint`, but this is a **different product metric** from RSS. Only add it through a separate feature decision, with permissions and performance tested. [RUsageInfoV4 fields](https://docs.rs/libproc/latest/libproc/pid_rusage/struct.RUsageInfoV4.html). |

The crate documentation explicitly states that per-process `cpu_usage()` may exceed 100% on multicore machines and requires two refreshes separated by at least `MINIMUM_CPU_UPDATE_INTERVAL`. `memory()` is resident-set bytes, not `top mem`/physical footprint. [`Process` API](https://docs.rs/sysinfo/latest/sysinfo/struct.Process.html), [minimum CPU interval](https://docs.rs/sysinfo/latest/sysinfo/constant.MINIMUM_CPU_UPDATE_INTERVAL.html). Apple distinguishes resident size from footprint in its [memory analysis guidance](https://developer.apple.com/documentation/xcode/analyzing-the-memory-usage-of-your-metal-app).

## State ownership and data contracts

```text
                         ┌─ ProcessSampler (persistent System) ─ ProcessSnapshot ─┐
shared settings/tick ────┤                                             Tauri events ├─ Svelte views
                         └─ SocketCollector (netstat2) ──────── SocketSnapshot ────┘
                                      ↑ PID + verified start token join ↑
```

Rust owns observed facts and their freshness; Svelte owns only presentation state: active view, per-view query/filter/sort, selected `ProcessKey`, and open/closed detail. No database or retained history is required. The app state caches the latest *successful* process and socket snapshots separately, plus each source's last error and capture time. The scheduler triggers sampling; manual requests coalesce into at most one queued follow-up and never start overlapping collectors. Pause stops automatic sampling, not navigation through the last snapshot.

Implemented wire contracts (Rust uses `snake_case`; Tauri serialization uses `camelCase`):

```rust
struct ProcessKey { pid: u32, start_sec: u64, start_usec: Option<u64> }
struct ProcessEntry {
    key: ProcessKey,
    name: String,
    cpu_percent: Option<f32>,
    rss_bytes: Option<u64>,
    status: ProcessState,
    parent_pid: Option<u32>,
}
struct ProcessSnapshot { generation: u64, captured_at: DateTime<Utc>, entries: Vec<ProcessEntry> }
struct ProcessDetail { key: ProcessKey, command: Option<Vec<String>>, exe: Option<String> }
```

`cpu_percent: None` means a first/too-close sample or unavailable result; it is not zero. `rss_bytes: None` means no trustworthy value was returned; if the OS API returns a real zero, show `0 B`. Because `sysinfo::memory()` itself is a `u64` without a per-field availability flag, the initial adapter can only assert availability when it successfully resolves a process; a spike must test whether restricted processes appear with synthetic zeroes on supported macOS versions. Do not claim perfect per-field permission detection without that evidence.

`ProcessKey` is a *process instance*, not PID alone. `sysinfo::Process::start_time()` is only epoch **seconds**, so `(pid, start_time)` alone does not meet the product's no-silent-PID-reuse rule. The macOS adapter should enrich visible rows with the BSD start microseconds and re-check it on detail requests and socket drill-down. If that token cannot be obtained, the row can remain in the inventory, but identity-sensitive detail/drill-down must either use a verified alternative or display `Identity unavailable` and not open a possibly different process. Cross-API sampling is not atomic; read identity before/after a socket scan for attributed PIDs and discard a join if it changed. Even with this check, test the remaining short-lived-process race rather than claiming kernel-atomic accuracy. [`sysinfo` start time granularity](https://docs.rs/sysinfo/latest/sysinfo/struct.Process.html), [Darwin start fields](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info.h).

For sockets, keep the socket's raw PID and endpoint independent of process metadata. Attach a verified `ProcessKey` only when identity checks agree. Socket count is the number of normalized socket rows whose verified key equals the process key; a socket associated with multiple PIDs may count once for each attributed process, consistent with the current per-PID normalization. This is *not* a unique kernel socket or throughput count. If the socket collector fails, counts become unavailable/stale rather than zero. If a socket has no PID or no verified process key, preserve the socket row and show unknown ownership.

## Sampling, detail, and event lifecycle

1. On launch, register Tauri listeners, request both cached snapshots, then start or reconcile the first refresh. The UI shows `Reading processes…` until the first process result. A generation counter per stream lets the UI ignore a late initial command result after a newer event.
2. One persistent `System::new()` in `ProcessInfoCollector` calls `refresh_processes_specifics(ProcessesToUpdate::All, true, ProcessRefreshKind::nothing().with_cpu().with_memory())` on a blocking worker. It records monotonic `Instant` and process start token to decide whether CPU is ready. The product's 2-second default exceeds the crate's minimum interval; the existing 1/2/5-second choices remain. `ProcessStatus::Run` maps to Running; Sleep to Sleeping; other statuses map explicitly to Stopped, Zombie, or Unknown. [ProcessStatus variants](https://docs.rs/sysinfo/latest/sysinfo/enum.ProcessStatus.html).
3. On the same tick, the socket collector runs after the process sampler in one non-overlapping blocking refresh. The results and last-good caches are independent; concurrent workers were unnecessary for the current scan cost. Emit `process-snapshot`/`process-error` and `snapshot`/`snapshot-error` with generations. Errors must not overwrite the other source's good snapshot. Tauri events are JSON and asynchronous, not a durable ordered log; use generations and an initial state command. [Tauri commands/events and listener cleanup](https://v2.tauri.app/develop/calling-rust/), [managed state guidance](https://v2.tauri.app/develop/state-management/).
4. On selection, request `get_process_detail(ProcessKey)` from a blocking command. Re-check the process instance before and after fetching command/executable using a *targeted* refresh or macOS process API; reject if it exited or changed. Do not include all commands in the periodic `ProcessSnapshot`. The existing socket inspector should use this same detail command rather than the v0.1 `SocketSnapshot.processes` command payload. Preserve argv boundaries; stringify for display with correct escaping, not an irreversible join. `Process::cmd()` returns OS strings and may be empty. [Process command API](https://docs.rs/sysinfo/latest/sysinfo/struct.Process.html).
5. If a selected process disappears in a later generation, keep its pane but mark `Exited or changed`; do not follow a same-PID replacement. When opening sockets, validate the selected key against the newest eligible socket snapshot. Revalidate when socket data refreshes. A filter by PID alone is insufficient.

Manual refresh is an async request to the same scheduler, not a second collector path. The scheduler awaits one blocking cycle at a time; repeated manual requests coalesce to one follow-up. It emits a completion generation and each source result after updating the independent caches. A slow cycle delays the next timer interval instead of overlapping it.

## Module boundaries

| Boundary | Responsibility |
| --- | --- |
| `src-tauri/src/collector/process_info.rs` | Persistent `sysinfo::System`, all-process CPU/RSS/status sampling, warm-up and exited-PID pruning. |
| `src-tauri/src/collector/macos_identity.rs` | Narrow Darwin start-token read/check, isolated from `sysinfo`; feature-gated to macOS if the crate requires it. |
| `src-tauri/src/model/process.rs` + `snapshot.rs` | `ProcessKey`, lightweight entry/snapshot/detail types and explicit availability. Replace v0.1 socket-only process payload, do not maintain two canonical inventories. |
| `src-tauri/src/refresh/coordinator.rs` + `app_state.rs` | Two independent sample results, non-overlap, cache/generation/error ownership, shared interval/pause settings. Keep `netstat2` collector untouched except any required identity join. |
| `src-tauri/src/commands/processes.rs` + `sockets.rs` | Identity-checked detail; cached monitor state and coalesced manual refresh request. |
| `src/lib/render-state.svelte.ts` | Derived process filters/sort/counts, source-specific loading/stale/error, and fixture for browser preview. No authoritative CPU/RSS facts computed in the UI. |
| `src/routes/+page.svelte` | Render Sockets/Processes navigation, table, detail, command availability, socket drill-down. Keep the 760×520 shell and existing socket controls. |

The exact split of `refresh/coordinator.rs` may be adjusted to keep the change small. The non-negotiable boundary is **two independently valid snapshots**; there is no need for a database, plugin, service daemon, or new IPC transport just to ship this feature.

## Failure, privacy, and distribution gates

- **Process failure:** retain last valid process inventory, mark its capture time stale, surface retry; socket view continues. **Socket failure:** retain last valid socket snapshot, mark socket counts/drill-down stale or unavailable; process CPU/RSS continues. An initial failure has no “zero processes/sockets” fallback.
- **Permissions and packaging:** a returned process may lack command/path, and some processes may not be enumerated. Display missing data explicitly. No root escalation or privileged helper is in scope. The Mac App Store path is excluded by product decision, so its mandatory App Sandbox is no longer a release blocker. Do not infer that any non-App-Store bundle is automatically unsandboxed: inspect its actual entitlements and test the final packaged app. The package's own docs warn that a macOS App Store build cannot retrieve this process information. [sysinfo warning](https://docs.rs/sysinfo/latest/sysinfo/struct.Process.html), [Apple sandbox rule](https://developer.apple.com/documentation/Xcode/preparing-your-app-for-distribution).
- **Sensitive data:** command arguments can contain secrets. The periodic list event excludes command/exe. The detail command returns them only after selection; do not send them to tracing, analytics, crash reports, local persistence, or browser fixtures. Consider UI copy affordance only as an explicit user action. Clear detail data when pane closes or process identity changes.
- **Metric honesty:** do not call RSS “top MEM.” The local `man top` defines `mem` as physical footprint and says first `%CPU` sample is invalid; the crate defines `memory()` as resident set. Do not clamp CPU to 100% or substitute zero while sampling. No per-process network bandwidth is inferred from socket presence.

## Validation before calling this shippable

1. **Focused macOS API spike:** on supported macOS/Apple Silicon and Intel if available, confirm all-process enumeration, `libc`/`proc_pidinfo` start-token read for normal/system processes, command/path availability, and PID exit/reuse handling. Then repeat against the actual non-App-Store bundled app and inspect its entitlements/signing; development-mode success alone is insufficient. Record inaccessible cases; do not silently weaken the product promise.
2. **Sampling tests:** fake process source for first sample, too-close second sample, spaced sample, multi-core CPU >100%, PID reuse, dead process removal, status mapping, and unknown RSS/command. Add identity-join tests for before/after mismatch and unavailable token.
3. **Two-source tests:** process success + socket failure, socket success + process failure, stale counts, late initial command vs newer event, manual refresh vs timer, pause/resume, and overrun coalescing. Existing socket normalization tests must still pass.
4. **Performance measurement:** measure first scan and p50/p95/p99 steady-state scan duration, app CPU/RSS, event payload size, and detail fetch latency at 1/2/5-second intervals with realistic process counts. The 2-second default is an **unmeasured proposal**, not a throughput claim. If excessive, first avoid repeated command/path reads and unnecessary refresh kinds; compare `sysinfo` feature settings only from current-version source and actual measurements. [sysinfo performance guidance](https://docs.rs/crate/sysinfo/latest/source/README.md).
5. **Acceptance:** `cargo fmt --check`, focused Rust tests, `cargo test --manifest-path src-tauri/Cargo.toml`, `pnpm check`, `pnpm build`, and a signed/native macOS run. Browser preview proves only fixture rendering, not OS data access. Verify the three Figma app views and operational-state reference at 760×520, keyboard focus/scroll, and selected process continuity while snapshots update.

## Implementation record — 2026-09-24

The macOS spike confirmed that `libc::proc_pidinfo(PROC_PIDTBSDINFO)` returns this process's high-resolution start time and that `sysinfo` enumerates multiple processes. The implemented collector now scans all visible processes every tick, obtains CPU/RSS/status with a persistent `System`, checks identity before attaching process metadata to a socket, and fetches command/executable only through an identity-checked detail command. The app state stores process and socket last-good snapshots and errors separately. The UI adds the Figma-derived Processes list, detail, and scoped-socket flow while keeping Sockets as the launch view. Local Figma assets and existing CSS conventions were reused; no Tailwind or `top` subprocess was added.

Current verification: Rust tests (including a real process+socket refresh on this Mac), `pnpm check`, and `pnpm build` pass. Browser fixture checks covered the 760×520 list/detail/scoped views, search, zero-socket process visibility, and sidebar filtering. A separate unsigned debug `.app` also passed a live native smoke test: hundreds of processes appeared, CPU/RSS/status refreshed, on-demand command/executable detail returned for a selected process, and scoped sockets matched its PID/start token. This does **not** prove a signed/notarized distribution bundle has the same access. The final outside-store packaging channel, signing/entitlements, signed-bundle access, Intel behavior, systematic permission-gap survey, failure injection, and p95/p99 performance measurements remain release gates.

Do not add `/usr/bin/top`, root privileges, a helper, or process-control actions to close those validation gaps. The next concrete step is to choose the outside-store distribution channel and test the correspondingly signed bundle with its final entitlements.
