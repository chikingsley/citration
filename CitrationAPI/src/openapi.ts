export const openApiDocument = {
  openapi: "3.1.0",
  info: {
    title: "Citration API",
    version: "0.1.0",
    summary: "Cloudflare Worker API for Citration auth, workspaces, sync, and attachments"
  },
  servers: [
    {
      url: "https://api.citration.app/v1"
    }
  ],
  paths: {
    "/health": {
      get: {
        operationId: "getHealth",
        summary: "Check API health",
        responses: {
          "200": {
            description: "The Worker is reachable"
          }
        }
      }
    },
    "/workspaces/{slug}/sync/status": {
      get: {
        operationId: "getSyncStatus",
        summary: "Return the current workspace sync version",
        parameters: [
          {
            name: "slug",
            in: "path",
            required: true,
            schema: { type: "string" }
          }
        ],
        responses: {
          "501": {
            description: "Planned route; not implemented in this scaffold"
          }
        }
      }
    },
    "/workspaces/{slug}/sync/changes": {
      get: {
        operationId: "getSyncChanges",
        summary: "Pull changed objects after a workspace version",
        parameters: [
          {
            name: "slug",
            in: "path",
            required: true,
            schema: { type: "string" }
          },
          {
            name: "since",
            in: "query",
            required: true,
            schema: { type: "integer", minimum: 0 }
          }
        ],
        responses: {
          "501": {
            description: "Planned route; not implemented in this scaffold"
          }
        }
      }
    },
    "/workspaces/{slug}/sync/batch": {
      post: {
        operationId: "postSyncBatch",
        summary: "Push idempotent local object mutations",
        parameters: [
          {
            name: "slug",
            in: "path",
            required: true,
            schema: { type: "string" }
          }
        ],
        responses: {
          "501": {
            description: "Planned route; not implemented in this scaffold"
          }
        }
      }
    }
  }
} as const;
