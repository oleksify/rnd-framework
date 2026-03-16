/** Tests for 6-step restructure of rnd-verification skill */

import { describe, test, expect } from "bun:test";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

const SKILL = join(import.meta.dir, "..", "skills/rnd-verification/SKILL.md");
const read = () => readFile(SKILL, "utf-8");

function section(content: string, heading: string): string {
  const lines = content.split("\n");
  const s = lines.findIndex((l) => l.includes(heading));
  if (s === -1) return "";
  const e = lines.findIndex((l, i) => i > s && /^#{1,4} /.test(l));
  return lines.slice(s, e === -1 ? lines.length : e).join("\n");
}

describe("exactly 6 numbered process steps", () => {
  test("has ### 1. through ### 6.", async () => {
    const c = await read();
    for (let i = 1; i <= 6; i++) expect(c).toContain(`### ${i}.`);
  });
  test("no ### 7.", async () => {
    expect(await read()).not.toContain("### 7.");
  });
});

describe("Step 1 reads pre-registration", () => {
  test("step 1 mentions pre-registration and success criteria", async () => {
    const s = section(await read(), "### 1.");
    expect(s.toLowerCase()).toContain("pre-registration");
    expect(s.toLowerCase()).toContain("success criteria");
  });
});

describe("Step 2 writes independent experiments", () => {
  test("step 2 references rnd-experiments skill", async () => {
    const s = section(await read(), "### 2.");
    expect(s).toContain("rnd-framework:rnd-experiments");
  });
  test("step 2 prohibits reading Builder test files at this stage", async () => {
    const s = section(await read(), "### 2.");
    expect(s.toUpperCase()).toContain("MUST NOT");
  });
  test("step 2 output path is in verifications dir", async () => {
    const s = section(await read(), "### 2.");
    expect(s).toContain("$RND_DIR/verifications/T<id>-experiments/");
  });
});

describe("Step 3 runs experiments against Builder code", () => {
  test("step 3 instructs running experiments without reading Builder tests", async () => {
    const s = section(await read(), "### 3.");
    expect(s.toLowerCase()).toContain("experiment");
    expect(s.toUpperCase()).toContain("DO NOT");
  });
  test("step 3 output includes verbatim results", async () => {
    const s = section(await read(), "### 3.");
    expect(s.toLowerCase()).toContain("verbatim");
  });
});

describe("Step 4 runs Builder tests and compares", () => {
  test("step 4 instructs running Builder test suite", async () => {
    const s = section(await read(), "### 4.");
    expect(s.toLowerCase()).toContain("builder");
    expect(s.toLowerCase()).toContain("test");
  });
  test("step 4 compares with experiment results", async () => {
    const s = section(await read(), "### 4.");
    expect(s.toLowerCase()).toContain("compare");
    expect(s.toLowerCase()).toContain("experiment");
  });
});

describe("Step 5 contains code inspection, failure mode analysis, cross-criterion sweep", () => {
  test("step 5 has failure mode analysis substep", async () => {
    const c = await read();
    expect(c).toContain("**a. Failure Mode Analysis**");
  });
  test("step 5 has code inspection substep", async () => {
    const c = await read();
    expect(c).toContain("**b. Code Inspection**");
  });
  test("step 5 has cross-criterion sweep substep", async () => {
    const c = await read();
    expect(c).toContain("**c. Cross-Criterion Sweep**");
  });
});

describe("Step 6 produces verification report", () => {
  test("step 6 heading references verification report", async () => {
    expect(await read()).toContain("### 6. Produce Verification Report");
  });
  test("skill contains report template with Overall Verdict", async () => {
    expect(await read()).toContain("Overall Verdict");
  });
});

describe("allowed-tools includes Write", () => {
  test("frontmatter allowed-tools contains Write", async () => {
    expect(await read()).toContain("Write");
  });
});

describe("preserved sections", () => {
  test("Iron Laws section present", async () => {
    expect(await read()).toContain("## The Iron Laws");
  });
  test("Information Barrier section present", async () => {
    expect(await read()).toContain("## Information Barrier");
  });
  test("Two-Stage Evaluation section present", async () => {
    expect(await read()).toContain("## Two-Stage Evaluation");
  });
  test("Verdict Guidelines section present", async () => {
    expect(await read()).toContain("## Verdict Guidelines");
  });
  test("Evidence Standards section present", async () => {
    expect(await read()).toContain("## Evidence Standards");
  });
  test("Common Rationalizations section present", async () => {
    expect(await read()).toContain("## Common Rationalizations");
  });
});
