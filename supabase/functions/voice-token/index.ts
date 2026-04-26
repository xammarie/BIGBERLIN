// voice-token: authenticated voice configuration plus server-side Gradium TTS.
//
// The client must never receive GRADIUM_API_KEY. STT is handled locally by iOS
// Speech; TTS is proxied here so the long-lived Gradium key stays server-side.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import {
    corsHeaders,
    errorResponse,
    handleOptions,
    jsonResponse,
} from "../_shared/cors.ts";
import { authenticate } from "../_shared/supabase.ts";
import {
    HttpError,
    LIMITS,
    readJsonObject,
    requirePost,
    responseMessage,
    responseStatus,
    text,
} from "../_shared/security.ts";

const TTS_URL = "https://api.gradium.ai/api/post/speech/tts";
const DEFAULT_VOICE_ID = "YTpq7expH9539ERJ";
const VOICE_ID_RE = /^[A-Za-z0-9_-]{1,80}$/;

interface VoiceRequest {
    text?: string;
    voice_id?: string;
}

serve(async (req) => {
    const optionsRes = handleOptions(req);
    if (optionsRes) return optionsRes;

    try {
        requirePost(req);
        const auth = await authenticate(req);
        if (!auth) return errorResponse("Unauthorized", 401, req);

        const apiKey = Deno.env.get("GRADIUM_API_KEY");
        if (!apiKey) {
            console.error("GRADIUM_API_KEY is not set");
            return errorResponse("Voice not configured", 500, req);
        }

        const body = await readJsonObject<VoiceRequest>(req);
        const speechText = text(body.text, "text", LIMITS.chatMessageChars, {
            required: false,
        });
        if (!speechText) {
            return jsonResponse({
                mode: "server_tts",
                token: null,
                websocket_url: null,
                tts_url: functionUrl(req),
            }, 200, req);
        }

        const voiceId = parseVoiceId(body.voice_id);
        const upstream = await fetch(TTS_URL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "x-api-key": apiKey,
            },
            body: JSON.stringify({
                text: speechText,
                voice_id: voiceId,
                output_format: "wav",
                only_audio: true,
            }),
        });

        if (!upstream.ok) {
            console.error("Gradium TTS failed:", upstream.status, await upstream.text());
            return errorResponse("Voice synthesis failed", 502, req);
        }

        const audio = await upstream.arrayBuffer();
        return new Response(audio, {
            status: 200,
            headers: {
                ...corsHeaders(req),
                "Content-Type": upstream.headers.get("content-type") ?? "audio/wav",
                "Cache-Control": "no-store",
            },
        });
    } catch (err) {
        console.error("voice-token error:", err);
        return errorResponse(
            responseMessage(err, "Voice request failed"),
            responseStatus(err),
            req,
        );
    }
});

function parseVoiceId(value: unknown): string {
    if (value === undefined || value === null || value === "") {
        return DEFAULT_VOICE_ID;
    }
    if (typeof value !== "string" || !VOICE_ID_RE.test(value)) {
        throw new HttpError(400, "voice_id has an invalid value");
    }
    return value;
}

function functionUrl(req: Request): string {
    return new URL(req.url).toString();
}
