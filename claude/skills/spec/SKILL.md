---
name: spec
description: Create specification documents without implementing code. Auto-detects spec type (feature, bug, refactor, integration, infrastructure) and uses the appropriate structure.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(git *), Bash(glab *), Bash(gh *), Task
argument-hint: [feature-name or description]
---

# Specification Document Creator

Create a specification/design document for: $ARGUMENTS

## Critical Rules

- **NEVER** write, edit, or implement any code
- **NEVER** enter plan mode or start implementation
- Output is ONLY a spec document — nothing else
- If the user hasn't described the feature clearly enough, ask clarifying questions before writing

## Instructions

### Step 1: Understand Context

1. Read the project's `CLAUDE.md` for conventions
2. Search for existing specs to match format:
   - Check `docs/specs/`, `specs/`, `docs/` directories
   - If existing specs found — match their structure exactly (skip Step 2 type detection, adapt to existing format)
   - If no existing specs — use the type-specific structures below
3. Explore relevant parts of the codebase to understand the current architecture
4. Identify impacted modules, services, and dependencies

### Step 2: Detect Spec Type

Infer the spec type from the user's description, then **confirm with the user before proceeding**:

| Type               | Signals                                                                                          |
|--------------------|--------------------------------------------------------------------------------------------------|
| **Feature**        | "add", "new", "implement", "support for", user-facing functionality                              |
| **Bug/Fix**        | "bug", "broken", "error", "doesn't work", "fix", "regression", issue references                  |
| **Refactor**       | "refactor", "restructure", "migrate", "clean up", "decouple", "extract", pattern changes         |
| **Integration**    | "integrate", "connect", external service names (Keycloak, Twilio, Stripe, etc.), API consumption |
| **Infrastructure** | "pipeline", "CI/CD", "deploy", "Docker", "GCP", "infra", "monitoring", environment changes       |

Use AskUserQuestion to confirm: _"Detected spec type: **[type]**. Is this correct?"_

### Step 3: Ask Clarifying Questions

Before writing, ensure you understand the scope. Questions vary by type:

- **Feature:** Scope boundaries, target users, integration points, constraints
- **Bug:** How to reproduce, affected environments, severity, since when
- **Refactor:** What's wrong with current approach, constraints on migration, backward compatibility
- **Integration:** Which service, auth method, environments, rate limits
- **Infrastructure:** Affected environments, rollback needs, downtime tolerance

Use AskUserQuestion if anything is unclear.

### Step 4: Write the Spec

Use the appropriate structure below based on detected type.

---

## Spec Structures

### Feature Spec

```markdown
# [Feature Name] — Feature Specification

## Overview
Brief description of the feature and its business value.

## User Stories
- As a [role], I want [capability], so that [benefit]

## Requirements

### Functional Requirements
- FR-1: ...
- FR-2: ...

### Non-Functional Requirements
- NFR-1: ...

## Technical Design

### Architecture
How this integrates with the existing system.

### Data Model Changes
Database/schema changes if applicable.

### API Changes
New or modified endpoints/contracts.

### Dependencies
External services, libraries, or modules involved.

## Implementation Steps
Ordered breakdown of how to build this incrementally.
1. Step 1 — ...
2. Step 2 — ...

## QA Criteria
- [ ] Acceptance criteria checklist
- [ ] Edge cases to test

## Open Questions
Unresolved decisions or items needing clarification.
```

### Bug/Fix Spec

```markdown
# [Bug Title] — Bug Specification

## Problem Description
Clear description of the incorrect behavior.

## Reproduction Steps
1. Step 1
2. Step 2
3. Observe: [what happens]

## Expected vs Actual Behavior

| | Description |
|---|---|
| **Expected** | What should happen |
| **Actual** | What happens instead |

## Affected Scope
- Environments: [dev/staging/prod]
- Users impacted: [scope]
- Since: [when it started, if known]
- Severity: [critical/high/medium/low]

## Root Cause Analysis
Deep investigation of why this happens. Trace the code path, identify the failing component, explain the underlying cause — not just symptoms.

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

### Refactor/Architecture Spec

```markdown
# [Refactor Name] — Architecture Specification

## Motivation
Why the current architecture is insufficient. Concrete pain points, not theoretical.

## Current State
How things work today. Diagrams or code references where helpful.

### Problems with Current Approach
- Problem 1: ...
- Problem 2: ...

## Proposed Architecture
How things should work after the refactor.

### Key Design Decisions
| Decision | Choice | Rationale |
|----------|--------|-----------|
| ... | ... | ... |

### Component Changes
Which modules/services/layers change and how.

## Migration Strategy
How to get from current state to proposed state incrementally.

1. Phase 1 — ...
2. Phase 2 — ...

### Backward Compatibility
What breaks, what stays compatible, how to handle the transition.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| ... | ... | ... | ... |

## QA Criteria
- [ ] Existing behavior preserved (no functional regressions)
- [ ] Performance not degraded
- [ ] New architecture validated with [specific test]

## Open Questions
Unresolved decisions or items needing clarification.
```

### Integration Spec

```markdown
# [Service Name] Integration — Specification

## Overview
What service we're integrating with and why.

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
| ... | ... | ... |

### Request/Response Examples
Key payloads with example data.

### Error Handling
| Error Code | Meaning | Our Response |
|-----------|---------|-------------|
| ... | ... | ... |

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

### Infrastructure Spec

```markdown
# [Change Name] — Infrastructure Specification

## Overview
What infrastructure change is being made and why.

## Current Setup
How the relevant infrastructure works today.

## Proposed Changes
Detailed description of what changes.

### Affected Components
| Component | Change | Environment |
|-----------|--------|-------------|
| ... | ... | ... |

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

### Step 5: Save and Next Steps

1. Propose a file path for the spec (e.g., `specs/feature-name.md`)
2. **First spec in project?** Ensure `specs/` is excluded from git:
   - Check if `specs/` is already in `.git/info/exclude`
   - If not, append `specs/` to `.git/info/exclude`
   - **NEVER** add to `.gitignore` — use `.git/info/exclude` only (local, not committed)
3. Ask user to approve the spec content
4. After approval, offer to:
   - Save the spec document
   - Create a GitLab/GitHub issue **from** the spec content — follow the same conventions as the `/create-issue` skill (GitLab in Latin American Spanish, GitHub in English, audience-appropriate acceptance criteria, default labels and assignee)

## Rules

- Spec files are **internal-use only** — they never leave the local machine
- **NEVER** commit spec files to git
- **NEVER** reference or link spec files in issues, MRs, PRs, or any external documentation
- Spec content can **inform** issues and MRs, but the file itself must not be mentioned
