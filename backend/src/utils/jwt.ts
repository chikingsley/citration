import * as jose from "jose";

export interface TokenClaims {
	sub: string;
	iss: string;
	iat: number;
	exp: number;
}

export async function signAccessToken(
	userId: string,
	secret: string,
	issuer: string
): Promise<{ token: string; expiresAt: Date }> {
	const now = Math.floor(Date.now() / 1000);
	const exp = now + 15 * 60; // 15 minutes

	const secretKey = new TextEncoder().encode(secret);
	const token = await new jose.SignJWT({ sub: userId })
		.setProtectedHeader({ alg: "HS256" })
		.setIssuedAt(now)
		.setExpirationTime(exp)
		.setIssuer(issuer)
		.sign(secretKey);

	return { token, expiresAt: new Date(exp * 1000) };
}

export async function verifyAccessToken(
	token: string,
	secret: string,
	issuer: string
): Promise<TokenClaims> {
	const secretKey = new TextEncoder().encode(secret);
	const { payload } = await jose.jwtVerify(token, secretKey, {
		issuer,
	});

	return {
		sub: payload.sub as string,
		iss: payload.iss as string,
		iat: payload.iat as number,
		exp: payload.exp as number,
	};
}
