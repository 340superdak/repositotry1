# shopify-audit-mcp

An MCP server that audits a Shopify store against its Google Analytics 4 (GA4)
data, scores pages against industry-practice heuristics (conversion,
engagement, cart/checkout abandonment, mobile UX), and drafts change
proposals for a human to review — it never publishes anything to your live
storefront on its own.

## Safety model (read this first)

This tool follows a **propose-and-approve** design, not full autonomy:

1. `run_audit` collects data and drafts `ChangeProposal`s with `status: "pending"`.
   Nothing is written to the store at this step.
2. A human calls `approve_proposal` or `reject_proposal`. Nothing can move past
   `pending` without an explicit human decision recorded against it.
3. Only an `approved` proposal can be applied with `apply_proposal`.
4. `apply_proposal` writes theme file changes **only to an UNPUBLISHED or
   DEVELOPMENT theme**, resolved fresh from Shopify at apply time — never the
   published/live theme customers see. You still review the change in the
   Shopify admin's theme preview and publish it yourself. Setting
   `TARGET_THEME_ROLE=live` is rejected at startup.
5. Proposed theme edits are **additive**: rules only ever draft brand-new
   snippet files (e.g. `snippets/audit-trust-signals.liquid`) rather than
   rewriting existing theme code, because this tool doesn't know your theme's
   actual section structure. A human decides whether/where to `{% render %}`
   them.
6. The standalone scheduler (`npm run schedule`) only ever runs audits and
   drafts proposals — it has no code path that approves or applies anything.

If you need a different autonomy level (e.g. auto-applying low-risk changes),
treat this as the safe default to relax deliberately and explicitly, not the
starting assumption.

## What it looks at

For each key page (home, products, collections, cart, checkout) it merges:

- **From GA4**: sessions, page views, average engagement time, bounce rate,
  conversions, device (desktop/mobile/tablet) session split.
- **From Shopify Admin API**: product price, image count, page type, and
  (where available) cart/checkout abandonment rate.

... and runs a small rule engine (`src/audit/rules.ts`) encoding common
ecommerce heuristics, e.g.:

- Engaged visitors who still aren't converting on a product page → conversion/trust friction.
- Very short engagement time + high bounce on a product page → weak above-the-fold content.
- High cart or checkout abandonment vs. industry benchmarks → checkout friction.
- Mobile-dominant traffic with weak engagement → mobile UX gap.

## Setup

```bash
npm install
cp .env.example .env   # optional — leave blank to run on mock data
```

With `.env` empty (or `SHOPIFY_*` / `GA4_*` unset), everything runs against
deterministic mock fixtures in `src/mocks/fixtures.ts`, so you can exercise
the full audit → proposal → approve → apply pipeline with no real accounts.

To connect a real store:

- **Shopify**: create a custom app in your store admin with `read_products`,
  `read_content`, `read_themes`, `write_themes` scopes. Also duplicate your
  live theme once (Online Store → Themes → Actions → Duplicate) and leave it
  unpublished — that's the sandbox theme proposals get written to.
- **GA4**: create a service account in Google Cloud, grant it Viewer access
  on your GA4 property, and point `GA4_SERVICE_ACCOUNT_JSON` at its key file.

## Running

```bash
npm run build && npm start     # MCP server over stdio
npm run dev                    # same, via tsx without a build step
```

Point an MCP client (Claude Code, Claude Desktop, etc.) at `dist/index.js`
(or `src/index.ts` via `tsx` for development).

### Scheduler (unattended audits)

```bash
npm run schedule          # runs on AUDIT_CRON_SCHEDULE (default: daily 06:00 UTC)
npm run schedule:once     # run a single audit cycle immediately and exit
```

Set `NOTIFY_WEBHOOK_URL` to a Slack/Teams-style incoming webhook to get a
one-line summary posted after each scheduled audit. The scheduler never
approves or applies proposals — that queue is only drained by a human via the
MCP tools.

## MCP tools

| Tool | Purpose |
| --- | --- |
| `run_audit` | Collect data, evaluate rules, draft pending proposals |
| `get_audit_report` / `list_recent_audits` | Inspect past audits |
| `get_page_metrics` | Ad hoc raw Shopify+GA4 metrics for one or all pages |
| `list_proposals` / `get_proposal` | Inspect drafted proposals |
| `approve_proposal` / `reject_proposal` | Human review gate |
| `apply_proposal` | Write an approved proposal's theme changes to the sandbox theme |

## Development

```bash
npm run typecheck
npm test           # vitest, runs entirely against mock fixtures
npm run smoke       # builds, then drives the real server over stdio via the MCP SDK client
```

## Known limitations / next steps

- Proposal/audit persistence is a JSON file under `data/` — fine for a single
  process, not for concurrent writers. Swap `src/proposals/store.ts` for a
  real database before running this as a shared service.
- The rule set is intentionally small and threshold-based; extend
  `src/audit/rules.ts` with more signals (e.g. GA4 funnel/exploration data,
  Shopify order data) as you find them useful.
- GA4 and Shopify clients are hand-rolled `fetch` wrappers to avoid heavy SDK
  dependencies — swap in `@google-analytics/data` / `@shopify/admin-api-client`
  if you'd rather depend on the official clients.
