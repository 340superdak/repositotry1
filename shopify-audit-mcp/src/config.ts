import "dotenv/config";

export interface Config {
  shopify: {
    storeDomain?: string; // e.g. "my-store.myshopify.com"
    adminAccessToken?: string;
    apiVersion: string;
  };
  ga4: {
    propertyId?: string;
    serviceAccountJsonPath?: string;
  };
  /** Draft theme edits are written here, never to the published/live theme. */
  targetThemeRole: "unpublished" | "development";
  dataDir: string;
  notifyWebhookUrl?: string;
  defaultLookbackDays: number;
}

function bool(value: string | undefined, fallback: boolean): boolean {
  if (value === undefined) return fallback;
  return value === "1" || value.toLowerCase() === "true";
}

export const config: Config = {
  shopify: {
    storeDomain: process.env.SHOPIFY_STORE_DOMAIN,
    adminAccessToken: process.env.SHOPIFY_ADMIN_ACCESS_TOKEN,
    apiVersion: process.env.SHOPIFY_API_VERSION ?? "2025-01",
  },
  ga4: {
    propertyId: process.env.GA4_PROPERTY_ID,
    serviceAccountJsonPath: process.env.GA4_SERVICE_ACCOUNT_JSON,
  },
  targetThemeRole:
    (process.env.TARGET_THEME_ROLE as Config["targetThemeRole"]) ?? "unpublished",
  dataDir: process.env.DATA_DIR ?? new URL("../data", import.meta.url).pathname,
  notifyWebhookUrl: process.env.NOTIFY_WEBHOOK_URL,
  defaultLookbackDays: Number(process.env.DEFAULT_LOOKBACK_DAYS ?? 28),
};

export function hasLiveShopifyCredentials(): boolean {
  return Boolean(config.shopify.storeDomain && config.shopify.adminAccessToken);
}

export function hasLiveGA4Credentials(): boolean {
  return Boolean(config.ga4.propertyId && config.ga4.serviceAccountJsonPath);
}

// Guardrail: this tool is only ever allowed to target draft/unpublished themes.
// If someone sets TARGET_THEME_ROLE=live in the environment, refuse to start
// rather than silently writing to the storefront customers see.
if ((process.env.TARGET_THEME_ROLE ?? "").toLowerCase() === "live") {
  throw new Error(
    "TARGET_THEME_ROLE=live is not supported. This tool only ever writes theme " +
      "changes to an unpublished/development theme so a human can preview before " +
      "publishing. Remove this setting or set it to 'unpublished' or 'development'."
  );
}
