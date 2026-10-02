# Architecture and design quality

Use this guide for repository or service coherence assessments and to select design dimensions for broad verification requests. Stay within the target established from context. Use the dimensions to investigate the code, without assuming each must reveal a defect or require a particular architecture.

## Establish the assessment boundary

Identify the requested repository, service, or subsystem and the available evidence. Map its main responsibilities, entry points, dependencies, data owners, and representative end-to-end flows. Prioritize boundaries that affect the user's concerns or behavior whose failure would be costly. Report inspected paths, exclusions, and unavailable components. File counts and passing tests do not establish that coverage.

Read declared architecture rules, domain definitions, interface contracts, schemas, configuration, and relevant callers and implementations. Separate authoritative requirements from inferred conventions. If architecture documentation is missing, label any inferred rules. Do not invent requirements for the code.

## Assessment dimensions

| Dimension | Question and useful evidence | Interpretation guardrail |
|---|---|---|
| Cohesion | Do responsibilities within a component belong together? Trace its operations, owned concepts, and reasons for change. Use change history when available. | Size or function count alone does not establish poor cohesion. A cohesive component may be substantial. |
| Coupling | What implementation details, data formats, operation ordering, availability, or coordinated changes does one component require from another? Inspect callers, imports, shared storage, deployment assumptions, and failure propagation. | Dependencies are necessary. Explain a concrete change or failure scenario before calling coupling a risk. |
| Encapsulation / information hiding | Does the owner of state or policy enforce its rules through a stable boundary? Look for direct internal writes, leaked representations, and rules callers must duplicate. | Identify the ownership rule or consequence before treating a public field or shared table as a defect. |
| Separation of concerns | Do HTTP handlers, jobs, events, and other relevant entry points apply the same business rules? Trace policy, transport, persistence, and presentation responsibilities. | Do not prescribe extra layers or classes when existing functions separate the responsibilities adequately. |
| Architectural conformance | Do actual dependencies, writes, and calls follow declared layering, ownership, or communication rules? Compare the rule with the concrete violating path. | Label inferred patterns separately. Architectural preference is not an authoritative rule. |
| Contract compatibility | Does the caller meet the provider's preconditions, and does the provider supply the guarantees the caller needs? Compare types, errors, timing, retries, ordering, and consistency expectations. | Matching signatures or schemas does not establish behavioral compatibility. Inspect adapters and protections before alleging a mismatch. |
| Semantic consistency | Do exchanged concepts preserve meaning through producers, transformations, storage, and consumers? Trace units, identifiers, statuses, nullability, and time conventions. | Different bounded contexts may intentionally use different models. Check the translation at their boundary rather than demanding one global model. |
| Invariant preservation | Where and when must a rule hold, and can any path violate it? Trace transactions, concurrent operations, retries, partial failures, and recovery. | Specify the consistency boundary. Distinguish rules required at every commit from temporary inconsistency allowed by an explicit recovery contract. |

## Investigate relationships before choosing tools

1. State a specific expectation, its source, and the relationship under inspection. For example: "Every caller of this payment operation supplies a stable idempotency key on retries."
2. Follow the relevant path across components. Check both the caller's assumptions and the provider's guarantees, including intervening conversions and guards.
3. Look for evidence that disproves the suspected issue or explains the design. A retry wrapper, transaction constraint, version adapter, or documented context boundary may resolve an apparent contradiction.
4. Select the smallest applicable check: direct source or dependency inspection, schema comparison, an existing contract test, a runtime trace, or a contained scenario. Choose checks that can settle the question.
5. Apply the main skill's assurance and evidence rules. Static evidence can establish a structural dependency. Runtime failure frequency, performance, and reachability under production configuration need further evidence.

For example, if a producer documents amounts in cents and a consumer treats them as dollars, cite both definitions and trace the actual transfer, including any conversion. If a conversion resolves the difference, there is no mismatch. If the transfer is unavailable, report the unresolved question and the evidence needed to settle it.

## Report findings and coverage

For each finding, record the relevant dimension, rule or quality goal and its authority, precise evidence locations, affected relationship or path, consequence, and evidence limitations. Recommend corrections supported by the evidence.

Distinguish finding types from the main skill's criterion statuses:

- A demonstrated defect violates a contract, invariant, or declared architecture rule. State the claim being checked. Confirming a defect does not verify system correctness.
- A design risk or tradeoff has a specific potential consequence under stated conditions. Cite the dependency or structure, explain the relevant goal and any known benefit, and distinguish the risk from an observed failure.
- An unresolved question lacks a required decision, implementation, configuration, or runtime evidence. State what would resolve it.

Group symptoms with one underlying cause rather than counting the same issue once per dimension. Summarize inspected components and flows, methods used, exclusions, and outstanding questions. If you find no issue, report that result within the inspected scope. Do not conclude that every relationship is coherent. Keep assessment read-only unless changes were requested.

## Background

These references supply vocabulary and evaluation approaches, not automatic compliance claims:

- [Architectural principles](https://learn.microsoft.com/dotnet/standard/modern-web-apps-azure-architecture/architectural-principles): separation of concerns, encapsulation, and dependency design.
- [SEI design conformance](https://sei.cmu.edu/annual-reviews/2021-research-review/automated-design-conformance-during-continuous-integration/): comparing implemented and intended design.
- [Design by Contract](https://www.eiffel.com/values/design-by-contract/introduction/): preconditions, postconditions, and invariants.
- [Domain analysis](https://learn.microsoft.com/en-us/azure/architecture/microservices/model/domain-analysis): bounded contexts and domain models.
- [ISO/IEC 25010:2023](https://committee.iso.org/standard/78176.html): product quality model.
- [ISO/IEC/IEEE 42010:2022](https://www.iso.org/standard/74393.html): architecture description requirements.
- [ATAM](https://www.sei.cmu.edu/library/the-architecture-tradeoff-analysis-method/): evaluation against quality goals and tradeoffs.
