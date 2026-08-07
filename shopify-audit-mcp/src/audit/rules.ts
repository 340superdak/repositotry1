import { randomUUID } from "node:crypto";
import type { PageMetrics, Recommendation, ThemeFileChange } from "../types.js";

type Rule = (metrics: PageMetrics) => Recommendation | null;

function rec(
  metrics: PageMetrics,
  fields: Omit<Recommendation, "id" | "path">
): Recommendation {
  return { id: randomUUID(), path: metrics.path, ...fields };
}

/**
 * New, additive snippet files are the only kind of theme change these rules
 * propose automatically: they can't clobber content in an existing section
 * because they don't exist yet. A merchant/theme developer still has to
 * decide where (if anywhere) to {% render %} them -- this pipeline never
 * rewires templates on its own.
 */
function trustSignalsSnippet(): ThemeFileChange {
  return {
    filePath: "snippets/audit-trust-signals.liquid",
    description:
      "New snippet with trust-building copy (secure checkout, free returns, shipping ETA) " +
      "for merchandisers to render near the buy box. Not wired into any template automatically.",
    newContent: `{% comment %}
  Proposed by shopify-audit-mcp. Review the copy below, then add
  {% render 'audit-trust-signals' %} near your add-to-cart button if you want it live.
{% endcomment %}
<div class="audit-trust-signals">
  <p>🔒 Secure checkout</p>
  <p>↩️ Free 30-day returns</p>
  <p>🚚 Ships in 1-2 business days</p>
</div>
`,
  };
}

function cartReassuranceSnippet(): ThemeFileChange {
  return {
    filePath: "snippets/audit-cart-reassurance.liquid",
    description:
      "New snippet with a free-shipping progress message and security badge for the cart page.",
    newContent: `{% comment %}
  Proposed by shopify-audit-mcp. Review, then render inside your cart template if desired.
{% endcomment %}
<div class="audit-cart-reassurance">
  <p>You're close to free shipping! Add a few more items to qualify.</p>
  <p>🔒 Payment is encrypted and secure.</p>
</div>
`,
  };
}

const productConversionGap: Rule = (m) => {
  if (m.page.type !== "product") return null;
  if (m.ga4.sessions < 500) return null;
  if (m.ga4.averageEngagementTimeSeconds < 60) return null;
  if (m.conversionRate >= 0.015) return null;

  return rec(m, {
    title: `Engaged visitors aren't converting on ${m.page.title}`,
    category: "conversion",
    severity: "high",
    rationale:
      "Visitors spend real time on this page (average engagement above 60s) but purchase at " +
      `${(m.conversionRate * 100).toFixed(2)}%, well under the ~2-3% typical ecommerce product-page ` +
      "conversion rate. That combination usually points to friction near the buy decision " +
      "(trust, price framing, shipping/returns clarity) rather than a traffic-quality problem.",
    evidence: [
      `${m.ga4.sessions} sessions, ${m.ga4.averageEngagementTimeSeconds.toFixed(0)}s avg engagement time`,
      `${(m.conversionRate * 100).toFixed(2)}% conversion rate`,
      m.shopify.hasProductReviews === false ? "No product reviews displayed" : "",
      m.shopify.productImageCount !== undefined
        ? `${m.shopify.productImageCount} product image(s)`
        : "",
    ].filter(Boolean),
    suggestedThemeChanges: [trustSignalsSnippet()],
  });
};

const productLowEngagement: Rule = (m) => {
  if (m.page.type !== "product") return null;
  if (m.ga4.averageEngagementTimeSeconds >= 20) return null;
  if (m.ga4.bounceRate <= 0.6) return null;

  return rec(m, {
    title: `Visitors bounce almost immediately from ${m.page.title}`,
    category: "content",
    severity: "medium",
    rationale:
      `Average engagement time is only ${m.ga4.averageEngagementTimeSeconds.toFixed(0)}s with a ` +
      `${(m.ga4.bounceRate * 100).toFixed(0)}% bounce rate, suggesting the page isn't giving visitors ` +
      "enough above-the-fold reason to stay -- commonly thin imagery, missing pricing/shipping " +
      "context, or a slow-loading hero.",
    evidence: [
      `${m.ga4.averageEngagementTimeSeconds.toFixed(0)}s avg engagement time`,
      `${(m.ga4.bounceRate * 100).toFixed(0)}% bounce rate`,
      m.shopify.productImageCount !== undefined
        ? `Only ${m.shopify.productImageCount} product image(s) -- 4+ is a common baseline`
        : "",
    ].filter(Boolean),
    suggestedThemeChanges: [],
  });
};

const cartAbandonmentHigh: Rule = (m) => {
  if (m.page.type !== "cart") return null;
  if (m.shopify.cartAbandonmentRate === undefined || m.shopify.cartAbandonmentRate <= 0.6) {
    return null;
  }

  return rec(m, {
    title: "Cart abandonment is above the typical ecommerce range",
    category: "checkout",
    severity: "high",
    rationale:
      `Cart abandonment is ${(m.shopify.cartAbandonmentRate * 100).toFixed(0)}%, above the ~60-70% ` +
      "industry range. Common causes worth checking: unexpected shipping costs revealed late, " +
      "forced account creation, or insufficient trust signals at the point customers commit to buy.",
    evidence: [`${(m.shopify.cartAbandonmentRate * 100).toFixed(0)}% cart abandonment rate`],
    suggestedThemeChanges: [cartReassuranceSnippet()],
  });
};

const checkoutFriction: Rule = (m) => {
  if (m.page.type !== "checkout") return null;
  if (m.shopify.cartAbandonmentRate === undefined || m.shopify.cartAbandonmentRate <= 0.45) {
    return null;
  }

  return rec(m, {
    title: "Checkout drop-off suggests friction in the payment flow",
    category: "checkout",
    severity: "medium",
    rationale:
      `${(m.shopify.cartAbandonmentRate * 100).toFixed(0)}% of checkout sessions don't complete. ` +
      "Consider enabling express/accelerated payment options (Shop Pay, PayPal, Apple Pay) and " +
      "surfacing security badges near the payment fields -- both are checkout-conversion best " +
      "practices this tool can't safely automate since they involve payment settings.",
    evidence: [`${(m.shopify.cartAbandonmentRate * 100).toFixed(0)}% checkout drop-off`],
    suggestedThemeChanges: [],
  });
};

const mobileEngagementGap: Rule = (m) => {
  const total = m.ga4.deviceSessions.desktop + m.ga4.deviceSessions.mobile + m.ga4.deviceSessions.tablet;
  if (total === 0) return null;
  const mobileShare = m.ga4.deviceSessions.mobile / total;
  if (mobileShare < 0.55) return null;
  if (m.ga4.averageEngagementTimeSeconds >= 30) return null;

  return rec(m, {
    title: `Mobile traffic dominates ${m.page.title} but engagement is weak`,
    category: "mobile-ux",
    severity: "medium",
    rationale:
      `${(mobileShare * 100).toFixed(0)}% of sessions on this page are mobile, but average ` +
      `engagement time is only ${m.ga4.averageEngagementTimeSeconds.toFixed(0)}s. Worth a manual ` +
      "mobile-specific UX pass: tap-target sizing, a sticky add-to-cart bar, and simplified " +
      "above-the-fold layout are common fixes -- these are structural/CSS changes best reviewed " +
      "by a person rather than auto-generated.",
    evidence: [
      `${(mobileShare * 100).toFixed(0)}% mobile session share`,
      `${m.ga4.averageEngagementTimeSeconds.toFixed(0)}s avg engagement time`,
    ],
    suggestedThemeChanges: [],
  });
};

export const RULES: Rule[] = [
  productConversionGap,
  productLowEngagement,
  cartAbandonmentHigh,
  checkoutFriction,
  mobileEngagementGap,
];
