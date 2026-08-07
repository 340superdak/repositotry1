import { describe, expect, it } from "vitest";
import { runAudit } from "../src/audit/engine.js";

// No Shopify/GA4 credentials are set in the test environment, so this
// exercises the full pipeline against the deterministic mock fixtures.
describe("runAudit (mock data)", () => {
  it("analyzes every mock page and only drafts proposals, never applies anything", async () => {
    const { report, proposals } = await runAudit(28);

    expect(report.pagesAnalyzed).toBe(6);
    expect(report.recommendations.length).toBeGreaterThan(0);
    expect(proposals).toHaveLength(report.recommendations.length);
    expect(proposals.every((p) => p.status === "pending")).toBe(true);
  });

  it("flags the known problem pages from the mock fixtures", async () => {
    const { report } = await runAudit(28);
    const paths = report.recommendations.map((r) => r.path);

    expect(paths).toContain("/products/aurora-wool-jacket"); // engaged but not converting
    expect(paths).toContain("/products/everyday-canvas-tote"); // fast bounce
    expect(paths).toContain("/cart"); // high abandonment
    expect(paths).toContain("/checkouts"); // checkout friction
  });

  it("does not flag the healthy home/collection pages", async () => {
    const { report } = await runAudit(28);
    const paths = report.recommendations.map((r) => r.path);

    expect(paths).not.toContain("/");
    expect(paths).not.toContain("/collections/new-arrivals");
  });
});
