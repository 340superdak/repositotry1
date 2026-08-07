import { fetchShopifyPageFacts, listShopifyPages } from "../clients/shopify.js";
import { fetchGA4PageMetrics } from "../clients/ga4.js";
import type { GA4PageMetrics, PageMetrics } from "../types.js";

function emptyGA4(path: string): GA4PageMetrics {
  return {
    path,
    sessions: 0,
    screenPageViews: 0,
    averageEngagementTimeSeconds: 0,
    bounceRate: 0,
    conversions: 0,
    deviceSessions: { desktop: 0, mobile: 0, tablet: 0 },
  };
}

/** Joins Shopify page/product facts with GA4 engagement + conversion data, per page. */
export async function collectPageMetrics(lookbackDays: number): Promise<PageMetrics[]> {
  const pages = await listShopifyPages();
  const [facts, ga4Metrics] = await Promise.all([
    fetchShopifyPageFacts(pages),
    fetchGA4PageMetrics(lookbackDays),
  ]);

  const ga4ByPath = new Map(ga4Metrics.map((m) => [m.path, m]));
  const factsByPath = new Map(facts.map((f) => [f.path, f]));

  return pages.map((page) => {
    const ga4 = ga4ByPath.get(page.path) ?? emptyGA4(page.path);
    const shopify = factsByPath.get(page.path) ?? { path: page.path, page };
    return {
      path: page.path,
      page,
      ga4,
      shopify,
      conversionRate: ga4.sessions > 0 ? ga4.conversions / ga4.sessions : 0,
    };
  });
}
