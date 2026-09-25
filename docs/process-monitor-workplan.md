# Process monitor discovery and design plan (2026-09-23)

## Deliverables and source of truth

1. An additive, editable process-monitor prototype in the existing PortScan Figma file (`vgxBW2cNDE1oVVyESnM1lM`); preserve the v0.1 screens.
2. A feature-only specification under `docs/product/` based on the prototype and the user's clarified goal: a `top`-like live view of all macOS processes, linked to sockets where available.
3. An evidence-backed implementation design under `docs/tech/` derived from that product specification and the current Rust/Tauri/Svelte checkout.

Priority for product decisions: latest user request > current app behavior > older Figma mock. The existing file supplies the Geist typography, 760×520 utility-window proportions, and table/sidebar language. The current app's white, full-window surface supersedes the older purple presentation backdrop.

## Scope and non-goals

- Prototype the all-process list, CPU/memory sorting, selection and detail, refresh/paused/error/limited-data states, and a link back to sockets.
- Specify observable metrics and interactions; keep OS APIs, crates, IPC, schema, and module design out of the product document.
- Research sampling, macOS metric semantics and restrictions, performance, privacy, process identity, lifecycle, and testability in the technical document.
- Do not implement application code, invoke `top` as the production data path, add process termination, fabricate network throughput, or imply historical charts exist in v0.2.

## Acceptance and sequence

1. Inspect live checkout and Figma structure/assets; record the no-local-design-system finding and any conflicts.
2. Add Figma screens without modifying earlier screens; inspect screenshots for legibility and hierarchy, and record node links.
3. Write the product spec with user problem, scope, interaction/state rules, metric labels, non-goals, and acceptance criteria. Review it for implementation leakage.
4. Research authoritative documentation and write the technical design with alternatives, chosen architecture, failure semantics, performance and privacy constraints, testing, and source links.
5. Verify files and links, report what is designed versus implemented.

Key risk: `top`'s `MEM` physical footprint and `sysinfo` resident memory are not interchangeable. The prototype and product spec must label the chosen metric explicitly. Another risk is command-line privacy; commands can contain secrets, so the feature must avoid automatic persistence/export.

## Completion record (2026-09-23)

- Figma screens added and visually inspected at 760×520: `28:2` all processes, `33:2` detail, `38:4` process-scoped sockets. Navigation edges were read back from Figma. `45:2` is the operational-state reference sheet. Earlier v0.1 screens remain present.
- Feature behavior and acceptance live in `docs/product/live-process-monitor-v0.2.md`; implementation architecture, source research, risks, and validation plan live in `docs/tech/live-process-monitor-v0.2.md`.
- No application code or dependencies were changed by this design task. Native performance, permissions, and signed-build acceptance remain implementation-phase work.
- Distribution decision after documentation: the user explicitly ruled out the Mac App Store. The product and technical specifications record outside-store distribution; final bundle entitlements and native data access still require verification.
