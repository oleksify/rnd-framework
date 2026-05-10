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
  | polisher
  deriving DecidableEq, Repr

-- A validated evidence-pack manifest carries a proof that no disallowed
-- free-text fields (notes, summary, confidence, reasoning, explanation)
-- are present. The Lean model treats schema validity as an opaque proposition
-- rather than replicating the jq field-check logic here.
structure Manifest where
  isSchemaValid : Bool
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
  | evidencePackManifest (m : Manifest)
  deriving DecidableEq, Repr

def canAccess (agent : AgentType) (file : FileType) : Bool :=
  match agent, file with
  | .verifier, .selfAssessment => false
  | .proofGate, .selfAssessment => false
  -- Verifier may only read an evidence-pack manifest when schema validation passes.
  | .verifier, .evidencePackManifest m => m.isSchemaValid
  -- amendments live at $RND_DIR/briefs/T<id>-amendments.md — blocked from verifier and proofGate
  -- by the existing /briefs/ hook barrier; these clauses make that invariant explicit in Lean.
  -- amendmentArbiter access to amendments and selfAssessment is governed by orchestrator
  -- discipline + soft self-check rather than runtime hook enforcement, so no Lean clauses
  -- claim those properties.
  | .verifier, .amendments => false
  | .proofGate, .amendments => false
  | .polisher, .selfAssessment => false
  | .polisher, .amendments => false
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

theorem polisher_cannot_access_self_assessment :
    canAccess .polisher .selfAssessment = false := by native_decide

theorem polisher_cannot_access_amendments :
    canAccess .polisher .amendments = false := by native_decide

-- Evidence-pack manifest theorems: the Verifier may not read an unvalidated
-- manifest (isSchemaValid = false). A validated manifest (isSchemaValid = true)
-- is readable, encoding that the evidence-pack-gate.sh hook must validate
-- before allowing the read.
theorem verifier_cannot_access_unvalidated_manifest :
    ∀ (m : Manifest), m.isSchemaValid = false →
      canAccess .verifier (.evidencePackManifest m) = false := by
  intro m hm
  simp [canAccess, hm]

theorem verifier_can_access_validated_manifest :
    ∀ (m : Manifest), m.isSchemaValid = true →
      canAccess .verifier (.evidencePackManifest m) = true := by
  intro m hm
  simp [canAccess, hm]
