// voice-token: broker an ephemeral Gradium session token for the swift client.
// Pattern: client never sees GRADIUM_API_KEY. Edge function exchanges API key
// for a short-lived session token and returns that to the swift app, which
// then opens its own websocket to gradium with the token.
//
// NOTE: actual gradium endpoint shape needs to be confirmed at venue.
// This implementation tries a sensible default and exposes the raw API key
// as a fallback (insecure but demo-acceptable) if the broker endpoint isn't available.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { errorResponse, handleOptions, jsonResponse } from "../_shared/cors.ts";
import { authenticate } from "../_shared/supabase.ts";

const GRADIUM_TOKEN_URL = "https://api.gradium.ai/v1/realtime/sessions";

serve(async (req) => {
    const optionsRes = handleOptions(req);
    if (optionsRes) return optionsRes;

    try {
        const auth = await authenticate(req);
        if (!auth) return errorResponse("Unauthorized", 401);

        const apiKey = Deno.env.get("GRADIUM_API_KEY")!;

        // Try the broker pattern first
        try {
            const res = await fetch(GRADIUM_TOKEN_URL, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    Authorization: `Bearer ${apiKey}`,
                },
                body: JSON.stringify({
                    user_id: auth.userId,
                    expires_in_seconds: 600,
                }),
            });
            if (res.ok) {
                const data = await res.json();
                return jsonResponse({
                    mode: "ephemeral",
                    token: data.token ?? data.session_token ?? data.client_secret,
                    expires_at: data.expires_at,
                    websocket_url: data.websocket_url ?? data.ws_url,
                });
            }
        } catch (e) {
            console.warn("Gradium broker endpoint not available:", e);
        }

        // Fallback: hand back raw key (hackathon-acceptable; replace once docs confirmed)
        return jsonResponse({
            mode: "raw",
            token: apiKey,
            websocket_url: null,
            note:
                "Gradium broker endpoint unavailable; using raw key (hackathon-only fallback).",
        });
    } catch (err) {
        console.error("voice-token error:", err);
        return errorResponse(
            err instanceof Error ? err.message : String(err),
            500,
        );
    }
});
