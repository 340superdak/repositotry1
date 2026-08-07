import { describe, expect, it } from "vitest";
import { RULES } from "../src/audit/rules.js";
import type { PageMetrics, ShopifyPage } from "../src/types.js";

function page(overrides: Partial<ShopifyPage> = {}): ShopifyPage {
  return { id: "1", handle: "test", path: "/products/test", title: "Test", type: "product", ...overrides };
}

function metrics(overrides: Partial<PageMetrics> = {}): PageMetrics {
  const p = overrides.page ?? page();
  return {
    path: p.path,
    page: p,
    ga4: {
      path: p.path,
      sessions: 1000,
      screenPageViews: 1200,
      averageEngagementTimeSeconds: 45,
      bounceRate: 0.4,
      conversions: 20,
      deviceSessions: { desktop: 500, mobile: 400, tablet: 100 },
      ...overrides.ga4,
    },
    shopify: { path: p.path, page: p, ...overrides.shopify },
    conversionRate: overrides.conversionRate ?? 0.02,
  };
}

function fire(m: PageMetrics) {
  return RULES.map((r) => r(m)).filter((r): r is NonNullable<typeof r> => r !== null);
}

describe("productConversionGap", () => {
  it("fires when engaged traffic doesn't convert", () => {
    const m = metrics({
      ga4: {
        path: "/products/test",
        sessions: 1000,
        screenPageViews: 1200,
        averageEngagementTimeSeconds: 90,
        bounceRate: 0.3,
        conversions: 5,
        deviceSessions: { desktop: 500, mobile: 400, tablet: 100 },
      },
      conversionRate: 0.005,
    });
    const results = fire(m);
    expect(results.some((r) => r.category === "conversion")).toBe(true);
  });

  it("does not fire below the session threshold", () => {
    const m = metrics({ ga4: { path: "/products/test", sessions: 10, screenPageViews: 12, averageEngagementTimeSeconds: 90, bounceRate: 0.3, conversions: 0, deviceSessions: { desktop: 5, mobile: 5, tablet: 0 } }, conversionRate: 0 });
    expect(fire(m).some((r) => r.category === "conversion")).toBe(false);
  });

  it("does not fire for non-product pages", () => {
    const m = metrics({
      page: page({ type: "collection", path: "/collections/test" }),
      ga4: { path: "/collections/test", sessions: 1000, screenPageViews: 1200, averageEngagementTimeSeconds: 90, bounceRate: 0.3, conversions: 5, deviceSessions: { desktop: 500, mobile: 400, tablet: 100 } },
      conversionRate: 0.005,
    });
    expect(fire(m).some((r) => r.category === "conversion")).toBe(false);
  });
});

describe("productLowEngagement", () => {
  it("fires on fast bounces with low engagement time", () => {
    const m = metrics({
      ga4: { path: "/products/test", sessions: 500, screenPageViews: 600, averageEngagementTimeSeconds: 10, bounceRate: 0.7, conversions: 2, deviceSessions: { desktop: 200, mobile: 250, tablet: 50 } },
    });
    expect(fire(m).some((r) => r.title.includes("bounce"))).toBe(true);
  });
});

describe("cartAbandonmentHigh", () => {
  it("fires above the abandonment threshold on the cart page", () => {
    const m = metrics({
      page: page({ type: "cart", path: "/cart" }),
      shopify: { path: "/cart", page: page({ type: "cart", path: "/cart" }), cartAbandonmentRate: 0.75 },
    });
    const results = fire(m);
    expect(results.some((r) => r.category === "checkout")).toBe(true);
    expect(results.find((r) => r.category === "checkout")?.suggestedThemeChanges.length).toBeGreaterThan(0);
  });

  it("does not fire below the threshold", () => {
    const m = metrics({
      page: page({ type: "cart", path: "/cart" }),
      shopify: { path: "/cart", page: page({ type: "cart", path: "/cart" }), cartAbandonmentRate: 0.4 },
    });
    expect(fire(m)).toHaveLength(0);
  });
});

describe("mobileEngagementGap", () => {
  it("fires when mobile-dominant traffic engages poorly", () => {
    const m = metrics({
      ga4: { path: "/products/test", sessions: 1000, screenPageViews: 1200, averageEngagementTimeSeconds: 10, bounceRate: 0.5, conversions: 20, deviceSessions: { desktop: 300, mobile: 650, tablet: 50 } },
    });
    expect(fire(m).some((r) => r.category === "mobile-ux")).toBe(true);
  });
});

describe("suggested theme changes are additive-only", () => {
  it("never overwrites existing content -- new snippet files with no previousContent", () => {
    const m = metrics({
      ga4: { path: "/products/test", sessions: 1000, screenPageViews: 1200, averageEngagementTimeSeconds: 90, bounceRate: 0.3, conversions: 5, deviceSessions: { desktop: 500, mobile: 400, tablet: 100 } },
      conversionRate: 0.005,
    });
    const results = fire(m);
    for (const r of results) {
      for (const change of r.suggestedThemeChanges) {
        expect(change.previousContent).toBeUndefined();
        expect(change.filePath.startsWith("snippets/audit-")).toBe(true);
      }
    }
  });
});
