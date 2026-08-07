import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const transport = new StdioClientTransport({
  command: "node",
  args: ["dist/index.js"],
});
const client = new Client({ name: "smoke-test", version: "0.0.1" });
await client.connect(transport);

const tools = await client.listTools();
console.log("Tools:", tools.tools.map((t) => t.name).join(", "));

const audit = await client.callTool({ name: "run_audit", arguments: { lookbackDays: 28 } });
console.log("run_audit ->", audit.content[0].text);

const auditData = JSON.parse(audit.content[0].text);

const proposals = await client.callTool({ name: "list_proposals", arguments: { status: "pending" } });
const proposalList = JSON.parse(proposals.content[0].text);
console.log(`Pending proposals: ${proposalList.length}`);

const withChanges = proposalList.find((p) => p.themeChanges.length > 0);
console.log("Approving + applying:", withChanges.title);

const approved = await client.callTool({
  name: "approve_proposal",
  arguments: { proposalId: withChanges.id, reviewedBy: "smoke-test" },
});
console.log("approve_proposal ->", approved.content[0].text);

const applied = await client.callTool({ name: "apply_proposal", arguments: { proposalId: withChanges.id } });
console.log("apply_proposal ->", applied.content[0].text);

const badApply = await client.callTool({ name: "apply_proposal", arguments: { proposalId: proposalList[1].id } });
console.log("apply_proposal on non-approved (expect isError) ->", JSON.stringify(badApply));

await client.close();
