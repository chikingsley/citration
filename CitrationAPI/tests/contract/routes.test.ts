import { describe, expect, it } from "vitest";

import { app } from "../../src";

interface OpenApiDocument {
  info: { title: string };
  openapi: string;
  paths: Record<string, unknown>;
}

interface ErrorResponse {
  error: string;
  issues?: unknown[];
}

const jsonAs = async <T>(response: Response): Promise<T> =>
  (await response.json()) as T;

describe("route contracts", () => {
  it("exposes health", async () => {
    const response = await app.request("/health");
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      environment: "unknown",
      ok: true,
      service: "citration-api",
    });
  });

  it("exposes OpenAPI JSON with sync routes", async () => {
    const response = await app.request("/openapi.json");
    expect(response.status).toBe(200);
    const body = await jsonAs<OpenApiDocument>(response);
    expect(body.info.title).toBe("Citration API");
    expect(body.openapi).toBe("3.1.0");
    expect(Object.keys(body.paths)).toContain(
      "/v1/libraries/{library_id}/sync/status"
    );
    expect(Object.keys(body.paths)).toContain(
      "/v1/libraries/{library_id}/sync/batch"
    );
  });

  it("exposes Scalar API docs", async () => {
    const response = await app.request("/docs");
    expect(response.status).toBe(200);
    await expect(response.text()).resolves.toContain("/openapi.json");
  });

  it("reserved sync routes fail explicitly", async () => {
    const response = await app.request("/v1/libraries/personal/sync/status");
    expect(response.status).toBe(501);
    const body = await jsonAs<ErrorResponse>(response);
    expect(body.error).toContain("not implemented");
  });

  it("rejects invalid sync batch input through Zod", async () => {
    const response = await app.request("/v1/libraries/personal/sync/batch", {
      body: JSON.stringify({ mutations: [] }),
      headers: { "content-type": "application/json" },
      method: "POST",
    });
    expect(response.status).toBe(400);
    const body = await jsonAs<ErrorResponse>(response);
    expect(body.error).toBe("invalid request");
    expect(body.issues?.length).toBeGreaterThan(0);
  });

  it("unknown routes return JSON 404", async () => {
    const response = await app.request("/v1/missing");
    expect(response.status).toBe(404);
    await expect(response.json()).resolves.toEqual({ error: "not found" });
  });
});
