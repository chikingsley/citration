export type Bindings = {
	DB: D1Database;
	APPLE_TEAM_ID: string;
	APPLE_SERVICE_ID: string;
	JWT_ISSUER: string;
	JWT_SECRET: string;
};

export type Variables = {
	userId: string;
};

export type AppEnv = {
	Bindings: Bindings;
	Variables: Variables;
};
