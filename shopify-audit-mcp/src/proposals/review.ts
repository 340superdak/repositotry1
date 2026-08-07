import type { ChangeProposal } from "../types.js";
import { getProposal, updateProposal } from "./store.js";

export class ReviewError extends Error {}

async function requirePending(proposalId: string): Promise<ChangeProposal> {
  const proposal = await getProposal(proposalId);
  if (!proposal) throw new ReviewError(`Proposal not found: ${proposalId}`);
  if (proposal.status !== "pending") {
    throw new ReviewError(
      `Proposal ${proposalId} is already "${proposal.status}" and can't be reviewed again.`
    );
  }
  return proposal;
}

export async function approveProposal(
  proposalId: string,
  reviewedBy?: string,
  reviewNote?: string
): Promise<ChangeProposal> {
  await requirePending(proposalId);
  return updateProposal(proposalId, {
    status: "approved",
    reviewedAt: new Date().toISOString(),
    reviewedBy,
    reviewNote,
  });
}

export async function rejectProposal(
  proposalId: string,
  reviewedBy?: string,
  reviewNote?: string
): Promise<ChangeProposal> {
  await requirePending(proposalId);
  return updateProposal(proposalId, {
    status: "rejected",
    reviewedAt: new Date().toISOString(),
    reviewedBy,
    reviewNote,
  });
}
