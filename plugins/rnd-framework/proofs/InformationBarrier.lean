-- Information Barrier: Formal proof that Verifier and ProofGate agents
-- cannot access Builder self-assessment files.

inductive AgentType where
  | builder
  | verifier
  | proofGate
  | planner
  | integrator
  | dataScientist
  | amendmentArbiter
  deriving DecidableEq, Repr

inductive FileType where
  | selfAssessment
  | code
  | tests
  | proofReport
  | manifest
  | plan
  | verification
  | amendments
  deriving DecidableEq, Repr

def canAccess (agent : AgentType) (file : FileType) : Bool :=
  match agent, file with
  | .verifier, .selfAssessment => false
  | .proofGate, .selfAssessment => false
  -- amendments live at $RND_DIR/briefs/T<id>-amendments.md — blocked from verifier and proofGate
  -- by the existing /briefs/ hook barrier; these clauses make that invariant explicit in Lean.
  -- amendmentArbiter access to amendments and selfAssessment is governed by orchestrator
  -- discipline + soft self-check rather than runtime hook enforcement, so no Lean clauses
  -- claim those properties.
  | .verifier, .amendments => false
  | .proofGate, .amendments => false
  | _, _ => true

theorem verifier_cannot_access_self_assessment :
    canAccess .verifier .selfAssessment = false := by native_decide

theorem proofGate_cannot_access_self_assessment :
    canAccess .proofGate .selfAssessment = false := by native_decide

theorem builder_can_access_own_self_assessment :
    canAccess .builder .selfAssessment = true := by native_decide

-- Amendment log theorems: amendments live in $RND_DIR/briefs/ — the same hook barrier
-- that blocks /briefs/ from verifier and proofGate also covers T<id>-amendments.md paths.
-- These theorems encode that runtime-enforced invariant at the type level.
theorem verifier_cannot_access_amendments :
    canAccess .verifier .amendments = false := by native_decide

theorem proofGate_cannot_access_amendments :
    canAccess .proofGate .amendments = false := by native_decide
