import { createSign } from "node:crypto";
import { readFile } from "node:fs/promises";

interface ServiceAccountKey {
  client_email: string;
  private_key: string;
  token_uri?: string;
}

interface CachedToken {
  accessToken: string;
  expiresAt: number; // epoch ms
}

let cached: CachedToken | undefined;

function base64url(input: Buffer | string): string {
  return Buffer.from(input)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

/**
 * Minimal Google service-account OAuth2 (JWT bearer grant) implementation,
 * scoped to the read-only Analytics scope. Avoids pulling in google-auth-library
 * for a single grant type.
 */
export async function getGoogleAccessToken(
  serviceAccountJsonPath: string,
  scope = "https://www.googleapis.com/auth/analytics.readonly"
): Promise<string> {
  if (cached && cached.expiresAt > Date.now() + 30_000) {
    return cached.accessToken;
  }

  const raw = await readFile(serviceAccountJsonPath, "utf8");
  const key: ServiceAccountKey = JSON.parse(raw);
  const tokenUri = key.token_uri ?? "https://oauth2.googleapis.com/token";

  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claimSet = base64url(
    JSON.stringify({
      iss: key.client_email,
      scope,
      aud: tokenUri,
      iat: now,
      exp: now + 3600,
    })
  );
  const signer = createSign("RSA-SHA256");
  signer.update(`${header}.${claimSet}`);
  signer.end();
  const signature = base64url(signer.sign(key.private_key));
  const assertion = `${header}.${claimSet}.${signature}`;

  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!response.ok) {
    throw new Error(
      `Google OAuth token exchange failed: ${response.status} ${await response.text()}`
    );
  }

  const json = (await response.json()) as { access_token: string; expires_in: number };
  cached = { accessToken: json.access_token, expiresAt: Date.now() + json.expires_in * 1000 };
  return cached.accessToken;
}
