import { createMiddleware } from "hono/factory";
import { verifyAccessToken } from "../utils/jwt";
import type { AppEnv } from "../types";

export const requireAuth = createMiddleware<AppEnv>(async (c, next) => {
	const header = c.req.header("Authorization");
	if (!header?.startsWith("Bearer ")) {
		return c.json({ error: "unauthorized", message: "Missing bearer token" }, 401);
	}

	const token = header.slice(7);
	try {
		const claims = await verifyAccessToken(
			token,
			c.env.JWT_SECRET,
			c.env.JWT_ISSUER
		);
		c.set("userId", claims.sub);
		await next();
	} catch {
		return c.json({ error: "unauthorized", message: "Invalid or expired token" }, 401);
	}
});
