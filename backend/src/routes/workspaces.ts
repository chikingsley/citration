import { Hono } from "hono";
import type { AppEnv } from "../types";
import { requireAuth } from "../middleware/auth";
import { generateId } from "../utils/crypto";

const RESERVED_SLUGS = new Set([
	"www",
	"api",
	"admin",
	"status",
	"support",
	"help",
	"app",
	"root",
]);

const SLUG_REGEX = /^[a-z0-9][a-z0-9-]*[a-z0-9]$/;

function validateSlug(
	slug: string
): { valid: true; normalized: string } | { valid: false; error: string } {
	const normalized = slug.trim().toLowerCase();

	if (normalized.length === 0) {
		return { valid: false, error: "Slug cannot be empty" };
	}

	if (normalized.length < 3 || normalized.length > 63) {
		return {
			valid: false,
			error: "Slug must be between 3 and 63 characters",
		};
	}

	if (!SLUG_REGEX.test(normalized)) {
		return {
			valid: false,
			error:
				"Slug must contain only lowercase letters, digits, and hyphens, and cannot start or end with a hyphen",
		};
	}

	if (RESERVED_SLUGS.has(normalized)) {
		return { valid: false, error: `"${normalized}" is a reserved word` };
	}

	return { valid: true, normalized };
}

export const workspaceRoutes = new Hono<AppEnv>();

// All workspace routes require authentication
workspaceRoutes.use("*", requireAuth);

// Create workspace
workspaceRoutes.post("/", async (c) => {
	const userId = c.get("userId");
	const body = await c.req.json<{ slug: string; displayName: string }>();

	if (!body.slug || !body.displayName) {
		return c.json(
			{
				error: "bad_request",
				message: "slug and displayName are required",
			},
			400
		);
	}

	const slugResult = validateSlug(body.slug);
	if (!slugResult.valid) {
		return c.json(
			{ error: "invalid_slug", message: slugResult.error },
			400
		);
	}

	// Check uniqueness
	const existing = await c.env.DB.prepare(
		"SELECT id FROM workspaces WHERE slug = ?"
	)
		.bind(slugResult.normalized)
		.first();

	if (existing) {
		return c.json(
			{ error: "slug_taken", message: "This workspace slug is already in use" },
			409
		);
	}

	const workspaceId = generateId();
	const displayName = body.displayName.trim();

	// Insert workspace + membership in a batch
	await c.env.DB.batch([
		c.env.DB.prepare(
			"INSERT INTO workspaces (id, slug, owner_id, display_name, created_at, updated_at) VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))"
		).bind(workspaceId, slugResult.normalized, userId, displayName),
		c.env.DB.prepare(
			"INSERT INTO workspace_members (workspace_id, user_id, role, joined_at) VALUES (?, ?, 'owner', datetime('now'))"
		).bind(workspaceId, userId),
	]);

	return c.json(
		{
			id: workspaceId,
			slug: slugResult.normalized,
			displayName,
			createdAt: new Date().toISOString(),
		},
		201
	);
});

// List user's workspaces
workspaceRoutes.get("/", async (c) => {
	const userId = c.get("userId");

	const results = await c.env.DB.prepare(
		`SELECT w.id, w.slug, w.display_name, w.created_at, wm.role
		 FROM workspaces w
		 JOIN workspace_members wm ON w.id = wm.workspace_id
		 WHERE wm.user_id = ?
		 ORDER BY w.created_at DESC`
	)
		.bind(userId)
		.all<{
			id: string;
			slug: string;
			display_name: string;
			created_at: string;
			role: string;
		}>();

	return c.json({
		workspaces: results.results.map((w) => ({
			id: w.id,
			slug: w.slug,
			displayName: w.display_name,
			role: w.role,
			createdAt: w.created_at,
		})),
	});
});

// Check slug availability
workspaceRoutes.get("/:slug/availability", async (c) => {
	const slug = c.req.param("slug");

	const slugResult = validateSlug(slug);
	if (!slugResult.valid) {
		return c.json({ available: false, reason: slugResult.error });
	}

	const existing = await c.env.DB.prepare(
		"SELECT id FROM workspaces WHERE slug = ?"
	)
		.bind(slugResult.normalized)
		.first();

	return c.json({
		available: !existing,
		slug: slugResult.normalized,
	});
});
