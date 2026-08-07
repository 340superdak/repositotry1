import { randomUUID } from "node:crypto";
import { findSandboxTheme, upsertThemeFiles } from "../clients/shopify.js";
import { config, hasLiveShopifyCredentials } from "../config.js";
import type { ChangeProposal } from "../types.js";
import { getProposal, updateProposal } from "./store.js";

export class ApplyError extends Error {}

/**
 * Applies an already-approved proposal. Safety invariants enforced here, not
 * just documented:
 *  - refuses anything not already in "approved" status (see approve/reject tools)
 *  - writes are only ever made to an UNPUBLISHED/DEVELOPMENT theme, resolved
 *    fresh from Shopify at apply time -- never the live/published theme
 *  - proposals with no theme changes (pure strategy recommendations) are
 *    marked applied without contacting Shopify at all, since there's nothing
 *    to write
 */
export async function applyProposal(proposalId: string, reviewedBy?: string): Promise<ChangeProposal> {
  const proposal = await getProposal(proposalId);
  if (!proposal) throw new ApplyError(`Proposal not found: ${proposalId}`);
  if (proposal.status !== "approved") {
    throw new ApplyError(
      `Proposal ${proposalId} is "${proposal.status}", not "approved". Call approve_proposal first.`
    );
  }

  if (proposal.themeChanges.length === 0) {
    return updateProposal(proposalId, {
      status: "applied",
      appliedAt: new Date().toISOString(),
    });
  }

  if (!hasLiveShopifyCredentials()) {
    // Mock mode: simulate the write so the full pipeline is exercisable without
    // real credentials, but never pretend to touch a live storefront.
    return updateProposal(proposalId, {
      status: "applied",
      appliedAt: new Date().toISOString(),
      appliedTo: {
        themeId: `mock-sandbox-theme-${randomUUID().slice(0, 8)}`,
        previewUrl: "https://example-store.myshopify.com/?preview_theme_id=mock&mock=true",
      },
    });
  }

  const theme = await findSandboxTheme();
  await upsertThemeFiles(theme.id, proposal.themeChanges);

  return updateProposal(proposalId, {
    status: "applied",
    appliedAt: new Date().toISOString(),
    appliedTo: {
      themeId: theme.id,
      previewUrl: `https://${config.shopify.storeDomain}?preview_theme_id=${theme.id.replace(/\D/g, "")}`,
    },
  });
}
