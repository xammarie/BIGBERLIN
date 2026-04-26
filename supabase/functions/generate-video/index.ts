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
import {
    boundedInt,
    HttpError,
    jobId,
    LIMITS,
    optionalUuid,
    readJsonObject,
    requirePost,
    responseMessage,
    responseStatus,
    text,
} from "../_shared/security.ts";

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
        requirePost(req);
        const auth = await authenticate(req);
        if (!auth) return errorResponse("Unauthorized", 401);

        const body = await readJsonObject<VideoRequest>(req);
        const supabase = adminClient();

        // Status check mode
        if (body.job_id) {
            const id = jobId(body.job_id);
            const { data: stored, error } = await supabase
                .from("video_jobs")
                .select("job_id")
                .eq("job_id", id)
                .eq("user_id", auth.userId)
                .maybeSingle();
            if (error) throw new Error(`Video job lookup failed: ${error.message}`);
            if (!stored) throw new HttpError(404, "Video job not found");

            const status = await getVideoStatus(id);
            await supabase
                .from("video_jobs")
                .update({
                    status: status.status,
                    video_url: status.videoUrl ?? null,
                    error: status.error ?? null,
                })
                .eq("job_id", id)
                .eq("user_id", auth.userId);
            return jsonResponse(status);
        }

        const topic = text(body.topic, "topic", LIMITS.topicChars);
        const durationSeconds = boundedInt(
            body.duration_seconds,
            "duration_seconds",
            8,
            4,
            12,
        );
        const chatId = optionalUuid(body.chat_id, "chat_id");
        const folderId = optionalUuid(
            body.knowledge_base_folder_id,
            "knowledge_base_folder_id",
        );

        // Gather context: chat history, KB filenames, web research
        const contextParts: string[] = [];

        if (chatId) {
            try {
                const { data: chat } = await supabase
                    .from("chats")
                    .select("messages")
                    .eq("id", chatId)
                    .eq("user_id", auth.userId)
                    .maybeSingle();
                if (!chat) throw new HttpError(404, "Chat not found");
                const messages = (chat?.messages ?? []) as Array<
                    { role: string; content: string }
                >;
                if (messages.length > 0) {
                    const recent = messages.slice(-10).map((m) =>
                        `${m.role}: ${String(m.content).slice(0, 600)}`
                    ).join("\n");
                    contextParts.push(`Recent chat:\n${recent}`);
                }
            } catch (e) {
                if (e instanceof HttpError) throw e;
                console.warn("Failed to load chat context:", e);
            }
        }

        if (folderId) {
            try {
                const { data: folder, error: folderErr } = await supabase
                    .from("knowledge_base_folders")
                    .select("id")
                    .eq("id", folderId)
                    .eq("user_id", auth.userId)
                    .maybeSingle();
                if (folderErr) throw new Error(folderErr.message);
                if (!folder) throw new HttpError(404, "Knowledge base folder not found");

                const { data: kb } = await supabase
                    .from("knowledge_base_items")
                    .select("filename, mime_type")
                    .eq("user_id", auth.userId)
                    .eq("folder_id", folderId)
                    .limit(15);
                if (kb && kb.length > 0) {
                    contextParts.push(
                        `KB files: ${
                            kb.map((k: any) => k.filename).join(", ")
                        }`,
                    );
                }
            } catch (e) {
                if (e instanceof HttpError) throw e;
                console.warn("Failed to load KB context:", e);
            }
        }

        if (body.use_web) {
            try {
                const search = await tavilySearch({
                    query: topic,
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
            topic,
            context: contextParts.length > 0
                ? contextParts.join("\n\n")
                : undefined,
        });

        // Kick off Hera
        const job = await startVideoGeneration({
            prompt: videoPrompt,
            durationSeconds,
        });

        await supabase.from("video_jobs").insert({
            job_id: job.jobId,
            user_id: auth.userId,
            prompt: videoPrompt,
            status: "queued",
        });

        return jsonResponse({
            job_id: job.jobId,
            status: "queued",
            prompt: videoPrompt,
        });
    } catch (err) {
        console.error("generate-video error:", err);
        return errorResponse(
            responseMessage(err, "Video request failed"),
            responseStatus(err),
        );
    }
});
