// Shared domain types used across the audit engine, proposal store, and MCP tools.

export interface ShopifyPage {
  id: string;
  handle: string;
  path: string;
  title: string;
  type: "home" | "product" | "collection" | "cart" | "checkout" | "page" | "blog";
  templateSuffix?: string;
}

export interface DeviceBreakdown {
  desktop: number;
  mobile: number;
  tablet: number;
}

/** Raw GA4 metrics for a single page/path over a lookback window. */
export interface GA4PageMetrics {
  path: string;
  sessions: number;
  screenPageViews: number;
  averageEngagementTimeSeconds: number;
  bounceRate: number; // 0..1
  conversions: number; // purchase events attributed to sessions that viewed this page
  deviceSessions: DeviceBreakdown;
}

/** Shopify-side facts about a page (independent of analytics). */
export interface ShopifyPageFacts {
  path: string;
  page: ShopifyPage;
  hasProductReviews?: boolean;
  productPriceCents?: number;
  productImageCount?: number;
  cartAbandonmentRate?: number; // 0..1, only meaningful for cart/checkout
}

/** Merged, analysis-ready record for one page. */
export interface PageMetrics {
  path: string;
  page: ShopifyPage;
  ga4: GA4PageMetrics;
  shopify: ShopifyPageFacts;
  conversionRate: number; // conversions / sessions, 0..1
}

export type RecommendationSeverity = "low" | "medium" | "high";

export type ProposalRiskLevel = "low" | "medium" | "high";

/** A concrete, machine-applicable change (currently: a theme asset/file upsert). */
export interface ThemeFileChange {
  /** Path within the theme, e.g. "sections/hero.liquid" or "templates/product.json". */
  filePath: string;
  /** Full new file content, or a JSON-merge patch for *.json section/template files. */
  newContent: string;
  previousContent?: string;
  description: string;
}

export interface ChangeProposal {
  id: string;
  auditId: string;
  createdAt: string;
  recommendationId: string;
  title: string;
  rationale: string;
  evidence: string[];
  riskLevel: ProposalRiskLevel;
  /** Theme file edits this proposal would make. Empty for copy/strategy-only recommendations. */
  themeChanges: ThemeFileChange[];
  status: "pending" | "approved" | "rejected" | "applied";
  reviewedAt?: string;
  reviewedBy?: string;
  reviewNote?: string;
  appliedAt?: string;
  /** Populated once applied: the (non-live, draft) theme id/preview URL the change was written to. */
  appliedTo?: {
    themeId: string;
    previewUrl: string;
  };
}

export interface Recommendation {
  id: string;
  path: string;
  title: string;
  category:
    | "conversion"
    | "engagement"
    | "mobile-ux"
    | "checkout"
    | "content"
    | "performance";
  severity: RecommendationSeverity;
  rationale: string;
  evidence: string[];
  suggestedThemeChanges: ThemeFileChange[];
}

export interface AuditReport {
  id: string;
  createdAt: string;
  lookbackDays: number;
  pagesAnalyzed: number;
  recommendations: Recommendation[];
}
