import * as jose from "jose";

const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";

let cachedJWKS: jose.JSONWebKeySet | null = null;
let cachedAt = 0;
const CACHE_TTL_MS = 60 * 60 * 1000; // 1 hour

export async function getAppleJWKS(): Promise<jose.JSONWebKeySet> {
	const now = Date.now();
	if (cachedJWKS && now - cachedAt < CACHE_TTL_MS) {
		return cachedJWKS;
	}

	const response = await fetch(APPLE_JWKS_URL);
	if (!response.ok) {
		throw new Error(`Failed to fetch Apple JWKS: ${response.status}`);
	}

	cachedJWKS = (await response.json()) as jose.JSONWebKeySet;
	cachedAt = now;
	return cachedJWKS;
}

export interface AppleTokenClaims {
	sub: string;
	email?: string;
	email_verified?: string | boolean;
	iss: string;
	aud: string;
}

export async function verifyAppleIdentityToken(
	identityToken: string,
	expectedAudience: string
): Promise<AppleTokenClaims> {
	const jwks = await getAppleJWKS();
	const JWKS = jose.createLocalJWKSet(jwks);

	const { payload } = await jose.jwtVerify(identityToken, JWKS, {
		issuer: "https://appleid.apple.com",
		audience: expectedAudience,
	});

	return {
		sub: payload.sub as string,
		email: payload.email as string | undefined,
		email_verified: payload.email_verified as string | boolean | undefined,
		iss: payload.iss as string,
		aud: payload.aud as string,
	};
}
