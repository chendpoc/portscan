# PortMaster v0.3 — Local port ownership investigation

Status: discovery-derived product requirements, 2026-09-24

## Product conclusion

The strongest validated job for the interviewed segment is not general process monitoring. It is:

> When a local development service fails with a port collision, identify the responsible process and the project context quickly enough to stop the correct process with confidence.

The existing process/socket views are a good foundation, but the current prototype is still centered on process inventory. The next product slice should make **port-to-process-to-project identification** the primary path.

## Interview scope and evidence quality

- One simulated customer segment: Mac developers who diagnose local process and port problems.
- One stable persona: a Mac developer.
- Ten rounds were completed with the `gpt-6-luna` subagent at `max` reasoning.
- This is directional discovery evidence, not statistically validated market research.
- The main incident was a local API failing with `EADDRINUSE` on `127.0.0.1:8787`; a leftover Node process from another repository owned the port.

## Observed user facts

| Evidence | Product implication |
| --- | --- |
| Port collisions happen a couple of times per month when switching projects. | The problem is recurring, but not an always-open dashboard need. Fast incident entry matters more than broad monitoring depth. |
| Simple cases take a few minutes; ambiguous generic Node processes take 10–15 minutes. | The target metric is time-to-confident-identification, not time-to-render a process list. |
| Current workflow is `lsof` → `ps` → another `lsof` for working directory → switch terminals → stop the right server → health-check the API. | PortMaster should collapse evidence gathering and preserve an explicit user-controlled handoff to the existing terminal/workflow. |
| The user needs to distinguish multiple similar Node processes and identify the owning repository. | PID, command, executable, working directory/project context, and collection time are more important than CPU/RSS for this job. |
| A stale observation or PID reuse could cause the wrong process to be targeted. | Freshness and process-instance identity are trust requirements, not secondary metadata. |
| The user will not trust a blank or zero value when the field is unavailable. | The UI must distinguish zero, unknown, restricted, and stale values. |
| The user explicitly does not want the product to terminate processes. | No kill/stop action in this product slice. Keep the user in control. |

## Problem statement

PortMaster can show a socket and its PID, and it can show process identity fields on demand. However, a generic command such as `node server.js` may still leave the user unable to tell which repository owns the listener. The current flow also risks making an old observation look actionable unless freshness and process-instance identity are visible at the decision point.

## v0.3 goals

1. Make a searched local port the fastest entry point into the responsible process.
2. Show enough project/process identity to distinguish similar processes without terminal hopping.
3. Make observation freshness and identity validity visible before the user acts.
4. Preserve the local-only, read-only, non-destructive boundary.

## Proposed user flow

```text
EADDRINUSE / port number
        ↓
Search or focus port 8787 in Sockets
        ↓
See listener + PID + process identity + project context + captured-at time
        ↓
Open process details and verify instance is still the same
        ↓
User decides what to do in Terminal or another workflow
        ↓
User retries service and verifies its health check
```

## Functional requirements

### P0 — Port-first investigation

- The Sockets view must support direct search by local port, with an obvious result for an exact port such as `8787`.
- A socket row must expose, without requiring multiple unrelated views, the local address, local port, protocol/state, PID, process name, and observation time.
- Selecting the socket must open the owning process detail for the same verified process instance.
- If a port has multiple listeners or protocol/address variants, show them as separate rows; do not silently merge them.

Acceptance:

- Starting from a port number, a user can reach its owning process detail in at most two deliberate selections.
- The selected detail cannot silently follow a different process that reuses the same PID.

### P0 — Project/process identity

- Process detail must show, when available: full launch command, executable path, working directory, PID, process start identity, and the socket(s) attributed to that process.
- Working directory must be a first-class field, not hidden only in a raw command or tooltip.
- If working directory/project context cannot be read, show an explicit `Unavailable from macOS` or permission-specific state.
- Do not infer a repository name from a process name or command when the path is unavailable.

Acceptance:

- For two generic Node processes, the user can distinguish them when their working directories differ.
- When the working directory is unavailable, the UI clearly states that the product cannot establish project ownership.

### P0 — Freshness and identity trust

- Show the collection timestamp for the socket and process facts used in the detail view.
- Show a clear stale/refreshing state when the latest collection failed or is older than the configured freshness threshold.
- Preserve the last valid data during refresh, but never present it as live/current.
- Bind selection and socket drill-down to a process instance identity, not PID alone.
- Before presenting an identity-sensitive action or drill-down, re-check that the process instance is still the same; otherwise show `Process exited or changed`.

Acceptance:

- A user can answer “when was this observed?” without opening a log or terminal.
- A failed refresh does not turn a known socket/process into zero or silently redirect selection.

### P1 — Investigation-oriented presentation

- Add a compact “Investigate port” affordance or equivalent focused state that makes the port-first workflow discoverable.
- Keep search/filter/sort choices stable while moving between Sockets and Processes.
- Make command/path text selectable and copyable as an explicit user action.
- Keep CPU and RSS available in process detail, but do not let them dominate the port-investigation path.

Acceptance:

- In a 760×520 window, the port, PID, process/project identity, freshness, and state remain legible without horizontal overflow.

### P1 — Read-only handoff

- Do not add process termination, restart, or automatic remediation in v0.3.
- Provide enough copyable identity to let the user act in Terminal or their existing workflow.
- Do not persist or upload command lines, working directories, or process history by default.

## Explicit non-goals

- Terminating or controlling processes.
- Historical process/socket timelines.
- Network throughput measurement.
- Multi-host monitoring.
- Repository introspection, Git status, or automatic project-name resolution beyond OS-visible process context.
- Replacing the user's final health check.
- Turning PortMaster into a general security or endpoint-management product.

## Risks and unresolved questions

1. **Working-directory availability:** the interview identified it as the key missing discriminator, but the current macOS collector may not always be allowed to read it. The product must validate platform/permission coverage before promising “project ownership.”
2. **Freshness threshold:** the user needs to know that data is current, but the interview did not establish a universal acceptable age. Start with the existing refresh interval and show the exact timestamp; validate thresholds with real incidents.
3. **Multiple listeners:** the interview covered one port collision. The design still needs a clear rule for IPv4/IPv6, TCP/UDP, and multiple processes associated with one observed socket.
4. **Outcome validation:** the simulated user expects under one minute from `EADDRINUSE` to confident identification. This must be tested with real developers and real ambiguous Node/process setups.

## Success metrics for a prototype test

- Median time from seeing a port-collision error to identifying the responsible process and project context: under 60 seconds.
- At least 90% of test tasks completed without switching to Terminal to discover the owning process.
- Zero silent PID-reuse or stale-selection misidentifications in adversarial tests.
- Users can correctly distinguish two same-name processes in a majority of test cases when working directories are available.
- Users do not interpret unavailable, stale, or restricted fields as zero/empty values.

## Next concrete action

Build a narrow clickable prototype around one task: enter/search `8787`, inspect the listener, verify project context and capture time, and return to the process/socket relationship. Before implementation, test whether macOS reliably exposes the working directory for the target process set; if not, downgrade “project context” from a guaranteed requirement to an explicitly unavailable evidence state.
