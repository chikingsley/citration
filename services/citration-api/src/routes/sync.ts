import type { OpenAPIHono } from "@hono/zod-openapi";
import { createRoute, z } from "@hono/zod-openapi";

import type { Env } from "../bindings";
import {
  JsonErrorContent,
  SyncBatchRequest,
  SyncBatchResponse,
  SyncChangesResponse,
  SyncStatusResponse,
} from "./openapi-schemas";

type App = OpenAPIHono<{ Bindings: Env }>;

const syncStatusRoute = createRoute({
  method: "get",
  path: "/v1/libraries/{library_id}/sync/status",
  request: {
    params: z.object({
      library_id: z.string().min(1),
    }),
  },
  responses: {
    200: {
      content: { "application/json": { schema: SyncStatusResponse } },
      description: "Current sync version for a library.",
    },
    501: { content: JsonErrorContent, description: "Not implemented yet." },
  },
  summary: "Get sync status",
  tags: ["Sync"],
});

const syncChangesRoute = createRoute({
  method: "get",
  path: "/v1/libraries/{library_id}/sync/changes",
  request: {
    params: z.object({
      library_id: z.string().min(1),
    }),
    query: z.object({
      since: z.coerce.number().int().nonnegative(),
      types: z.string().optional(),
    }),
  },
  responses: {
    200: {
      content: { "application/json": { schema: SyncChangesResponse } },
      description:
        "Objects and tombstones changed after the requested version.",
    },
    501: { content: JsonErrorContent, description: "Not implemented yet." },
  },
  summary: "Get sync changes",
  tags: ["Sync"],
});

const syncBatchRoute = createRoute({
  method: "post",
  path: "/v1/libraries/{library_id}/sync/batch",
  request: {
    body: {
      content: { "application/json": { schema: SyncBatchRequest } },
      required: true,
    },
    params: z.object({
      library_id: z.string().min(1),
    }),
  },
  responses: {
    200: {
      content: { "application/json": { schema: SyncBatchResponse } },
      description: "Accepted mutations, conflicts, and new library version.",
    },
    400: { content: JsonErrorContent, description: "Invalid request." },
    409: { content: JsonErrorContent, description: "Version conflict." },
    501: { content: JsonErrorContent, description: "Not implemented yet." },
  },
  summary: "Push sync mutations",
  tags: ["Sync"],
});

export const registerSyncRoutes = (app: App): void => {
  app.openapi(syncStatusRoute, (c) =>
    c.json(
      { error: `sync status not implemented for ${c.req.param("library_id")}` },
      501
    )
  );

  app.openapi(syncChangesRoute, (c) =>
    c.json(
      {
        error: `sync changes not implemented for ${c.req.param("library_id")}`,
      },
      501
    )
  );

  app.openapi(syncBatchRoute, (c) =>
    c.json(
      { error: `sync batch not implemented for ${c.req.param("library_id")}` },
      501
    )
  );
};
