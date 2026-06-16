#!/usr/bin/env node

// Cross-platform Claude Usage Fetcher
// Outputs: fhUtil|fhReset|sdUtil|sdReset
// Errors:  ERROR:<message>

const https = require("https");

function readSessionKey() {
  // Session key injected by Claude Usage app
  const injectedKey = "<YOUR_SESSION>";
  const trimmed = injectedKey.trim();
  return trimmed || null;
}

function readOrganizationId() {
  // Organization ID injected from settings by Claude Usage app
  const injectedOrgId = "<YOUR_ORG_ID>";
  const trimmed = injectedOrgId.trim();
  return trimmed || null;
}

function fetchUsageData(sessionKey, orgId) {
  return new Promise((resolve, reject) => {
    // Validate orgId doesn't contain path traversal
    if (orgId.includes("..") || orgId.includes("/")) {
      return reject(new Error("Invalid organization ID"));
    }

    const options = {
      hostname: "claude.ai",
      path: `/api/organizations/${orgId}/usage`,
      method: "GET",
      headers: {
        Cookie: `sessionKey=${sessionKey}`,
        Accept: "application/json",
      },
    };

    const req = https.request(options, (res) => {
      let body = "";
      res.on("data", (chunk) => (body += chunk));
      res.on("end", () => {
        if (res.statusCode !== 200) {
          return reject(new Error("Failed to fetch usage"));
        }

        try {
          const json = JSON.parse(body);

          let fhUtil = 0,
            fhReset = "",
            sdUtil = 0,
            sdReset = "";

          if (json.five_hour) {
            fhUtil = json.five_hour.utilization ?? 0;
            fhReset = json.five_hour.resets_at ?? "";
          }

          if (json.seven_day) {
            sdUtil = json.seven_day.utilization ?? 0;
            sdReset = json.seven_day.resets_at ?? "";
          }

          resolve({ fhUtil, fhReset, sdUtil, sdReset });
        } catch {
          reject(new Error("Invalid response format"));
        }
      });
    });

    req.on("error", (err) => reject(err));
    req.end();
  });
}

// Main
(async () => {
  const sessionKey = readSessionKey();
  if (!sessionKey) {
    console.log("ERROR:NO_SESSION_KEY");
    process.exit(1);
  }

  const orgId = readOrganizationId();
  if (!orgId) {
    console.log("ERROR:NO_ORG_CONFIGURED");
    process.exit(1);
  }

  try {
    const { fhUtil, fhReset, sdUtil, sdReset } = await fetchUsageData(
      sessionKey,
      orgId
    );
    console.log(`${fhUtil}|${fhReset}|${sdUtil}|${sdReset}`);
    process.exit(0);
  } catch (err) {
    console.log(`ERROR:${err.message}`);
    process.exit(1);
  }
})();
