// voice-token: broker an ephemeral Gradium session token for the swift client.
// Pattern: client never sees GRADIUM_API_KEY. Edge function exchanges API key
// for a short-lived session token and returns that to the swift app, which
// then opens its own websocket to gradium with the token.
//
// Client never receives GRADIUM_API_KEY. If the broker endpoint is unavailable,
// this function fails closed instead of falling back to a raw server secret.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { errorResponse, handleOptions, jsonResponse } from "../_shared/cors.ts";
import { authenticate } from "../_shared/supabase.ts";
import {
    requirePost,
    responseMessage,
    responseStatus,
} from "../_shared/security.ts";

const GRADIUM_TOKEN_URL = "https://api.gradium.ai/v1/realtime/sessions";

serve(async (req) => {
    const optionsRes = handleOptions(req);
    if (optionsRes) return optionsRes;

    try {
        requirePost(req);
        const auth = await authenticate(req);
        if (!auth) return errorResponse("Unauthorized", 401);

        const apiKey = Deno.env.get("GRADIUM_API_KEY");
        if (!apiKey) throw new Error("GRADIUM_API_KEY is not set");

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
        if (!res.ok) {
            console.error("Gradium broker failed:", res.status, await res.text());
            return errorResponse("Voice token broker unavailable", 502);
        }

        const data = await res.json();
        const token = data.token ?? data.session_token ?? data.client_secret;
        if (typeof token !== "string" || token.length === 0) {
            console.error("Gradium broker returned no client token:", data);
            return errorResponse("Voice token broker returned no token", 502);
        }
        return jsonResponse({
            mode: "ephemeral",
            token,
            expires_at: data.expires_at,
            websocket_url: data.websocket_url ?? data.ws_url,
        });
    } catch (err) {
        console.error("voice-token error:", err);
        return errorResponse(
            responseMessage(err, "Voice token request failed"),
            responseStatus(err),
        );
    }
});
