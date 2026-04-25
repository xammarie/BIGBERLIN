// generate-video: kicks off Hera explainer video generation, then polls.
// payload: { topic: string, duration_seconds?: number, session_id?: string }
// returns: { job_id, status, video_url? }
// For long jobs, the swift client can poll this endpoint with { job_id } to check status.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { errorResponse, handleOptions, jsonResponse } from "../_shared/cors.ts";
import { authenticate } from "../_shared/supabase.ts";
import { getVideoStatus, startVideoGeneration } from "../_shared/hera.ts";

interface VideoRequest {
    topic?: string;
    duration_seconds?: number;
    job_id?: string;
}

serve(async (req) => {
    const optionsRes = handleOptions(req);
    if (optionsRes) return optionsRes;

    try {
        const auth = await authenticate(req);
        if (!auth) return errorResponse("Unauthorized", 401);

        const body = (await req.json()) as VideoRequest;

        // Status check mode
        if (body.job_id) {
            const status = await getVideoStatus(body.job_id);
            return jsonResponse(status);
        }

        // Start mode
        if (!body.topic?.trim()) return errorResponse("topic required", 400);

        const prompt = buildExplainerPrompt(body.topic);
        const job = await startVideoGeneration({
            prompt,
            durationSeconds: body.duration_seconds ?? 8,
        });

        return jsonResponse({
            job_id: job.jobId,
            status: "queued",
        });
    } catch (err) {
        console.error("generate-video error:", err);
        return errorResponse(
            err instanceof Error ? err.message : String(err),
            500,
        );
    }
});

function buildExplainerPrompt(topic: string): string {
    return `Educational explainer video about: ${topic}.
Style: clean, minimal, focused, anti-slop. Pedagogical clarity over flashy effects.
Use clear visual metaphors. Show, don't tell. Keep it tight and uncluttered.`;
}
