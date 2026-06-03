---
name: spec
description: Create specification documents without implementing code. Uses a two-tier model — a plain-language business spec (parent) plus one technical spec per vertical slice (child). Generates the parent + first slice on a new requirement, and the next slice when resumed on an existing feature.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(git *), Bash(glab *), Bash(gh *), Agent, AskUserQuestion, Skill
argument-hint: [feature-name or description]
---

# Specification Document Creator

Create a specification/design document for: $ARGUMENTS

## Critical Rules

- **NEVER** write, edit, or implement any code
- **NEVER** enter plan mode or start implementation
- Output is ONLY spec documents — nothing else
- If the user hasn't described the requirement clearly enough, ask clarifying questions before writing

## The Two-Tier Model

Every requirement — regardless of size — is captured as a **business spec** (parent) plus one or more **technical specs** (children), one per vertical slice. Leading with business intent before any mechanism is mandatory: it is the uniform thinking contract for this workflow.

- **Business spec (parent, `00-overview.md`)** — plain language. The "why" and "what": context, proposal, goals, business rules, and the slice map. No technical jargon. This is the doc the user lives in.
- **Technical spec (child, `NN-<slug>.md`)** — one per vertical slice. The "how": each opens with a `Serves` back-reference to the parent, then the mechanism.

A **vertical slice** is a thin, end-to-end, independently shippable increment of user-visible behavior ("user can create a draft"), NOT a horizontal layer ("the API layer"). One technical spec per slice.

**Generation flow:** on a *new* requirement, generate the parent + the **first slice only**. The parent's slice map lists the foreseen slices, but only the active slice gets a written technical spec. Later slices are written on subsequent `/spec` runs against the same feature folder (next-slice mode). This keeps batch size small — the user only ever holds one slice in their head.

**Scale depth, not presence.** A tiny requirement still gets a parent + a slice — but the parent can be a few lines (Context, one Goal, maybe one rule). Keep the structure; drop empty sections. Never skip the parent.

## Naming & Layout — Hard Rules

```
specs/<feature-slug>/
├── 00-overview.md      # business spec (parent / map) — always sorts first
├── 01-<slug>.md        # technical spec, slice 1
├── 02-<slug>.md        # technical spec, slice 2
└── ...
```

- **`<feature-slug>` and slice names are pure slugs:** lowercase, hyphen-separated, derived from the name (`User Draft Autosave` → `user-draft-autosave`).
- **NEVER** use SCREAMING_CASE, leading underscores, or a `spec-` prefix in any spec file or folder name.
- Parent is always `00-overview.md` (the `00` prefix keeps the map sorted above the slices).
- Slices are zero-padded numeric prefix + slug: `01-intake.md`, `02-async-processing.md`.

## Instructions

### Step 1: Understand Context

1. Read the project's `CLAUDE.md` for conventions.
2. Explore the relevant parts of the **codebase** to ground the spec — current architecture, impacted modules, services, dependencies.
3. **Do NOT read other spec files to copy their structure.** The templates in this skill are canonical; an existing spec must never override them. The only permitted spec-folder lookup is the existence check in Step 2.

### Step 2: New Feature or Next Slice?

Slugify the requirement name and check whether `specs/<feature-slug>/` already exists (Glob/Bash). This is an existence check only — not a structure read.

- **Folder does not exist** → this is a new feature. Scaffold the folder and write `00-overview.md` + the first slice. Continue to Step 3.
- **Folder exists** → you are adding the next slice to an existing feature. Read its `00-overview.md`, then skip to Step 5.
- **Ambiguous** (the description could match an existing folder, or several): use AskUserQuestion to confirm whether this is a new feature or which existing one, before proceeding.

### Step 3: Define the Business Spec (new feature only)

Ask clarifying questions until the business intent is clear — problem, desired outcomes, goals, the rules that must always hold. Use AskUserQuestion for anything unclear. Then write `00-overview.md` using the **Business Spec** template below.

Keep it in business language. A technical concern may appear in `## Technical Constraints` **only if it is business-visible** — it changes cost, risk, compliance, or user-facing behavior (e.g. rate limiting, infra provisioning, a compliance control). Name the concern and why it matters; the mechanism stays in the slice. Implementation choices (libraries, patterns) never appear in the parent.

### Step 4: Decompose into Slices (new feature only)

Break the requirement into vertical slices. List them all in the parent's `## Slices` map as a checklist (the high-level shape), but mark only slice `01` as the one being written now. The map can be refined on later runs.

### Step 5: Pick the Active Slice

- New feature: the active slice is `01`.
- Existing feature: choose the next unwritten slice from the parent's map (or define one with the user if the map is exhausted), using the next free numeric prefix.

### Step 6: Detect the Slice's Technical Type

A technical spec (child) is type-specific. Infer the type from the slice, then **confirm with the user** via AskUserQuestion (_"Detected slice type: **[type]**. Is this correct?"_):

| Type               | Signals                                                                                          |
|--------------------|--------------------------------------------------------------------------------------------------|
| **Feature**        | "add", "new", "implement", "support for", user-facing functionality                              |
| **Bug/Fix**        | "bug", "broken", "error", "doesn't work", "fix", "regression", issue references                  |
| **Refactor**       | "refactor", "restructure", "migrate", "clean up", "decouple", "extract", pattern changes         |
| **Integration**    | "integrate", "connect", external service names (Keycloak, Twilio, Stripe, etc.), API consumption |
| **Infrastructure** | "pipeline", "CI/CD", "deploy", "Docker", "GCP", "infra", "monitoring", environment changes       |

### Step 7: Ask Clarifying Questions (slice scope)

Before writing the slice, ensure the scope is clear. Questions vary by type:

- **Feature:** Scope boundaries, target users, integration points, constraints
- **Bug:** How to reproduce, affected environments, severity, since when
- **Refactor:** What's wrong with current approach, constraints on migration, backward compatibility
- **Integration:** Which service, auth method, environments, rate limits
- **Infrastructure:** Affected environments, rollback needs, downtime tolerance

### Step 8: Write the Slice's Technical Spec

Write `NN-<slug>.md` using the matching child template below. Every child opens with `## Serves`.

---

## Metadata Block

Every spec — parent and child — MUST start with this block immediately under the H1 title. Use `<br>` between bold lines per global Markdown rules. `Date` is today's date (ISO). `Status` is one of: `Draft`, `In Review`, `Approved`, `In Progress`, `Done`, `Blocked`. `Author` is `Frank`.

```markdown
**Date:** YYYY-MM-DD<br>
**Status:** Draft<br>
**Author:** Frank
```

---

## Parent Template — Business Spec (`00-overview.md`)

```markdown
# [Feature Name] — Business Spec

**Date:** YYYY-MM-DD<br>
**Status:** Draft<br>
**Author:** Frank

## Context
The problem today; why this matters now. Plain language, no jargon.

## Proposal
What we're building, stated as outcomes — not "how".

## Goals & Success Criteria
Business-visible and measurable. Numbered so slices can reference them.
- G1: ...
- G2: ...

## Business Rules & Invariants
What must always be true. Numbered for reference. State the rule, not the mechanism.
- BR1: A user can never ...
- BR2: When ..., the system must ...

## Technical Constraints (flagged)
Business-visible concerns only (cost, risk, compliance, user-facing behavior). Name + why — the mechanism lives in the slice spec. Omit this section if there are none.

| Constraint    | Why it matters              | Slice          |
|---------------|-----------------------------|----------------|
| Rate limiting | Prevent abuse / cost blowup | `01-intake.md` |

## Slices
The map — high-level decomposition. Only the active slice has a written technical spec; the rest are placeholders until reached.
- [ ] 01 — <slice name> → `01-<slug>.md`
- [ ] 02 — <slice name> → `02-<slug>.md` (not yet written)

## Out of Scope
What is explicitly NOT part of this requirement.

## Open Questions
Unresolved decisions or items needing clarification.
```

---

## Child Templates — Technical Spec (`NN-<slug>.md`)

Every child starts with the metadata block and a `## Serves` section. `Serves` references the parent's goals/rules/constraints by ID — this lives **inside `specs/` only and must never leak to code, comments, or commits** (per the global spec-hygiene rule). The parent owns all business framing; the child stays technical.

```markdown
## Serves
- Goals: G1, G2
- Rules: BR1
- Constraint: Rate limiting
```

### Feature Slice

```markdown
# [Feature Name] — Slice NN: [slice name]

**Date:** YYYY-MM-DD<br>
**Status:** Draft<br>
**Author:** Frank

## Serves
- Goals: ...
- Rules: ...
- Constraint: ... (omit if none)

## Technical Design

### Architecture
How this slice integrates with the existing system.

### Data Model Changes
Database/schema changes if applicable.

### API Changes
New or modified endpoints/contracts.

### Dependencies
External services, libraries, or modules involved.

## Guardrail Enforcement
For each business-visible constraint this slice owns, how it is enforced (algorithm, limits, where applied). Omit if none.

## Validations & Edge Cases
Input validation, boundary conditions, failure modes.

## Implementation Steps
Ordered, incremental breakdown.
1. Step 1 — ...
2. Step 2 — ...

## Decisions & Tradeoffs
Key technical choices and why; alternatives discarded.

## QA Criteria
- [ ] Acceptance criteria checklist
- [ ] Edge cases to test

## Open Questions
Unresolved decisions or items needing clarification.
```

### Bug/Fix Slice

```markdown
# [Bug Title] — Slice NN: [slice name]

**Date:** YYYY-MM-DD<br>
**Status:** Draft<br>
**Author:** Frank

## Serves
- Goals: ...
- Rules: ...

## Problem Description
Clear description of the incorrect behavior.

## Reproduction Steps
1. Step 1
2. Step 2
3. Observe: [what happens]

## Expected vs Actual Behavior

|              | Description          |
|--------------|----------------------|
| **Expected** | What should happen   |
| **Actual**   | What happens instead |

## Affected Scope
- Environments: [dev/staging/prod]
- Users impacted: [scope]
- Since: [when it started, if known]
- Severity: [critical/high/medium/low]

## Root Cause Analysis
Trace the code path, identify the failing component, explain the underlying cause — not just symptoms.

## Proposed Fix
Detailed description of the solution approach.

### Risks & Side Effects
What else could break. Regression concerns.

### Alternative Approaches Considered
Other options evaluated and why they were discarded.

## QA Criteria
- [ ] Original bug no longer reproducible
- [ ] Regression tests for the fix
- [ ] Related flows still work correctly

## Open Questions
Unresolved decisions or items needing clarification.
```

### Refactor/Architecture Slice

```markdown
# [Refactor Name] — Slice NN: [slice name]

**Date:** YYYY-MM-DD<br>
**Status:** Draft<br>
**Author:** Frank

## Serves
- Goals: ...
- Rules: ...

## Motivation
Why the current architecture is insufficient. Concrete pain points, not theoretical.

## Current State
How things work today. Diagrams or code references where helpful.

### Problems with Current Approach
- Problem 1: ...
- Problem 2: ...

## Proposed Architecture
How things should work after this slice.

### Key Design Decisions
| Decision | Choice | Rationale |
|----------|--------|-----------|
| ...      | ...    | ...       |

### Component Changes
Which modules/services/layers change and how.

## Rollback Plan
Incremental steps, each with its revert.
1. Phase 1 — change … · Rollback: …
2. Phase 2 — change … · Rollback: …

### Backward Compatibility
What breaks, what stays compatible, how to handle the transition.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| ...  | ...        | ...    | ...        |

## QA Criteria
- [ ] Existing behavior preserved (no functional regressions)
- [ ] Performance not degraded
- [ ] New architecture validated with [specific test]

## Open Questions
Unresolved decisions or items needing clarification.
```

### Integration Slice

```markdown
# [Service Name] Integration — Slice NN: [slice name]

**Date:** YYYY-MM-DD<br>
**Status:** Draft<br>
**Author:** Frank

## Serves
- Goals: ...
- Rules: ...
- Constraint: ... (omit if none)

## Service Overview
- **Provider:** [service name and docs URL]
- **Purpose:** What it does for us
- **Environments:** [sandbox/staging/prod URLs]

## Authentication & Authorization
- Auth method: [API key / OAuth / JWT / etc.]
- Credential management: [where secrets are stored]
- Token lifecycle: [expiry, refresh strategy]

## API Contract

### Endpoints We Consume
| Method | Endpoint | Purpose |
|--------|----------|---------|
| ...    | ...      | ...     |

### Request/Response Examples
Key payloads with example data.

### Error Handling
| Error Code | Meaning | Our Response |
|------------|---------|--------------|
| ...        | ...     | ...          |

## Data Flow
How data moves between our system and the external service.

## Fallback & Resilience
- What happens if the service is down
- Retry strategy
- Circuit breaker / timeout configuration

## Configuration
Required env vars, feature flags, or config entries.

## QA Criteria
- [ ] Happy path works end-to-end
- [ ] Error scenarios handled gracefully
- [ ] Auth token refresh works
- [ ] Fallback behavior verified

## Open Questions
Unresolved decisions or items needing clarification.
```

### Infrastructure Slice

```markdown
# [Change Name] — Slice NN: [slice name]

**Date:** YYYY-MM-DD<br>
**Status:** Draft<br>
**Author:** Frank

## Serves
- Goals: ...
- Rules: ...
- Constraint: ... (omit if none)

## Current Setup
How the relevant infrastructure works today.

## Proposed Changes
Detailed description of what changes.

### Affected Components
| Component | Change | Environment |
|-----------|--------|-------------|
| ...       | ...    | ...         |

### Configuration Changes
New or modified env vars, parameters, secrets, IAM roles, etc.

### Pipeline Changes
CI/CD modifications — new stages, modified jobs, updated scripts.

## Rollback Plan
Exact steps to revert if something goes wrong.
1. Step 1 — ...
2. Step 2 — ...

## Deployment Strategy
- Order of operations
- Downtime expectations
- Feature flag requirements

## Monitoring & Validation
How to verify the change works post-deployment.
- [ ] Health check: ...
- [ ] Log verification: ...
- [ ] Metric to watch: ...

## Open Questions
Unresolved decisions or items needing clarification.
```

---

### Step 9: Save and Next Steps

1. Propose the folder path: `specs/<feature-slug>/`.
2. **First spec in project?** Ensure `specs/` is excluded from git:
   - Check if `specs/` is already in `.git/info/exclude`
   - If not, append `specs/` to `.git/info/exclude`
   - **NEVER** add to `.gitignore` — use `.git/info/exclude` only (local, not committed)
3. Ask the user to approve the content.
4. After approval, save the files:
   - **New feature:** write `00-overview.md` + `01-<slug>.md`.
   - **Adding a slice:** write the new `NN-<slug>.md` and tick/refresh the corresponding entry in the parent's `## Slices` map.
5. Offer to create a tracking issue. If accepted, **invoke the `/create-issue` skill** via the Skill tool, passing the requirement description. Do NOT mention any spec file, its path, or its existence in the issue — only its content informs the issue body. Do not re-implement the issue-creation flow inline.

## Rules

- Spec files are **internal-use only** — they never leave the local machine. **Hard rule, no exceptions.**
- **NEVER** commit spec files to git.
- **NEVER** mention, reference, link, attach, paste, or quote spec files in any artifact that leaves the local machine. This explicitly includes:
  - Committed Markdown files (READMEs, ADRs, in-repo `docs/`, runbooks)
  - Git commit messages and tags
  - GitLab/GitHub issues, MRs, PRs (titles, descriptions, comments, review threads)
  - Code comments in committed source files
  - External chat, email, tickets, or shared documents
- The path, filename, or existence of a spec file must not appear anywhere outside `specs/` and the local conversation.
- Spec **content** can inform issues, MRs, and committed docs — but the file itself, its path, its name, and internal references (`G1`, `BR1`, slice IDs) must not be referenced outside `specs/`.
