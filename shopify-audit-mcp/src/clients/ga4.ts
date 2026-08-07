import { config, hasLiveGA4Credentials } from "../config.js";
import { MOCK_GA4_METRICS } from "../mocks/fixtures.js";
import type { DeviceBreakdown, GA4PageMetrics } from "../types.js";
import { getGoogleAccessToken } from "./googleAuth.js";

interface RunReportResponse {
  rows?: Array<{
    dimensionValues: Array<{ value: string }>;
    metricValues: Array<{ value: string }>;
  }>;
}

async function runReport(
  body: Record<string, unknown>
): Promise<RunReportResponse> {
  const token = await getGoogleAccessToken(config.ga4.serviceAccountJsonPath!);
  const res = await fetch(
    `https://analyticsdata.googleapis.com/v1beta/properties/${config.ga4.propertyId}:runReport`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    }
  );
  if (!res.ok) {
    throw new Error(`GA4 runReport failed: ${res.status} ${await res.text()}`);
  }
  return (await res.json()) as RunReportResponse;
}

function dateRange(lookbackDays: number) {
  return [{ startDate: `${lookbackDays}daysAgo`, endDate: "today" }];
}

/**
 * Fetches page-level engagement + conversion metrics from GA4, plus a
 * device-split session count per page. Falls back to deterministic mock
 * fixtures when no GA4 service account is configured (see config.ts).
 */
export async function fetchGA4PageMetrics(lookbackDays: number): Promise<GA4PageMetrics[]> {
  if (!hasLiveGA4Credentials()) {
    return MOCK_GA4_METRICS;
  }

  const [overall, byDevice] = await Promise.all([
    runReport({
      dateRanges: dateRange(lookbackDays),
      dimensions: [{ name: "pagePath" }],
      metrics: [
        { name: "sessions" },
        { name: "screenPageViews" },
        { name: "userEngagementDuration" },
        { name: "bounceRate" },
        { name: "conversions" },
      ],
    }),
    runReport({
      dateRanges: dateRange(lookbackDays),
      dimensions: [{ name: "pagePath" }, { name: "deviceCategory" }],
      metrics: [{ name: "sessions" }],
    }),
  ]);

  const deviceByPath = new Map<string, DeviceBreakdown>();
  for (const row of byDevice.rows ?? []) {
    const [path, device] = row.dimensionValues.map((d) => d.value);
    const sessions = Number(row.metricValues[0]?.value ?? 0);
    const existing = deviceByPath.get(path) ?? { desktop: 0, mobile: 0, tablet: 0 };
    if (device === "desktop") existing.desktop += sessions;
    else if (device === "mobile") existing.mobile += sessions;
    else if (device === "tablet") existing.tablet += sessions;
    deviceByPath.set(path, existing);
  }

  return (overall.rows ?? []).map((row) => {
    const path = row.dimensionValues[0].value;
    const [sessions, screenPageViews, engagementDuration, bounceRate, conversions] =
      row.metricValues.map((m) => Number(m.value));
    return {
      path,
      sessions,
      screenPageViews,
      averageEngagementTimeSeconds: sessions > 0 ? engagementDuration / sessions : 0,
      bounceRate,
      conversions,
      deviceSessions: deviceByPath.get(path) ?? { desktop: 0, mobile: 0, tablet: 0 },
    };
  });
}
