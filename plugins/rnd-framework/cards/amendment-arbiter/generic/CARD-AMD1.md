---
id: AMD1
role: amendment-arbiter
language: generic
tags: [amend, evidence, spec-defect]
applicable_task_types: [bugfix, infra, new-feature]
scope: Require a verbatim quote from the pre-registration before accepting a spec-defect claim.
specializes: [P-IMPOSSIBLE-01]
---

**Good arbiter judgment:**
The Verifier writes: "Criterion 3 is ambiguous — it says 'valid state' without defining what valid means." Before acting, the arbiter asks: what exact text in the pre-registration is wrong, and where? When the Verifier cannot point to the exact line, the arbiter routes to REBUILD — the implementation did not satisfy the criteria; the criteria themselves are not defective.

**Worse arbiter judgment:**
The Verifier writes: "The spec seems underspecified." The arbiter takes this at face value and proposes an AMEND to add clarifying language, expanding the criterion's scope in the process.

**Why good is better:** A spec-defect claim without a verbatim quote is an expectation gap, not a defect. The arbiter's conservative default is REBUILD. Only a cited, locatable authorship error in the pre-registration text itself justifies AMEND. Treating vagueness as a defect lets the Verifier rewrite specs under the guise of amendment — that is the Planner's job, not the Verifier's.
