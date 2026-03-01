import { Hono } from "hono";
import type { AppEnv } from "../types";
import { requireAuth } from "../middleware/auth";
import { verifyAppleIdentityToken } from "../utils/apple-jwks";
import { signAccessToken } from "../utils/jwt";
import { generateId, generateRefreshToken, hashToken } from "../utils/crypto";

export const authRoutes = new Hono<AppEnv>();

// Exchange Apple identity token for access + refresh tokens
authRoutes.post("/apple", async (c) => {
	const body = await c.req.json<{ identityToken: string }>();
	if (!body.identityToken) {
		return c.json({ error: "bad_request", message: "identityToken is required" }, 400);
	}

	// Verify Apple identity token
	const appleClaims = await verifyAppleIdentityToken(
		body.identityToken,
		c.env.APPLE_SERVICE_ID
	);

	// Upsert user by Apple user ID
	const existingUser = await c.env.DB.prepare(
		"SELECT id, email, display_name FROM users WHERE apple_user_id = ?"
	)
		.bind(appleClaims.sub)
		.first<{ id: string; email: string | null; display_name: string | null }>();

	let userId: string;
	let userEmail = appleClaims.email ?? null;
	let userDisplayName: string | null = null;

	if (existingUser) {
		userId = existingUser.id;
		userEmail = appleClaims.email ?? existingUser.email;
		userDisplayName = existingUser.display_name;

		// Update email if Apple provided a new one
		if (appleClaims.email && appleClaims.email !== existingUser.email) {
			await c.env.DB.prepare(
				"UPDATE users SET email = ?, updated_at = datetime('now') WHERE id = ?"
			)
				.bind(appleClaims.email, userId)
				.run();
		}
	} else {
		userId = generateId();
		await c.env.DB.prepare(
			"INSERT INTO users (id, apple_user_id, email, created_at, updated_at) VALUES (?, ?, ?, datetime('now'), datetime('now'))"
		)
			.bind(userId, appleClaims.sub, userEmail)
			.run();
	}

	// Generate tokens
	const { token: accessToken, expiresAt } = await signAccessToken(
		userId,
		c.env.JWT_SECRET,
		c.env.JWT_ISSUER
	);

	const refreshTokenRaw = generateRefreshToken();
	const refreshTokenHash = await hashToken(refreshTokenRaw);
	const refreshExpiresAt = new Date(
		Date.now() + 30 * 24 * 60 * 60 * 1000
	).toISOString();

	await c.env.DB.prepare(
		"INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at, created_at) VALUES (?, ?, ?, ?, datetime('now'))"
	)
		.bind(generateId(), userId, refreshTokenHash, refreshExpiresAt)
		.run();

	return c.json({
		accessToken,
		refreshToken: refreshTokenRaw,
		expiresAt: expiresAt.toISOString(),
		user: {
			id: userId,
			email: userEmail,
			displayName: userDisplayName,
		},
	});
});

// Exchange refresh token for new access + refresh tokens
authRoutes.post("/refresh", async (c) => {
	const body = await c.req.json<{ refreshToken: string }>();
	if (!body.refreshToken) {
		return c.json({ error: "bad_request", message: "refreshToken is required" }, 400);
	}

	const tokenHash = await hashToken(body.refreshToken);

	const storedToken = await c.env.DB.prepare(
		"SELECT id, user_id, expires_at, revoked_at FROM refresh_tokens WHERE token_hash = ?"
	)
		.bind(tokenHash)
		.first<{
			id: string;
			user_id: string;
			expires_at: string;
			revoked_at: string | null;
		}>();

	if (!storedToken) {
		return c.json({ error: "unauthorized", message: "Invalid refresh token" }, 401);
	}

	if (storedToken.revoked_at) {
		return c.json({ error: "unauthorized", message: "Refresh token has been revoked" }, 401);
	}

	if (new Date(storedToken.expires_at) <= new Date()) {
		return c.json({ error: "unauthorized", message: "Refresh token has expired" }, 401);
	}

	// Revoke old refresh token
	await c.env.DB.prepare(
		"UPDATE refresh_tokens SET revoked_at = datetime('now') WHERE id = ?"
	)
		.bind(storedToken.id)
		.run();

	// Issue new tokens
	const { token: accessToken, expiresAt } = await signAccessToken(
		storedToken.user_id,
		c.env.JWT_SECRET,
		c.env.JWT_ISSUER
	);

	const newRefreshTokenRaw = generateRefreshToken();
	const newRefreshTokenHash = await hashToken(newRefreshTokenRaw);
	const refreshExpiresAt = new Date(
		Date.now() + 30 * 24 * 60 * 60 * 1000
	).toISOString();

	await c.env.DB.prepare(
		"INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at, created_at) VALUES (?, ?, ?, ?, datetime('now'))"
	)
		.bind(generateId(), storedToken.user_id, newRefreshTokenHash, refreshExpiresAt)
		.run();

	// Fetch user info
	const user = await c.env.DB.prepare(
		"SELECT id, email, display_name FROM users WHERE id = ?"
	)
		.bind(storedToken.user_id)
		.first<{ id: string; email: string | null; display_name: string | null }>();

	return c.json({
		accessToken,
		refreshToken: newRefreshTokenRaw,
		expiresAt: expiresAt.toISOString(),
		user: {
			id: storedToken.user_id,
			email: user?.email ?? null,
			displayName: user?.display_name ?? null,
		},
	});
});

// Revoke refresh token (logout)
authRoutes.post("/revoke", async (c) => {
	const body = await c.req.json<{ refreshToken: string }>();
	if (!body.refreshToken) {
		return c.json({ error: "bad_request", message: "refreshToken is required" }, 400);
	}

	const tokenHash = await hashToken(body.refreshToken);

	await c.env.DB.prepare(
		"UPDATE refresh_tokens SET revoked_at = datetime('now') WHERE token_hash = ? AND revoked_at IS NULL"
	)
		.bind(tokenHash)
		.run();

	return c.json({ success: true });
});

// Get current user profile
authRoutes.get("/me", requireAuth, async (c) => {
	const userId = c.get("userId");

	const user = await c.env.DB.prepare(
		"SELECT id, email, display_name, created_at FROM users WHERE id = ?"
	)
		.bind(userId)
		.first<{
			id: string;
			email: string | null;
			display_name: string | null;
			created_at: string;
		}>();

	if (!user) {
		return c.json({ error: "not_found", message: "User not found" }, 404);
	}

	return c.json({
		id: user.id,
		email: user.email,
		displayName: user.display_name,
		createdAt: user.created_at,
	});
});
