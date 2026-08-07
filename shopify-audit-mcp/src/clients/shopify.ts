import { config, hasLiveShopifyCredentials } from "../config.js";
import { MOCK_PAGES, MOCK_SHOPIFY_FACTS } from "../mocks/fixtures.js";
import type { ShopifyPage, ShopifyPageFacts, ThemeFileChange } from "../types.js";

interface GraphQLResponse<T> {
  data?: T;
  errors?: Array<{ message: string }>;
}

async function shopifyGraphQL<T>(
  query: string,
  variables?: Record<string, unknown>
): Promise<T> {
  const url = `https://${config.shopify.storeDomain}/admin/api/${config.shopify.apiVersion}/graphql.json`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Shopify-Access-Token": config.shopify.adminAccessToken!,
    },
    body: JSON.stringify({ query, variables }),
  });
  if (!res.ok) {
    throw new Error(`Shopify Admin API HTTP ${res.status}: ${await res.text()}`);
  }
  const json = (await res.json()) as GraphQLResponse<T>;
  if (json.errors?.length) {
    throw new Error(`Shopify Admin API error: ${json.errors.map((e) => e.message).join("; ")}`);
  }
  return json.data as T;
}

/** Lists storefront pages worth auditing: home, products, collections, cart, checkout. */
export async function listShopifyPages(): Promise<ShopifyPage[]> {
  if (!hasLiveShopifyCredentials()) {
    return MOCK_PAGES;
  }

  const data = await shopifyGraphQL<{
    products: { nodes: Array<{ id: string; handle: string; title: string }> };
    collections: { nodes: Array<{ id: string; handle: string; title: string }> };
  }>(`
    query AuditablePages {
      products(first: 100) { nodes { id handle title } }
      collections(first: 50) { nodes { id handle title } }
    }
  `);

  const pages: ShopifyPage[] = [
    { id: "home", handle: "home", path: "/", title: "Home", type: "home" },
    { id: "cart", handle: "cart", path: "/cart", title: "Cart", type: "cart" },
    { id: "checkout", handle: "checkout", path: "/checkouts", title: "Checkout", type: "checkout" },
  ];
  for (const p of data.products.nodes) {
    pages.push({ id: p.id, handle: p.handle, path: `/products/${p.handle}`, title: p.title, type: "product" });
  }
  for (const c of data.collections.nodes) {
    pages.push({ id: c.id, handle: c.handle, path: `/collections/${c.handle}`, title: c.title, type: "collection" });
  }
  return pages;
}

/** Fetches Shopify-side facts (price, image count, etc.) for a set of pages. */
export async function fetchShopifyPageFacts(pages: ShopifyPage[]): Promise<ShopifyPageFacts[]> {
  if (!hasLiveShopifyCredentials()) {
    return MOCK_SHOPIFY_FACTS;
  }

  const productPages = pages.filter((p) => p.type === "product");
  const facts: ShopifyPageFacts[] = pages.map((page) => ({ path: page.path, page }));

  if (productPages.length > 0) {
    const data = await shopifyGraphQL<{ nodes: Array<{
      id: string;
      priceRangeV2: { minVariantPrice: { amount: string } };
      images: { nodes: unknown[] };
    } | null> }>(
      `query ProductFacts($ids: [ID!]!) {
        nodes(ids: $ids) {
          ... on Product {
            id
            priceRangeV2 { minVariantPrice { amount } }
            images(first: 10) { nodes { id } }
          }
        }
      }`,
      { ids: productPages.map((p) => p.id) }
    );
    for (const node of data.nodes) {
      if (!node) continue;
      const page = productPages.find((p) => p.id === node.id);
      if (!page) continue;
      const fact = facts.find((f) => f.path === page.path);
      if (fact) {
        fact.productPriceCents = Math.round(Number(node.priceRangeV2.minVariantPrice.amount) * 100);
        fact.productImageCount = node.images.nodes.length;
      }
    }
  }

  return facts;
}

interface ShopifyTheme {
  id: string;
  name: string;
  role: "MAIN" | "UNPUBLISHED" | "DEVELOPMENT" | "DEMO";
}

/**
 * Finds a non-live theme to write proposed changes to. Never returns the MAIN
 * (published/live) theme -- see config.ts's TARGET_THEME_ROLE guardrail. If no
 * suitable sandbox theme exists, this throws with instructions rather than
 * silently falling back to the live theme.
 */
export async function findSandboxTheme(): Promise<ShopifyTheme> {
  const data = await shopifyGraphQL<{ themes: { nodes: ShopifyTheme[] } }>(`
    query Themes {
      themes(first: 20) { nodes { id name role } }
    }
  `);
  const wanted = config.targetThemeRole.toUpperCase();
  const match = data.themes.nodes.find((t) => t.role === wanted);
  if (!match) {
    throw new Error(
      `No theme with role "${wanted}" found. Create a duplicate of your live theme in the ` +
        `Shopify admin (Online Store > Themes > Actions > Duplicate) and leave it unpublished, ` +
        `so proposals have a safe place to land for preview before you publish them.`
    );
  }
  return match;
}

/** Writes theme file changes to the given (non-live) theme via themeFilesUpsert. */
export async function upsertThemeFiles(
  themeId: string,
  changes: ThemeFileChange[]
): Promise<void> {
  const data = await shopifyGraphQL<{
    themeFilesUpsert: { userErrors: Array<{ message: string }> };
  }>(
    `mutation UpsertThemeFiles($themeId: ID!, $files: [OnlineStoreThemeFilesUpsertFileInput!]!) {
      themeFilesUpsert(themeId: $themeId, files: $files) {
        userErrors { message }
      }
    }`,
    {
      themeId,
      files: changes.map((c) => ({ filename: c.filePath, body: { type: "TEXT", value: c.newContent } })),
    }
  );
  if (data.themeFilesUpsert.userErrors.length > 0) {
    throw new Error(
      `themeFilesUpsert failed: ${data.themeFilesUpsert.userErrors.map((e) => e.message).join("; ")}`
    );
  }
}
