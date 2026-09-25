# PortMaster professional-user interview plan

Status: completed — 10 rounds conducted on 2026-09-24

## Deliverable

One structured 10-round discovery interview with a single customer group, followed by a product-manager interpretation and a scoped feature-requirements document for the existing PortMaster prototype.

## Interview group

Developers, SREs, and IT support engineers who use macOS and need to diagnose local process/port/socket behavior during a network or resource incident.

This is one behavioral group for this interview: technically capable professionals responsible for explaining or fixing local machine behavior. It is not a combined interview of consumers, security analysts, or network administrators.

## Source of truth

- Product behavior: `docs/product/live-process-monitor-v0.2.md`
- Current implementation/prototype: the live checkout and its Svelte/Tauri UI
- User evidence: the 10-round transcript produced in this interview

## Acceptance criteria

- Exactly 10 rounds are recorded.
- Each round captures a concrete behavior, pain, workaround, consequence, and confidence/uncertainty where available.
- Observed pain is separated from requested solutions and product assumptions.
- The final PRD maps each requirement to interview evidence and to an existing PortMaster surface or an explicitly scoped new surface.
- Requirements preserve the prototype's local-only, non-destructive, privacy-sensitive boundary.

## Interview order

1. Role, context, and a recent concrete incident
2. Trigger and desired outcome
3. Current investigation workflow
4. Hardest ambiguity or failure point
5. Evidence and trust requirements
6. Cost of delay and severity
7. Existing tools and unacceptable workarounds
8. Reaction to the current PortMaster flow
9. Prioritization and trade-offs
10. Success criteria and unresolved concerns

## Non-goals

Do not design the complete roadmap, add unrelated user groups, promise implementation, or treat a simulated interview as statistically validated market research.

## Output

Requirements derived from this interview are recorded in `docs/product/portmaster-professional-user-prd-v0.3.md`.
