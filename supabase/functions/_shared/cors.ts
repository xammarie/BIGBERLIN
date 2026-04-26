const DEFAULT_ALLOWED_ORIGINS = [
    "https://nowork.app",
    "https://bigberlin.de",
    "https://xammarie.github.io",
];

function allowedOrigins(): string[] {
    const configured = Deno.env.get("ALLOWED_ORIGINS");
    if (!configured) return DEFAULT_ALLOWED_ORIGINS;
    return configured.split(",").map((origin) => origin.trim()).filter(Boolean);
}

export function corsHeaders(req?: Request): Record<string, string> {
    const headers: Record<string, string> = {
        "Vary": "Origin",
        "Access-Control-Allow-Headers":
            "authorization, x-client-info, apikey, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
    };

    const origin = req?.headers.get("Origin");
    if (origin && allowedOrigins().includes(origin)) {
        headers["Access-Control-Allow-Origin"] = origin;
    }
    return headers;
}

export const legacyCorsHeaders = {
    "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type",
};

export function handleOptions(req: Request): Response | null {
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders(req) });
    }
    return null;
}

export function jsonResponse(body: unknown, status = 200, req?: Request): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
}

export function errorResponse(message: string, status = 500, req?: Request): Response {
    return jsonResponse({ error: message }, status, req);
}
