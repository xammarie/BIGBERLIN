// research: Tavily wrapper. authenticated thin proxy so the API key never leaves the backend.
// payload: { query: string, depth?: "basic"|"advanced", time_range?: "day"|"week"|"month"|"year" }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { errorResponse, handleOptions, jsonResponse } from "../_shared/cors.ts";
import { authenticate } from "../_shared/supabase.ts";
import { tavilySearch } from "../_shared/tavily.ts";

interface ResearchRequest {
    query: string;
    depth?: "basic" | "advanced";
    time_range?: "day" | "week" | "month" | "year";
    max_results?: number;
}

serve(async (req) => {
    const optionsRes = handleOptions(req);
    if (optionsRes) return optionsRes;

    try {
        const auth = await authenticate(req);
        if (!auth) return errorResponse("Unauthorized", 401);

        const body = (await req.json()) as ResearchRequest;
        if (!body.query?.trim()) return errorResponse("query required", 400);

        const result = await tavilySearch({
            query: body.query,
            depth: body.depth ?? "basic",
            timeRange: body.time_range,
            maxResults: body.max_results ?? 5,
            includeAnswer: true,
        });

        return jsonResponse(result);
    } catch (err) {
        console.error("research error:", err);
        return errorResponse(
            err instanceof Error ? err.message : String(err),
            500,
        );
    }
});
