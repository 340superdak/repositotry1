import { describe, expect, it } from "vitest";
import { runAudit } from "../src/audit/engine.js";
import { saveAuditRun, listProposals } from "../src/proposals/store.js";
import { approveProposal, rejectProposal, ReviewError } from "../src/proposals/review.js";
import { applyProposal, ApplyError } from "../src/proposals/apply.js";

async function seedProposals() {
  const { report, proposals } = await runAudit(28);
  await saveAuditRun(report, proposals);
  return proposals;
}

describe("proposal review + apply lifecycle", () => {
  it("refuses to apply a proposal that hasn't been approved", async () => {
    const [proposal] = await seedProposals();
    await expect(applyProposal(proposal.id)).rejects.toBeInstanceOf(ApplyError);
  });

  it("approve -> apply writes a mock sandbox theme id/preview url for theme-change proposals", async () => {
    const proposals = await seedProposals();
    const withChanges = proposals.find((p) => p.themeChanges.length > 0);
    expect(withChanges).toBeDefined();

    await approveProposal(withChanges!.id, "test-user");
    const applied = await applyProposal(withChanges!.id);

    expect(applied.status).toBe("applied");
    expect(applied.appliedTo?.themeId).toMatch(/^mock-sandbox-theme-/);
    expect(applied.appliedTo?.previewUrl).toContain("preview_theme_id");
  });

  it("approve -> apply on a strategy-only proposal marks applied without a theme write", async () => {
    const proposals = await seedProposals();
    const noChanges = proposals.find((p) => p.themeChanges.length === 0);
    expect(noChanges).toBeDefined();

    await approveProposal(noChanges!.id);
    const applied = await applyProposal(noChanges!.id);

    expect(applied.status).toBe("applied");
    expect(applied.appliedTo).toBeUndefined();
  });

  it("rejected proposals can never be applied", async () => {
    const [proposal] = await seedProposals();
    await rejectProposal(proposal.id, "test-user", "not a priority right now");
    await expect(applyProposal(proposal.id)).rejects.toBeInstanceOf(ApplyError);
  });

  it("refuses to review the same proposal twice", async () => {
    const [proposal] = await seedProposals();
    await approveProposal(proposal.id);
    await expect(approveProposal(proposal.id)).rejects.toBeInstanceOf(ReviewError);
  });

  it("lists proposals filtered by status", async () => {
    const proposals = await seedProposals();
    await approveProposal(proposals[0].id);
    const pending = await listProposals("pending");
    const approved = await listProposals("approved");
    expect(approved.some((p) => p.id === proposals[0].id)).toBe(true);
    expect(pending.some((p) => p.id === proposals[0].id)).toBe(false);
  });
});
