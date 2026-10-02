# Reproducibility for unstable checks

Use this guide only when a verification check produces inconsistent results under apparently identical conditions. Reproducibility is a means of obtaining assessable evidence, not the goal of the overall task.

## Confirm the instability

Preserve the inputs and context that may affect the result: time, seed, configuration, environment, ordering, schedule, external response, persisted state, dependency versions, and relevant logs.

Do not label a difficult-to-reproduce failure nondeterministic until ordinary input differences, stale state, and an incomplete oracle have been considered.

## Find the relevant uncontrolled input

Trace the selected check to the earliest uncontrolled value or event that can change its verdict. Common sources include:

- wall-clock time, deadlines, and timers;
- randomness, generated identifiers, and probabilistic services;
- implicit iteration, filesystem, query, or event ordering;
- concurrency, scheduling, cancellation, and process lifecycle;
- environment variables, locale, platform, and resource availability;
- persistence, caches, queues, networks, and external APIs.

Inventory only sources that can affect the check. Do not attempt to make the entire repository deterministic.

## Apply the smallest control

Prefer, in order:

1. Remove variability that has no product meaning.
2. Pass the value explicitly.
3. Canonicalize equivalent results.
4. Inject the narrow dependency that owns the variability.
5. Synchronize on a real condition instead of elapsed time.
6. Capture and replay an irreducible boundary.
7. Verify a stable invariant when exact output should remain variable.

A clock, random-number generator, scheduler, identifier generator, adapter, simulator, or record-and-replay layer is an option, not a required deliverable.

## Prove the check is useful

Use a proof tied to the diagnosed source:

| Source | Suitable proof |
|---|---|
| Randomness | Replay the captured seed and surface seeds on later failures |
| Time | Drive an explicit or virtual clock across the relevant boundary |
| Ordering | Exercise relevant orders or compare a canonical form when order has no meaning |
| Concurrency | Force the critical interleaving or preserve a failing schedule |
| External input | Replay a safe captured interaction and retain an appropriate live-boundary check |
| Distributed behavior | Replay the operation history and check the stated invariant |

A single passing run does not establish reproducibility. When the causal condition is known, force it. When only a historical failure rate is known, state the number of attempts and observed results without claiming certainty.

## Guardrails

- Do not hide instability with arbitrary sleeps, timeout increases, silent retries, or quarantine.
- Do not seed randomness without surfacing the seed on failure.
- Do not globally serialize the system to conceal a race.
- Do not freeze every clock or replace every external dependency when one boundary is responsible.
- Do not require exact equality for intentionally probabilistic or distributed behavior.
- Do not claim that the service is deterministic because one verification check is stable.
