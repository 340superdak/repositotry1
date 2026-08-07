import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { runAudit } from "./audit/engine.js";
import { collectPageMetrics } from "./audit/collector.js";
import { saveAuditRun, listAudits, getAudit, listProposals, getProposal } from "./proposals/store.js";
import { approveProposal, rejectProposal } from "./proposals/review.js";
import { applyProposal, ApplyError } from "./proposals/apply.js";
import { config, hasLiveGA4Credentials, hasLiveShopifyCredentials } from "./config.js";

function json(data: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }] };
}

function errorResult(message: string) {
  return { content: [{ type: "text" as const, text: message }], isError: true as const };
}

export function registerTools(server: McpServer): void {
  server.registerTool(
    "run_audit",
    {
      title: "Run a store audit",
      description:
        "Collects merged Shopify + Google Analytics 4 data for the store's key pages and " +
        "evaluates industry-practice recommendation rules against it (conversion, engagement, " +
        "cart/checkout abandonment, mobile UX). Produces an audit report and drafts a pending " +
        "ChangeProposal for each recommendation. This ONLY drafts proposals -- it never modifies " +
        "the store. Use approve_proposal + apply_proposal to act on a recommendation.",
      inputSchema: {
        lookbackDays: z
          .number()
          .int()
          .positive()
          .optional()
          .describe("Analytics lookback window in days. Defaults to DEFAULT_LOOKBACK_DAYS (28)."),
      },
    },
    async ({ lookbackDays }) => {
      const days = lookbackDays ?? config.defaultLookbackDays;
      const { report, proposals } = await runAudit(days);
      await saveAuditRun(report, proposals);
      return json({
        auditId: report.id,
        pagesAnalyzed: report.pagesAnalyzed,
        lookbackDays: report.lookbackDays,
        recommendationCount: report.recommendations.length,
        proposalIds: proposals.map((p) => p.id),
        dataSource: {
          shopify: hasLiveShopifyCredentials() ? "live" : "mock",
          ga4: hasLiveGA4Credentials() ? "live" : "mock",
        },
      });
    }
  );

  server.registerTool(
    "get_audit_report",
    {
      title: "Get a full audit report",
      description: "Fetches the full recommendation list for a previously run audit by its id.",
      inputSchema: { auditId: z.string() },
    },
    async ({ auditId }) => {
      const report = await getAudit(auditId);
      if (!report) return errorResult(`Audit not found: ${auditId}`);
      return json(report);
    }
  );

  server.registerTool(
    "list_recent_audits",
    {
      title: "List recent audits",
      description: "Lists past audit runs (id, timing, recommendation count) most recent last.",
      inputSchema: {},
    },
    async () => {
      const audits = await listAudits();
      return json(
        audits.map((a) => ({
          id: a.id,
          createdAt: a.createdAt,
          lookbackDays: a.lookbackDays,
          pagesAnalyzed: a.pagesAnalyzed,
          recommendationCount: a.recommendations.length,
        }))
      );
    }
  );

  server.registerTool(
    "get_page_metrics",
    {
      title: "Get raw merged page metrics",
      description:
        "Ad hoc inspection tool: returns the merged Shopify + GA4 metrics per page without " +
        "running the recommendation rules, useful for spot-checking a specific page's numbers.",
      inputSchema: {
        lookbackDays: z.number().int().positive().optional(),
        path: z.string().optional().describe("Filter to a single page path, e.g. \"/products/foo\"."),
      },
    },
    async ({ lookbackDays, path }) => {
      const metrics = await collectPageMetrics(lookbackDays ?? config.defaultLookbackDays);
      return json(path ? metrics.filter((m) => m.path === path) : metrics);
    }
  );

  server.registerTool(
    "list_proposals",
    {
      title: "List change proposals",
      description:
        "Lists drafted change proposals, optionally filtered by status " +
        "(pending, approved, rejected, applied).",
      inputSchema: {
        status: z.enum(["pending", "approved", "rejected", "applied"]).optional(),
      },
    },
    async ({ status }) => json(await listProposals(status))
  );

  server.registerTool(
    "get_proposal",
    {
      title: "Get a change proposal",
      description: "Fetches full detail for one change proposal, including any theme file diffs.",
      inputSchema: { proposalId: z.string() },
    },
    async ({ proposalId }) => {
      const proposal = await getProposal(proposalId);
      if (!proposal) return errorResult(`Proposal not found: ${proposalId}`);
      return json(proposal);
    }
  );

  server.registerTool(
    "approve_proposal",
    {
      title: "Approve a change proposal",
      description:
        "Marks a pending proposal as approved. This is the explicit human-in-the-loop gate: " +
        "nothing is ever written to the store without a proposal first being approved here.",
      inputSchema: {
        proposalId: z.string(),
        reviewedBy: z.string().optional(),
        reviewNote: z.string().optional(),
      },
    },
    async ({ proposalId, reviewedBy, reviewNote }) => {
      try {
        return json(await approveProposal(proposalId, reviewedBy, reviewNote));
      } catch (err) {
        return errorResult((err as Error).message);
      }
    }
  );

  server.registerTool(
    "reject_proposal",
    {
      title: "Reject a change proposal",
      description: "Marks a pending proposal as rejected so it will never be applied.",
      inputSchema: {
        proposalId: z.string(),
        reviewedBy: z.string().optional(),
        reviewNote: z.string().optional(),
      },
    },
    async ({ proposalId, reviewedBy, reviewNote }) => {
      try {
        return json(await rejectProposal(proposalId, reviewedBy, reviewNote));
      } catch (err) {
        return errorResult((err as Error).message);
      }
    }
  );

  server.registerTool(
    "apply_proposal",
    {
      title: "Apply an approved change proposal",
      description:
        "Applies an already-approved proposal's theme file changes. Writes are only ever made " +
        "to an UNPUBLISHED/DEVELOPMENT theme (resolved fresh from Shopify), never the live theme " +
        "customers see -- you still need to review and publish the change yourself in the Shopify " +
        "admin. Refuses to run on anything not already in 'approved' status.",
      inputSchema: { proposalId: z.string() },
    },
    async ({ proposalId }) => {
      try {
        return json(await applyProposal(proposalId));
      } catch (err) {
        if (err instanceof ApplyError) return errorResult(err.message);
        throw err;
      }
    }
  );
}
