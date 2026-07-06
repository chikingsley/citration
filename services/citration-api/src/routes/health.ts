import type { OpenAPIHono } from "@hono/zod-openapi";
import { createRoute } from "@hono/zod-openapi";
import type { Context } from "hono";

import type { Env } from "../bindings";
import { HealthResponse, JsonErrorContent } from "./openapi-schemas";

interface AppEnv {
  Bindings: Env;
}
type App = OpenAPIHono<AppEnv>;

const healthRoute = createRoute({
  method: "get",
  path: "/health",
  responses: {
    200: {
      content: { "application/json": { schema: HealthResponse } },
      description: "Worker health.",
    },
    400: { content: JsonErrorContent, description: "Invalid request." },
  },
  summary: "Health",
  tags: ["Health"],
});

const versionedHealthRoute = createRoute({
  method: "get",
  path: "/v1/health",
  responses: {
    200: {
      content: { "application/json": { schema: HealthResponse } },
      description: "Versioned Worker health.",
    },
    400: { content: JsonErrorContent, description: "Invalid request." },
  },
  summary: "Versioned health",
  tags: ["Health"],
});

export const registerHealthRoutes = (app: App): void => {
  const handler = (c: Context<AppEnv>) =>
    c.json(
      {
        environment: c.env?.CITRATION_ENV ?? "unknown",
        ok: true,
        service: "citration-api",
      },
      200
    );

  app.openapi(healthRoute, handler);
  app.openapi(versionedHealthRoute, handler);
};
