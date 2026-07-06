import assert from "node:assert/strict";
import test from "node:test";

import { handleRequest } from "../src/index";

test("health route returns service metadata", async () => {
  const response = await handleRequest(new Request("https://api.citration.app/health"), {
    CITRATION_ENV: "test"
  });
  const body = await response.json() as { ok: boolean; service: string; environment: string };

  assert.equal(response.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.service, "citration-api");
  assert.equal(body.environment, "test");
});

test("versioned OpenAPI route returns the Citration API document", async () => {
  const response = await handleRequest(new Request("https://api.citration.app/v1/openapi.json"));
  const body = await response.json() as { openapi: string; info: { title: string } };

  assert.equal(response.status, 200);
  assert.equal(body.openapi, "3.1.0");
  assert.equal(body.info.title, "Citration API");
});

test("reserved sync routes fail explicitly", async () => {
  const response = await handleRequest(
    new Request("https://api.citration.app/v1/workspaces/acme/sync/status")
  );
  const body = await response.json() as { error: string };

  assert.equal(response.status, 501);
  assert.equal(body.error, "not_implemented");
});

test("unknown routes return JSON 404", async () => {
  const response = await handleRequest(new Request("https://api.citration.app/v1/missing"));
  const body = await response.json() as { error: string };

  assert.equal(response.status, 404);
  assert.equal(body.error, "not_found");
});
