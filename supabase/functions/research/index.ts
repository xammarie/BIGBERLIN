// research: Tavily wrapper. authenticated thin proxy so the API key never leaves the backend.
// payload: { query: string, depth?: "basic"|"advanced", time_range?: "day"|"week"|"month"|"year" }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { errorResponse, handleOptions, jsonResponse } from "../_shared/cors.ts";
import { authenticate } from "../_shared/supabase.ts";
import { tavilySearch } from "../_shared/tavily.ts";
import {
    boundedInt,
    enumValue,
    LIMITS,
    readJsonObject,
    requirePost,
    responseMessage,
    responseStatus,
    text,
} from "../_shared/security.ts";

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
        requirePost(req);
        const auth = await authenticate(req);
        if (!auth) return errorResponse("Unauthorized", 401);

        const body = await readJsonObject<ResearchRequest>(req);
        const query = text(body.query, "query", LIMITS.searchQueryChars);
        const depth = enumValue(
            body.depth,
            "depth",
            ["basic", "advanced"] as const,
            "basic",
        );
        const timeRange = body.time_range === undefined || body.time_range === null
            ? undefined
            : enumValue(
                body.time_range,
                "time_range",
                ["day", "week", "month", "year"] as const,
            );
        const maxResults = boundedInt(
            body.max_results,
            "max_results",
            5,
            1,
            10,
        );

        const result = await tavilySearch({
            query,
            depth,
            timeRange,
            maxResults,
            includeAnswer: true,
        });

        return jsonResponse(result);
    } catch (err) {
        console.error("research error:", err);
        return errorResponse(
            responseMessage(err, "Research request failed"),
            responseStatus(err),
        );
    }
});
