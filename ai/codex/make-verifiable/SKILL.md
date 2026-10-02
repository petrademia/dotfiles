---
name: make-verifiable
description: Turn engineering requests and AI-produced changes into explicit acceptance criteria, material claims, independent checks, and recorded evidence. Use when implementing or reviewing work that needs an auditable completion claim, including Jira tickets, bug fixes, features, refactors, migrations, and configuration changes. Do not use for open-ended brainstorming or work with no checkable artifact.
---

# Make verifiable

Require important completion claims to carry checkable evidence.

Verification does not make a claim infallible. It makes the claim observable, falsifiable, and explicit about what the available evidence does and does not establish.

## Scope

Work from the requested task, ticket, specification, and repository. Verify the selected change rather than auditing the entire system.

Treat request text as an input, not automatic truth. Separate stated requirements, repository facts, agent inferences, and unresolved product decisions.

Respect the requested mode:

- For implementation, define the verification contract, make the scoped change, and collect evidence.
- For assessment or review, evaluate the existing artifact without editing unless the user asks for changes.

Reuse existing tests, development commands, application drivers, and observability. During implementation, add the smallest missing check needed to verify a material claim. During assessment or review, run existing non-mutating checks and report missing checks rather than adding them.

## Verification triangle

For each material claim, select the applicable gates:

1. **Contract:** Does the claim match the request, acceptance criteria, documented behavior, or other authoritative source?
2. **Execution:** Does the real artifact exhibit the claimed behavior when exercised through a relevant path?
3. **Challenge:** Can a different method expose the claim as false, the check as insensitive, or the evidence as circular?

Each gate targets a different mistake:

| Gate | Mistake it detects |
|---|---|
| Contract | Solving the wrong requirement |
| Execution | Producing an artifact that does not work |
| Challenge | Using weak, circular, or insensitive verification |

The Contract gate applies to every material claim. A standard-assurance claim also needs the most direct applicable observation, normally Execution. An elevated-assurance claim requires all three gates. The methods must be meaningfully independent. Repeating the same oracle, mock, assumption, or model opinion does not add verification strength.

A valid contradiction cannot be outvoted by passing checks. Once the contract is settled, counterevidence against the claim makes it falsified. Conflicting authoritative requirements with no precedence rule instead block the Contract gate because the intended claim is not yet known.

## Workflow

### 1. Resolve the execution contract

Read repository instructions and the relevant runtime path. Extract the requested outcome, constraints, affected behavior, and explicit acceptance criteria. Mark any interpretation the agent introduced.

Compare the request, ticket, specification, documentation, tests, and observed behavior when they can define the contract. If authoritative sources materially conflict, record the conflict and do not pass the contract gate until an authorized decision resolves it. Do not choose the source that merely supports the proposed implementation.

Before implementation, record a concise execution contract in the task's working notes or response. Do this when the skill is invoked with an ordinary ticket or prompt; the user does not need to request contract resolution separately. Include only details relevant to the requested outcome:

- observable inputs, outputs, errors, and state changes;
- defaults, boundary cases, ordering, and retry behavior where they affect acceptance;
- scope and explicit exclusions;
- the sources or authorized decisions supporting the behavior, with agent assumptions labeled separately.

Resolve material ambiguity from authoritative sources first. Ask for clarification only when a missing product decision would materially change observable behavior or acceptance. Keep dependent implementation blocked while that decision is missing; continue independent work. Otherwise proceed with a stated, reversible interpretation. Do not turn an assumption into an approved requirement.

Keep trivial tasks to a short criterion rather than a full specification. The contract should make intended behavior consistent across executions without prescribing identical code or tool sequences.

### 2. Define material criteria and claims

Convert the execution contract into a bounded set of observable acceptance criteria. Trace each required criterion to its source or recorded decision, and use concrete inputs and expected outcomes where they clarify behavior. For each criterion, state the material claim the final response would need to make.

Before implementation or verification, classify each criterion along two separate dimensions:

- **Completion role:** required or supplemental. Explicit acceptance criteria and conditions that determine the requested outcome are required by default.
- **Assurance level:** standard or elevated, with a short risk-based rationale. Use elevated assurance for claims whose failure would be costly or hard to reverse, whose evidence shares assumptions with the implementation, or that make causal, security, financial, migration, or broad compatibility assertions.

Required does not imply elevated. A trivial task may have one required criterion that needs only standard assurance. Do not lower the assurance level because a check is difficult to run.

Exclude incidental implementation details unless the request makes them part of the contract. Do not expand into a whole-system quality plan.

### 3. Design the checks

Map each material claim to its contract, execution, and challenge checks as applicable. Record what each check can prove and the result that would falsify the claim.

Prefer direct observations of the real artifact. Use [verification-methods.md](references/verification-methods.md) when selecting independent methods or scaling the triangle to task risk.

Design challenge checks to be contained and reversible. Prefer isolated worktrees, disposable environments, fixtures, copied data, dry runs, or transactions that can be rolled back. Do not mutate production or external state merely to obtain stronger evidence; obtain explicit authorization when a necessary challenge would do so.

### 4. Establish the before state when relevant

For bug fixes, regressions, migrations, and performance changes, capture the current state before editing when practical. A bug may be established through a failing check, runtime trace, log, persisted artifact, or other direct evidence.

If the reported problem cannot be observed, distinguish "reported," "inferred," and "reproduced." Do not claim that a bug was reproduced or fixed without evidence supporting that statement.

### 5. Implement or inspect the scoped change

Make the smallest change that satisfies the criteria, unless the user requested assessment only. Preserve unrelated behavior and avoid cleanup that does not improve the required evidence.

Use the same execution contract for implementation and verification. If new evidence requires a contract change, record its source and reason, resolve any material product decision, and update affected criteria and checks before continuing dependent work. Never silently weaken the contract to fit the implementation.

### 6. Execute and record

Run the planned checks against the real artifact. Record enough information for another person or agent to assess the result: command or action, relevant inputs, expected observation, actual observation, and a safe pointer to retained evidence.

Never report a check as passed when it was not run. If a check is unstable, read [reproducibility.md](references/reproducibility.md) and make only that check reproducible enough to assess.

### 7. Evaluate evidence

Evaluate every material criterion using this precedence order:

1. **Falsified:** with a settled contract, valid counterevidence from any gate contradicts the claim. Passing checks cannot outvote it.
2. **Blocked:** the intended contract is unresolved because authoritative sources conflict, or at least one required gate has a known check that a concrete dependency, missing authority, unavailable environment, or safety constraint prevents from running.
3. **Unverified:** no counterevidence or blocker exists, but at least one required gate lacks an adequate method or sufficient evidence.
4. **Verified:** every required gate passed and no unresolved evidence contradicts the claim.

Also label a verified claim **Triangulated** when Contract, Execution, and Challenge all passed with meaningfully independent evidence. Elevated-assurance claims are verified only when triangulated. For other incomplete combinations, report which gates passed without inventing another completion status.

Do not turn these statuses into an AI confidence percentage. Report observable counts by criterion status and the triangulated subset. Attribute methods per claim rather than presenting an unexplained global method count.

### 8. Report the verification record

Report:

- each material criterion and claim;
- the gates and methods applied;
- the relevant evidence and observed result;
- the assigned status;
- contradictions, limitations, and exact follow-up checks for blocked work.

Claim full completion only when every required acceptance criterion is verified at its declared assurance level. Otherwise state the narrower result that the evidence supports.

## Guardrails

- Do not treat test-suite success as proof of claims the suite does not exercise.
- Do not count multiple checks as independent when they share the same oracle or assumption.
- Do not use mocks to verify the behavior of the mocked component.
- Do not hide failed or contradictory evidence behind a majority of passing checks.
- Do not invent certainty scores or describe work as foolproof.
- Do not require three checks for trivial claims when one direct check is sufficient.
- Do not describe a narrow validator as proof of parts it does not inspect.
- Do not pass the contract gate while authoritative requirements remain materially inconsistent.
- Do not run destructive or externally mutating challenges without explicit authorization and a bounded recovery plan.
- Do not broaden the task merely to improve a verification metric.
- Do not post evidence or change external ticket state unless the user requested that action.
