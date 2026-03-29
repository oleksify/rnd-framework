-- Information Barrier: Formal proof that Verifier and ProofGate agents
-- cannot access Builder self-assessment files.

inductive AgentType where
  | builder
  | verifier
  | proofGate
  | planner
  | integrator
  | dataScientist
  deriving DecidableEq, Repr

inductive FileType where
  | selfAssessment
  | code
  | tests
  | proofReport
  | manifest
  | plan
  | verification
  deriving DecidableEq, Repr

def canAccess (agent : AgentType) (file : FileType) : Bool :=
  match agent, file with
  | .verifier, .selfAssessment => false
  | .proofGate, .selfAssessment => false
  | _, _ => true

theorem verifier_cannot_access_self_assessment :
    canAccess .verifier .selfAssessment = false := by native_decide

theorem proofGate_cannot_access_self_assessment :
    canAccess .proofGate .selfAssessment = false := by native_decide

theorem builder_can_access_own_self_assessment :
    canAccess .builder .selfAssessment = true := by native_decide
