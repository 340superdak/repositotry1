import type { GA4PageMetrics, ShopifyPage, ShopifyPageFacts } from "../types.js";

// Deterministic mock data standing in for a real Shopify store + GA4 property.
// Used automatically whenever live credentials are not configured (see config.ts),
// so the whole pipeline (collect -> recommend -> propose) is exercisable end to end
// without needing real accounts.

export const MOCK_PAGES: ShopifyPage[] = [
  { id: "gid://shopify/Page/1", handle: "home", path: "/", title: "Home", type: "home" },
  {
    id: "gid://shopify/Product/101",
    handle: "aurora-wool-jacket",
    path: "/products/aurora-wool-jacket",
    title: "Aurora Wool Jacket",
    type: "product",
  },
  {
    id: "gid://shopify/Product/102",
    handle: "everyday-canvas-tote",
    path: "/products/everyday-canvas-tote",
    title: "Everyday Canvas Tote",
    type: "product",
  },
  {
    id: "gid://shopify/Collection/201",
    handle: "new-arrivals",
    path: "/collections/new-arrivals",
    title: "New Arrivals",
    type: "collection",
  },
  { id: "gid://shopify/Page/2", handle: "cart", path: "/cart", title: "Cart", type: "cart" },
  {
    id: "gid://shopify/Page/3",
    handle: "checkout",
    path: "/checkouts",
    title: "Checkout",
    type: "checkout",
  },
];

export const MOCK_GA4_METRICS: GA4PageMetrics[] = [
  {
    path: "/",
    sessions: 12000,
    screenPageViews: 15400,
    averageEngagementTimeSeconds: 38,
    bounceRate: 0.42,
    conversions: 210,
    deviceSessions: { desktop: 4800, mobile: 6600, tablet: 600 },
  },
  {
    path: "/products/aurora-wool-jacket",
    sessions: 5200,
    screenPageViews: 6100,
    averageEngagementTimeSeconds: 95,
    bounceRate: 0.31,
    conversions: 38, // ~0.73% conversion despite strong engagement time
    deviceSessions: { desktop: 1600, mobile: 3300, tablet: 300 },
  },
  {
    path: "/products/everyday-canvas-tote",
    sessions: 3100,
    screenPageViews: 3400,
    averageEngagementTimeSeconds: 12, // very low engagement time
    bounceRate: 0.68,
    conversions: 9,
    deviceSessions: { desktop: 900, mobile: 2050, tablet: 150 },
  },
  {
    path: "/collections/new-arrivals",
    sessions: 8400,
    screenPageViews: 11200,
    averageEngagementTimeSeconds: 46,
    bounceRate: 0.39,
    conversions: 0, // collection pages don't convert directly, expected
    deviceSessions: { desktop: 2900, mobile: 5000, tablet: 500 },
  },
  {
    path: "/cart",
    sessions: 1900,
    screenPageViews: 2500,
    averageEngagementTimeSeconds: 54,
    bounceRate: 0.22,
    conversions: 640,
    deviceSessions: { desktop: 700, mobile: 1100, tablet: 100 },
  },
  {
    path: "/checkouts",
    sessions: 1550,
    screenPageViews: 1980,
    averageEngagementTimeSeconds: 71,
    bounceRate: 0.18,
    conversions: 640,
    deviceSessions: { desktop: 640, mobile: 810, tablet: 100 },
  },
];

export const MOCK_SHOPIFY_FACTS: ShopifyPageFacts[] = [
  { path: "/", page: MOCK_PAGES[0] },
  {
    path: "/products/aurora-wool-jacket",
    page: MOCK_PAGES[1],
    hasProductReviews: false,
    productPriceCents: 24900,
    productImageCount: 2,
  },
  {
    path: "/products/everyday-canvas-tote",
    page: MOCK_PAGES[2],
    hasProductReviews: true,
    productPriceCents: 4800,
    productImageCount: 4,
  },
  { path: "/collections/new-arrivals", page: MOCK_PAGES[3] },
  {
    path: "/cart",
    page: MOCK_PAGES[4],
    cartAbandonmentRate: 0.66,
  },
  { path: "/checkouts", page: MOCK_PAGES[5], cartAbandonmentRate: 0.55 },
];
