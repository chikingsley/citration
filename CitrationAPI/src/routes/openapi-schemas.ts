import { z } from "@hono/zod-openapi";

const ErrorResponse = z
  .object({
    error: z.string(),
    issues: z.array(z.unknown()).optional(),
  })
  .openapi("ErrorResponse");

export const JsonErrorContent = {
  "application/json": { schema: ErrorResponse },
};

export const HealthResponse = z
  .object({
    environment: z.string(),
    ok: z.boolean(),
    service: z.string(),
  })
  .openapi("HealthResponse");

export const SyncStatusResponse = z
  .object({
    current_version: z.number().int().nonnegative(),
    library_id: z.string(),
    object_counts: z.record(z.string(), z.number().int().nonnegative()),
    server_time: z.string(),
  })
  .openapi("SyncStatusResponse");

export const SyncChangesResponse = z
  .object({
    current_version: z.number().int().nonnegative(),
    objects: z.array(
      z.object({
        body: z.record(z.string(), z.unknown()).nullable(),
        deleted_at: z.string().nullable(),
        object_id: z.string(),
        object_type: z.string(),
        updated_at: z.string(),
        version: z.number().int().nonnegative(),
      })
    ),
  })
  .openapi("SyncChangesResponse");

export const SyncBatchRequest = z
  .object({
    base_version: z.number().int().nonnegative(),
    device_id: z.string().min(1),
    idempotency_key: z.string().min(1),
    mutations: z.array(
      z.object({
        base_object_version: z.number().int().nonnegative(),
        body: z.record(z.string(), z.unknown()).nullable().optional(),
        object_id: z.string().min(1),
        object_type: z.string().min(1),
        op: z.enum(["upsert", "delete"]),
      })
    ),
  })
  .strict()
  .openapi("SyncBatchRequest");

export const SyncBatchResponse = z
  .object({
    accepted: z.array(
      z.object({
        object_id: z.string(),
        object_type: z.string(),
        version: z.number().int().nonnegative(),
      })
    ),
    conflicts: z.array(
      z.object({
        object_id: z.string(),
        object_type: z.string(),
        server_version: z.number().int().nonnegative(),
      })
    ),
    current_version: z.number().int().nonnegative(),
  })
  .openapi("SyncBatchResponse");
