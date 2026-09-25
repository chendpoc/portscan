# Live Process Monitor — v0.2 feature specification

Status: product contract, updated 2026-09-24. The feature is implemented in the current working tree and has passed an unsigned debug-app smoke test; signed distribution remains unverified. The figures and process names in the prototype are illustrative. Distribution is outside the Mac App Store.

## Outcome and audience

PortMaster currently starts from open sockets. A user investigating a slow Mac also needs to see *every running process*, including those with no socket, to answer: “Which process is consuming CPU or memory, what command started it, and does it own any network sockets?” The new Processes view is a live, local process inventory alongside the existing Sockets view. It is not a terminal `top` clone.

The primary user is a developer or technically curious Mac user diagnosing resource use and local port ownership. The first useful outcome is locating a costly process, inspecting its identity and launch command, then reaching its sockets in one action.

## Prototype and navigation

The additive Figma flow keeps the existing socket designs intact:

1. [All Processes](https://www.figma.com/design/vgxBW2cNDE1oVVyESnM1lM/PortScan-%E2%80%94-Product-Prototype-v0.1?node-id=28-2): the default CPU-sorted inventory.
2. [Process Detail](https://www.figma.com/design/vgxBW2cNDE1oVVyESnM1lM/PortScan-%E2%80%94-Product-Prototype-v0.1?node-id=33-2): selected process, command, and metrics.
3. [Sockets for Process](https://www.figma.com/design/vgxBW2cNDE1oVVyESnM1lM/PortScan-%E2%80%94-Product-Prototype-v0.1?node-id=38-4): socket view scoped to that process.
4. [Operational States](https://www.figma.com/design/vgxBW2cNDE1oVVyESnM1lM/PortScan-%E2%80%94-Product-Prototype-v0.1?node-id=45-2): sampling, paused, partial-access, and process-error treatments (a reference sheet, not another app view).

The intended click path is list row → detail → “View N sockets” → scoped socket list → Processes. The existing Sockets view remains the launch view; the Processes tab opens the new inventory. Each view keeps its own search/filter/sort choice when switching, while both share the refresh interval and pause setting. The product surface is a 760×520 resizable macOS utility window with a plain white application background, not a purple canvas.

## v0.2 feature behavior

| Area | User-visible contract |
| --- | --- |
| Inventory | Show all processes visible to the current macOS user, not only socket-owning processes. A process with zero sockets remains in the list. If macOS prevents seeing some system processes, do not imply the list is complete. |
| Columns | `PID`, `Process`, `CPU`, `RSS`, `Status`, `Sockets`. Keep the primary list compact; the command is in detail. |
| Default order | Highest available CPU first. Rows with CPU still sampling or unavailable follow rows with known CPU; ties use PID for stable ordering. Column headings for CPU, RSS, and PID allow ascending/descending sort. Live updates must not change the user's selected sort. |
| Search | Case-insensitive substring search over process name and PID. Search narrows the current view; it does not change the underlying counts. The full command is inspectable but not indexed by the list search in this version. |
| Sidebar | `All Processes`, `Running`, `With Sockets`; each count reflects the latest process inventory and current socket attribution, before search text is applied. `Running` uses the reported process state, not “CPU > 0.” `With Sockets` means one or more currently attributed socket rows. |
| Selection | Clicking a process row opens a detail pane without leaving the inventory. It shows name, PID, status, start time when available, CPU, RSS, socket count, full launch command, parent PID, and executable path when available. Long command/path content remains selectable and readable without widening the main table. |
| Socket drill-down | “View N sockets” opens the existing socket view filtered to the selected process. If N is zero, show a disabled or explanatory empty action. The socket view identifies its process filter and can return to Processes. |
| Refresh | Initial load then live refresh, default every 2 seconds. Manual refresh keeps the last valid display while new data arrives. The existing 1/2/5-second interval choices and pause/resume remain available in compact settings. Switching views does not silently pause the other inventory. |

### Metric and label meanings

- `CPU` is the process's recent CPU usage, not its lifetime average. More than 100% is valid on a multicore Mac. On first sight or immediately after a process restarts, show `Sampling…` until a meaningful interval has elapsed; never display an invented `0.0%`.
- `RSS` is resident memory attributed to the process, presented in compact byte units. Label it **RSS**, not `top MEM`, “physical footprint,” or total Mac memory pressure. These are different measures.
- `Sockets` counts the currently observed socket rows attributed to that process. It is not network throughput or a count of remote peers. Because visibility and socket attribution can be limited, show `—` with an explanation when the socket inventory is unavailable instead of treating an error as zero.
- `Status` uses plain-language values such as Running and Sleeping; unknown or inaccessible status is `Unknown`. A process can be present while using 0% CPU or owning no sockets.
- `Command` means the OS-provided launch arguments. If unavailable, say `Unavailable from macOS`; never substitute the process name as if it were the full command.

## State and failure rules

| State | Display rule |
| --- | --- |
| First load | Keep the layout visible and show `Reading processes…`. CPU cells may subsequently show `Sampling…` until a second reading. |
| Empty search/filter result | Show `No matching processes`; retain current counts and controls. An empty result is not an error. |
| Paused | Freeze the last successful values and show `Paused` plus the time of the last reading. Resume restarts live updates; CPU may briefly need a new sample. |
| Process collection error | Preserve the last successful process reading, mark it stale, and show a concise error/retry affordance. Do not show `0 processes` as if collection succeeded. |
| Socket collection error | Keep the process list usable. Mark socket counts and drill-down as unavailable or stale; do not convert them to zero. |
| Partial access | Keep a visible process even when its command, path, status, or metric is missing. Mark each missing field explicitly. Do not imply the application has elevated privileges. |
| Exited or replaced selected process | Keep the detail pane open with `Process exited or changed` until dismissed. Never silently attach the pane to a new process that happens to reuse the same PID. |

The app remains local-only for this feature. Commands can contain tokens, paths, and other sensitive values; they are shown only on demand in the detail pane and are not automatically logged, exported, uploaded, or retained as history. Copying a command is an explicit user action.

## Acceptance criteria

1. On macOS, a visible process with zero sockets appears in All Processes and not in With Sockets; a socket-owning process appears in both.
2. At the 760×520 default size, the list, sidebar, controls, detail, and state messages remain legible without unexpected horizontal overflow.
3. CPU descends by default, can exceed 100%, and starts as `Sampling…` rather than a false zero. RSS is labelled RSS everywhere.
4. Search, sidebar filters, sorting, pause/resume, interval selection, and manual refresh work without losing the last valid reading during a refresh.
5. Selecting a process exposes its command and available identity fields; drill-down shows only sockets attributed to that same still-running process. A reused PID cannot silently redirect the detail or socket filter.
6. Process and socket collection failures are independently visible and do not erase healthy data from the other view.
7. No command line is persisted, uploaded, or written to routine logs.

## Explicit non-goals

No process termination or control, historical charts, export, disk I/O, per-process network throughput, exact Activity Monitor/`top` physical-footprint parity, process tree, multi-host monitoring, or non-macOS support in v0.2. The Figma examples do not assert specific real process counts or resource values.
