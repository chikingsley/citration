# BetterCite Standard SaaS Architecture

## Decision
We are using a standard multi-tenant SaaS model:
1. Shared backend API + shared database cluster
2. Tenant/workspace isolation by `workspace_id`
3. Tenant-facing subdomains like `https://{slug}.bettercite.app`
4. DNS and tenant provisioning handled by backend services, never by desktop clients

This replaces the per-user Cloudflare Tunnel idea as the default product path.

## Why This Model
1. Predictable reliability: one controlled backend stack instead of user laptop uptime/network variability
2. Better security: no user API tokens in desktop binary, no local tunnel process to harden
3. Lower support burden: one platform to monitor, patch, rate limit, and abuse-protect
4. Easier cross-device sync: clients connect to stable API endpoints

## Tenant and Subdomain Flow
1. User signs up/logs in at central auth endpoint
2. User chooses workspace slug (for example `acme-lab`)
3. Backend validates slug and creates workspace row
4. Backend creates DNS record (or maps wildcard route) for `acme-lab.bettercite.app`
5. TLS is handled by platform edge
6. Desktop app stores `workspaceSlug` and authenticates with bearer session tokens

## Routing Pattern
1. UI host: `https://{slug}.bettercite.app`
2. API host: `https://api.bettercite.app/v1`
3. API requests include workspace context from token claims (preferred) and optional `X-Workspace-Slug` for diagnostics

## Security Baseline
1. Tokens are issued by central auth, short-lived access token + refresh token rotation
2. Desktop stores session credentials in Keychain (not plaintext files)
3. Server enforces tenant scoping on every query and mutation
4. Rate limiting at edge/API by IP + account + workspace
5. Audit logs for auth, provisioning, and destructive actions

## Cost and Abuse Guardrails
1. Per-workspace quotas (items, storage, request budgets)
2. Signup throttling + email verification for self-serve plans
3. API rate limits and burst controls
4. Optional soft limits before hard enforcement for paid plans

## Vertical Slices (Execution Order)

### VS-001 Workspace Routing Contracts
Scope:
1. Slug validation rules
2. Deterministic tenant URL construction
3. Shared models for workspace context

Done when:
1. All slug/URL edge cases are unit tested
2. App can compute stable workspace API targets from config

### VS-002 Session/Auth Foundation
Scope:
1. Auth session model
2. Session storage abstraction
3. Refresh lifecycle contract

Done when:
1. Session lifecycle unit tests pass
2. App can load/save/clear session without network calls

### VS-003 Workspace Provisioning API
Scope:
1. `POST /v1/workspaces` (create)
2. Slug availability check
3. DNS/subdomain activation job + status

Done when:
1. Create workspace returns slug + status
2. Provisioning failures are surfaced with actionable error states

### VS-004 Read Sync Loop (Downstream)
Scope:
1. Pull changes endpoint + cursor
2. Client apply-to-local pipeline
3. Initial conflict strategy (server wins for P1)

Done when:
1. Client can bootstrap local DB from remote workspace
2. Repeat pulls are idempotent and cursor-based

### VS-005 Write Sync Loop (Upstream)
Scope:
1. Push local mutations endpoint
2. Version checks and conflict response model
3. Retry/backoff policy

Done when:
1. Local edits propagate and receive canonical server state
2. Conflict cases are deterministic and tested

### VS-006 Attachment Upload + Linking
Scope:
1. Presigned upload flow
2. Attachment metadata registration
3. Download URL fetch

Done when:
1. PDF upload links to item in tenant workspace
2. Download works across devices for same account

## First Build Target For This Turn
We start with VS-001 + VS-002 foundations in code (`BCDataRemote`) while local-first P0 continues.
