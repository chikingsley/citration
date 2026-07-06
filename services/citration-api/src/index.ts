import { OpenAPIHono } from "@hono/zod-openapi";
import { apiReference } from "@scalar/hono-api-reference";

import type { Env } from "./bindings";
import { jsonError } from "./http/json";
import { registerHealthRoutes } from "./routes/health";
import { registerSyncRoutes } from "./routes/sync";

export const app = new OpenAPIHono<{ Bindings: Env }>({
  defaultHook: (result, c) =>
    result.success
      ? undefined
      : c.json(
          {
            error: "invalid request",
            issues: result.error.issues,
          },
          400
        ),
});

registerHealthRoutes(app);
registerSyncRoutes(app);

app.get(
  "/docs",
  apiReference({
    spec: { url: "/openapi.json" },
    theme: "default",
  })
);

app.doc("/openapi.json", {
  info: {
    description:
      "Citration Cloudflare Worker API for Apple-first auth, library sync, attachment storage, and future web reading.",
    title: "Citration API",
    version: "0.1.0",
  },
  openapi: "3.1.0",
  servers: [{ url: "https://api.citration.app/v1" }],
});

app.notFound(() => jsonError("not found", 404));

export default {
  fetch: app.fetch,
};
