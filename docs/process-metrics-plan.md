# Process metrics (macOS v0.1)

## Goal and boundary

For a selected socket row, show the owning PID's CPU percentage, resident memory, and command line. Keep socket facts in `SocketEntry`; carry one `ProcessInfo` per PID in `SocketSnapshot`. Preserve the current `netstat2` collector and Tauri event path. Do not execute `top` or persist command lines.

## Data and lifecycle

- Refresh only socket-associated PIDs with `sysinfo` CPU, memory, command, and executable fields.
- Reuse the existing `System` across refreshes. Mark CPU unavailable until the same process has been sampled twice at least `MINIMUM_CPU_UPDATE_INTERVAL` apart; a new process with a reused PID starts a new sample.
- Return current process records with each snapshot. Missing process information stays missing; an empty command is shown as unavailable.
- Selecting a socket row opens a compact process inspector below the table. Keep the 760×520 table columns unchanged; search includes the command line.

## Acceptance

- Rust tests cover PID-to-process normalization and CPU sample readiness; existing collector tests pass.
- `pnpm check`, `pnpm build`, and `cargo test` pass.
- Native macOS check shows CPU, resident memory, and command for a visible PID, and a clear unavailable state for restricted or exited processes.
