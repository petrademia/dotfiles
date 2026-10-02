# Verification methods

Use this guide when choosing checks for the verification triangle or deciding whether two methods are meaningfully independent.

## Test independence

Two checks add distinct evidence when they can fail for different reasons. Ask:

- Do they observe different parts of the real system?
- Do they use different inputs, oracles, or sources of truth?
- Could one pass while the other exposes the claim as false?
- Did one check come from the implementation's assumptions, or from an independent contract?

Examples of weak combinations:

- three tests that call the same mocked dependency;
- two agents reviewing the same summary without reading the artifact;
- a unit test and snapshot that assert the same implementation detail;
- an agent checking its own claim by restating the reasoning.

Examples of stronger combinations:

- an acceptance criterion, a user-path execution, and a mutation that proves the check detects the defect;
- a database invariant and an API-level integration test;
- a compiler or schema check and a live compatibility probe;
- a benchmark and a profiler trace tied to the same workload.

## Contract conflicts

Potential contract sources include the current user instruction, ticket, formal specification, repository documentation, tests, API or schema definitions, and observed production behavior. They do not automatically have equal authority.

When sources disagree:

1. State the conflicting claims and cite their sources.
2. Apply an explicit precedence rule from the repository or user when one exists.
3. If the conflict changes the required outcome and no authorized rule resolves it, block the contract gate and request a decision.
4. Preserve the conflict in the verification record.

Do not infer precedence from whichever source makes the implementation easiest or supports the agent's current theory.

## Separate completion role from assurance

Classify each criterion twice:

| Dimension | Values | Effect |
|---|---|---|
| Completion role | Required or supplemental | Required criteria must be verified before claiming full completion |
| Assurance level | Standard or elevated | Elevated criteria require all three independent gates |

These dimensions answer different questions. A typo correction can be required for completion while remaining standard assurance. A payment-integrity claim can be required and elevated.

The Contract gate applies to every material claim. A standard-assurance claim also needs the most direct applicable observation, normally Execution. Add or elevate to the Challenge gate when any of these conditions holds:

- the claim is costly or hard to reverse;
- the implementation and primary check share assumptions;
- the bug or regression was previously missed by existing checks;
- a passing check could be insensitive to the changed behavior;
- the evidence is probabilistic, indirect, or incomplete;
- the agent is making a causal or broad compatibility claim.

Do not lower assurance merely because a gate is difficult to run. Apply the outcome precedence below.

## Outcome precedence

Evaluate conditions from top to bottom and stop at the first match:

| Priority | Condition | Criterion status |
|---|---|---|
| 1 | With a settled contract, any gate produced valid counterevidence against the claim | Falsified |
| 2 | Authoritative requirements conflict without a precedence decision, or a required gate has a known check that cannot run because of a concrete dependency, authority, environment, or safety constraint | Blocked |
| 3 | A required gate lacks an adequate method or sufficient evidence | Unverified |
| 4 | Every required gate passed and no contradiction remains | Verified |

Label a verified criterion **Triangulated** when all three gates passed with meaningfully independent evidence. Passing one or two gates may be reported as supporting evidence, but it does not create another completion status.

A conflicting requirement is not counterevidence against either candidate contract until an authorized source resolves which contract applies. Likewise, a failed command is not automatically counterevidence. Distinguish an unresolved contract or environmental/tooling failure, which may block verification, from an observation that falsifies a settled claim. When a check has not been designed or its evidence is inadequate, use Unverified rather than Blocked.

## Methods by task

| Task | Contract gate | Execution gate | Challenge gate |
|---|---|---|---|
| Bug fix | Reported symptom and expected behavior | Failing-before and passing-after scenario, trace, or direct observation | Revert or mutate the fix, inject the failure condition, or exercise a different path |
| Feature | Acceptance criteria and user contract | Focused user-path or integration check | Negative, boundary, permission, or failure-path check |
| Refactor | Preserved behavior and interfaces | Existing focused tests and representative execution | Differential comparison between old and new behavior |
| Migration | Target schema, protocol, or configuration | Forward migration on representative data or environment | Compatibility, rollback, restart, or partial-failure check |
| Performance | Defined workload and threshold | Repeated before-and-after measurement | Profiler trace, alternate workload, or regression distribution |
| Documentation or configuration | Authoritative format and intended consumer | Parser, renderer, loader, or dry-run | Broken-reference scan, clean-environment check, or independent source comparison |

## Challenge patterns

Choose a challenge that can expose false confidence:

- **Sensitivity:** remove, revert, or mutate the relevant change and confirm that the check detects the difference.
- **Boundary:** exercise values immediately around a threshold or contract edge.
- **Negative path:** provide invalid, unauthorized, missing, or conflicting input.
- **Differential:** compare the same input across versions, configurations, or implementations.
- **Invariant:** inspect the resulting state rather than trusting a success response.
- **Independent source:** compare against an authoritative document, system of record, or separately collected observation.
- **Fault injection:** force the error, timeout, retry, crash, or partial completion that the claim says is handled.

Do not run every pattern. Select the smallest one that can falsify the material claim.

## Safe challenges

Challenge evidence is useful only when obtaining it stays within the task's authority and acceptable risk. Prefer:

- an isolated worktree or disposable environment;
- fixtures, copied data, or an ephemeral database;
- a dry run or read-only probe;
- a transaction or deployment that has a tested rollback;
- a local mutation of the change or test rather than a live-system mutation.

Before fault injection, rollback, destructive input, or an external write, resolve the exact target, expected effect, stopping condition, and recovery path. Do not test against production or mutate external state without explicit authorization. If safe execution is unavailable, mark the challenge gate blocked and state the exact check that remains.

## Evidence record

For each material criterion, retain:

- criterion and claim;
- gate and method;
- command, action, or source;
- relevant input and environment;
- expected observation;
- actual observation;
- evidence location or concise output;
- final status and any contradiction.

Evidence must be reviewable without exposing credentials, personal data, or unrestricted production payloads.
