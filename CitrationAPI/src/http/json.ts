export const jsonError = (message: string, status = 400): Response =>
  new Response(JSON.stringify({ error: message }), {
    headers: { "content-type": "application/json" },
    status,
  });
