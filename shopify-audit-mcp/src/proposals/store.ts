import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { config } from "../config.js";
import type { AuditReport, ChangeProposal } from "../types.js";

const AUDITS_FILE = () => path.join(config.dataDir, "audits.json");
const PROPOSALS_FILE = () => path.join(config.dataDir, "proposals.json");

async function readJson<T>(file: string, fallback: T): Promise<T> {
  try {
    const raw = await readFile(file, "utf8");
    return JSON.parse(raw) as T;
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return fallback;
    throw err;
  }
}

async function writeJson(file: string, data: unknown): Promise<void> {
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, JSON.stringify(data, null, 2), "utf8");
}

// NOTE: this is a simple file-backed store meant for a single-process scaffold.
// It is not safe for concurrent writers -- swap for a real database before
// running this behind multiple processes or a web-facing API.

export async function saveAuditRun(report: AuditReport, proposals: ChangeProposal[]): Promise<void> {
  const audits = await readJson<AuditReport[]>(AUDITS_FILE(), []);
  audits.push(report);
  await writeJson(AUDITS_FILE(), audits);

  const existing = await readJson<ChangeProposal[]>(PROPOSALS_FILE(), []);
  existing.push(...proposals);
  await writeJson(PROPOSALS_FILE(), existing);
}

export async function listAudits(): Promise<AuditReport[]> {
  return readJson<AuditReport[]>(AUDITS_FILE(), []);
}

export async function getAudit(auditId: string): Promise<AuditReport | undefined> {
  const audits = await listAudits();
  return audits.find((a) => a.id === auditId);
}

export async function listProposals(status?: ChangeProposal["status"]): Promise<ChangeProposal[]> {
  const proposals = await readJson<ChangeProposal[]>(PROPOSALS_FILE(), []);
  return status ? proposals.filter((p) => p.status === status) : proposals;
}

export async function getProposal(proposalId: string): Promise<ChangeProposal | undefined> {
  const proposals = await listProposals();
  return proposals.find((p) => p.id === proposalId);
}

export async function updateProposal(
  proposalId: string,
  patch: Partial<ChangeProposal>
): Promise<ChangeProposal> {
  const proposals = await readJson<ChangeProposal[]>(PROPOSALS_FILE(), []);
  const index = proposals.findIndex((p) => p.id === proposalId);
  if (index === -1) throw new Error(`Proposal not found: ${proposalId}`);
  proposals[index] = { ...proposals[index], ...patch };
  await writeJson(PROPOSALS_FILE(), proposals);
  return proposals[index];
}
