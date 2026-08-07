import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

// Point the file-backed proposal store at a throwaway directory so tests
// never touch (or depend on) a real data/ directory.
process.env.DATA_DIR = mkdtempSync(path.join(tmpdir(), "shopify-audit-mcp-test-"));
