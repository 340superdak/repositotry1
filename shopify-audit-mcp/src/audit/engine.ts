import { randomUUID } from "node:crypto";
import { collectPageMetrics } from "./collector.js";
import { RULES } from "./rules.js";
import type { AuditReport, ChangeProposal, Recommendation } from "../types.js";

function riskLevelFor(recommendation: Recommendation): ChangeProposal["riskLevel"] {
  if (recommendation.suggestedThemeChanges.length === 0) return "low";
  return recommendation.severity === "high" ? "medium" : "low";
}

function proposalFrom(auditId: string, recommendation: Recommendation): ChangeProposal {
  return {
    id: randomUUID(),
    auditId,
    createdAt: new Date().toISOString(),
    recommendationId: recommendation.id,
    title: recommendation.title,
    rationale: recommendation.rationale,
    evidence: recommendation.evidence,
    riskLevel: riskLevelFor(recommendation),
    themeChanges: recommendation.suggestedThemeChanges,
    status: "pending",
  };
}

export interface AuditRunResult {
  report: AuditReport;
  proposals: ChangeProposal[];
}

/**
 * Runs one full audit cycle: collect merged Shopify+GA4 metrics, evaluate every
 * rule against every page, and draft a proposal for each recommendation. This
 * function only ever *drafts* proposals -- nothing here touches the store.
 */
export async function runAudit(lookbackDays: number): Promise<AuditRunResult> {
  const metrics = await collectPageMetrics(lookbackDays);

  const recommendations: Recommendation[] = [];
  for (const pageMetrics of metrics) {
    for (const rule of RULES) {
      const result = rule(pageMetrics);
      if (result) recommendations.push(result);
    }
  }

  const report: AuditReport = {
    id: randomUUID(),
    createdAt: new Date().toISOString(),
    lookbackDays,
    pagesAnalyzed: metrics.length,
    recommendations,
  };

  const proposals = recommendations.map((r) => proposalFrom(report.id, r));
  return { report, proposals };
}
