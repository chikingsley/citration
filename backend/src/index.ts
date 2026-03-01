import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import { authRoutes } from "./routes/auth";
import { workspaceRoutes } from "./routes/workspaces";
import type { AppEnv } from "./types";

const app = new Hono<AppEnv>();

app.use("*", logger());
app.use(
	"*",
	cors({
		origin: "*",
		allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
		allowHeaders: ["Content-Type", "Authorization"],
		maxAge: 86400,
	})
);

app.get("/", (c) => c.json({ name: "bettercite-api", status: "ok" }));

app.get("/health", (c) =>
	c.json({ status: "ok", timestamp: new Date().toISOString() })
);

app.route("/v1/auth", authRoutes);
app.route("/v1/workspaces", workspaceRoutes);

app.notFound((c) => c.json({ error: "not_found" }, 404));

app.onError((err, c) => {
	console.error("Unhandled error:", err);
	return c.json({ error: "internal_server_error" }, 500);
});

export default app;
