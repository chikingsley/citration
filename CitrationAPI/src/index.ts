import { openApiDocument } from "./openapi";

export interface Env {
  CITRATION_DB: D1Database;
  ATTACHMENTS: R2Bucket;
  CITRATION_ENV?: string;
  JWT_SIGNING_SECRET?: string;
}

type JsonValue = boolean | number | string | null | JsonValue[] | { [key: string]: JsonValue };

interface JsonResponseBody {
  [key: string]: JsonValue;
}

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8"
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, env);
  }
} satisfies ExportedHandler<Env>;

export async function handleRequest(request: Request, env?: Partial<Env>): Promise<Response> {
  const url = new URL(request.url);
  const path = normalizePath(url.pathname);

  if (request.method === "GET" && (path === "/health" || path === "/v1/health")) {
    return json({
      ok: true,
      service: "citration-api",
      environment: env?.CITRATION_ENV ?? "unknown"
    });
  }

  if (request.method === "GET" && (path === "/openapi.json" || path === "/v1/openapi.json")) {
    return json(openApiDocument);
  }

  if (path.startsWith("/v1/workspaces/") && path.includes("/sync/")) {
    return json(
      {
        error: "not_implemented",
        message: "Sync routes are specified in docs/sync-api-prd.md and reserved in OpenAPI, but not implemented yet."
      },
      { status: 501 }
    );
  }

  return json(
    {
      error: "not_found",
      message: "No route matched the request."
    },
    { status: 404 }
  );
}

function json(body: JsonResponseBody | typeof openApiDocument, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body, null, 2), {
    ...init,
    headers: {
      ...jsonHeaders,
      ...init.headers
    }
  });
}

function normalizePath(pathname: string): string {
  if (pathname.length > 1 && pathname.endsWith("/")) {
    return pathname.slice(0, -1);
  }
  return pathname;
}
