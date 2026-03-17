-- Artifact Flow: Formal proof that artifacts flow correctly through
-- the pipeline phases.

inductive Phase where
  | plan
  | build
  | proofGate
  | verify
  | integrate
  deriving DecidableEq, BEq, Repr

inductive Artifact where
  | planDoc
  | buildManifest
  | selfAssessment
  | proofReport
  | verificationReport
  | integrationReport
  deriving DecidableEq, Repr

def producedBy (a : Artifact) : Phase :=
  match a with
  | .planDoc => .plan
  | .buildManifest => .build
  | .selfAssessment => .build
  | .proofReport => .proofGate
  | .verificationReport => .verify
  | .integrationReport => .integrate

def consumedBy (a : Artifact) : List Phase :=
  match a with
  | .planDoc => [.build, .proofGate, .verify]
  | .buildManifest => [.verify, .integrate]
  | .selfAssessment => [.build]
  | .proofReport => [.verify]
  | .verificationReport => [.integrate]
  | .integrationReport => []

-- Build artifacts (manifest) are consumed by the verify phase
theorem build_artifacts_consumed_by_verify :
    Phase.verify ∈ consumedBy .buildManifest := by native_decide

-- Self-assessment is NOT consumed by the verify phase (information barrier)
theorem self_assessment_not_consumed_by_verify :
    Phase.verify ∉ consumedBy .selfAssessment := by native_decide
