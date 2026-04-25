// generate-video: Hera explainer video generation.
// Two modes:
//   start mode: { topic: string, chat_id?: string, knowledge_base_folder_id?: string, use_web?: boolean }
//     -> gemini 3.1 pro generates a tight video prompt from topic + chat context + KB + web,
//        then kicks off Hera. Returns { job_id, prompt, status }.
//   status mode: { job_id: string }
//     -> returns current Hera job status + video_url if complete.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { errorResponse, handleOptions, jsonResponse } from "../_shared/cors.ts";
import { adminClient, authenticate } from "../_shared/supabase.ts";
import { generateExplainerPrompt } from "../_shared/gemini.ts";
import { getVideoStatus, startVideoGeneration } from "../_shared/hera.ts";
import { tavilySearch } from "../_shared/tavily.ts";

interface VideoRequest {
    topic?: string;
    duration_seconds?: number;
    chat_id?: string;
    knowledge_base_folder_id?: string;
    use_web?: boolean;
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

        if (!body.topic?.trim()) return errorResponse("topic required", 400);

        const supabase = adminClient();

        // Gather context: chat history, KB filenames, web research
        const contextParts: string[] = [];

        if (body.chat_id) {
            try {
                const { data: chat } = await supabase
                    .from("chats")
                    .select("messages")
                    .eq("id", body.chat_id)
                    .eq("user_id", auth.userId)
                    .single();
                const messages = (chat?.messages ?? []) as Array<
                    { role: string; content: string }
                >;
                if (messages.length > 0) {
                    const recent = messages.slice(-10).map((m) =>
                        `${m.role}: ${m.content}`
                    ).join("\n");
                    contextParts.push(`Recent chat:\n${recent}`);
                }
            } catch (e) {
                console.warn("Failed to load chat context:", e);
            }
        }

        if (body.knowledge_base_folder_id !== undefined) {
            try {
                let q = supabase
                    .from("knowledge_base_items")
                    .select("filename, mime_type")
                    .eq("user_id", auth.userId);
                if (body.knowledge_base_folder_id) {
                    q = q.eq("folder_id", body.knowledge_base_folder_id);
                }
                const { data: kb } = await q.limit(15);
                if (kb && kb.length > 0) {
                    contextParts.push(
                        `KB files: ${
                            kb.map((k: any) => k.filename).join(", ")
                        }`,
                    );
                }
            } catch (e) {
                console.warn("Failed to load KB context:", e);
            }
        }

        if (body.use_web) {
            try {
                const search = await tavilySearch({
                    query: body.topic,
                    maxResults: 3,
                    includeAnswer: true,
                });
                const lines: string[] = [];
                if (search.answer) lines.push(search.answer);
                search.results.slice(0, 2).forEach((r) =>
                    lines.push(`- ${r.title}: ${r.content.slice(0, 250)}`)
                );
                if (lines.length > 0) {
                    contextParts.push(`Web research:\n${lines.join("\n")}`);
                }
            } catch (e) {
                console.warn("Tavily failed:", e);
            }
        }

        // Gemini 3.1 Pro generates the video prompt
        const videoPrompt = await generateExplainerPrompt({
            topic: body.topic,
            context: contextParts.length > 0
                ? contextParts.join("\n\n")
                : undefined,
        });

        // Kick off Hera
        const job = await startVideoGeneration({
            prompt: videoPrompt,
            durationSeconds: body.duration_seconds ?? 8,
        });

        return jsonResponse({
            job_id: job.jobId,
            status: "queued",
            prompt: videoPrompt,
        });
    } catch (err) {
        console.error("generate-video error:", err);
        return errorResponse(
            err instanceof Error ? err.message : String(err),
            500,
        );
    }
});
