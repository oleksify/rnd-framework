import Lake
open Lake DSL

package proofs where
  leanOptions := #[⟨`autoImplicit, false⟩]

lean_lib Proofs where
  roots := #[`InformationBarrier, `ArtifactFlow]
