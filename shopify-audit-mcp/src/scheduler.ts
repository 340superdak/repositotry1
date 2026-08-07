#!/usr/bin/env node
import cron from "node-cron";
import { runAudit } from "./audit/engine.js";
import { saveAuditRun } from "./proposals/store.js";
import { config } from "./config.js";

// Standalone unattended entrypoint (run via `npm run schedule`, cron, systemd
// timer, etc.). By design this ONLY runs audits and writes pending proposals
// -- it never approves or applies anything. A human still has to review
// proposals via the MCP tools (or by reading data/proposals.json) and call
// approve_proposal + apply_proposal.

const schedule = process.env.AUDIT_CRON_SCHEDULE ?? "0 6 * * *"; // daily at 06:00 UTC by default

async function notify(summary: {
  auditId: string;
  recommendationCount: number;
  highSeverityCount: number;
}) {
  if (!config.notifyWebhookUrl) return;
  try {
    await fetch(config.notifyWebhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        text:
          `shopify-audit-mcp: audit ${summary.auditId} found ${summary.recommendationCount} ` +
          `recommendation(s), ${summary.highSeverityCount} high severity. Review pending ` +
          "proposals before anything is applied.",
      }),
    });
  } catch (err) {
    console.error("Failed to post audit notification webhook:", err);
  }
}

async function runOnce() {
  console.log(`[${new Date().toISOString()}] Running scheduled audit...`);
  const { report, proposals } = await runAudit(config.defaultLookbackDays);
  await saveAuditRun(report, proposals);
  const highSeverityCount = report.recommendations.filter((r) => r.severity === "high").length;
  console.log(
    `[${new Date().toISOString()}] Audit ${report.id} complete: ` +
      `${report.recommendations.length} recommendation(s) drafted as pending proposals ` +
      `(${highSeverityCount} high severity). Nothing was applied automatically.`
  );
  await notify({ auditId: report.id, recommendationCount: report.recommendations.length, highSeverityCount });
}

if (process.argv.includes("--once")) {
  runOnce().catch((err) => {
    console.error("Scheduled audit failed:", err);
    process.exit(1);
  });
} else {
  console.log(`shopify-audit-mcp scheduler starting with cron schedule "${schedule}"`);
  cron.schedule(schedule, () => {
    runOnce().catch((err) => console.error("Scheduled audit failed:", err));
  });
}
