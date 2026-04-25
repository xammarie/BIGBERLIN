// chat: text chat with Gemini Flash. Optional inline web research via Tavily,
// optional KB folder context, optional image attachments.
// payload: {
//   chat_id?: string,
//   message: string,
//   use_web?: boolean,
//   knowledge_base_folder_id?: string,
//   attachment_paths?: string[],   // paths in worksheets-input bucket
//   session_id?: string
// }
// returns the assistant message and the (created or updated) chat_id.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { errorResponse, handleOptions, jsonResponse } from "../_shared/cors.ts";
import { adminClient, authenticate } from "../_shared/supabase.ts";
import { chatTurn, ChatMessage, GEMINI_FLASH } from "../_shared/gemini.ts";
import { tavilySearch } from "../_shared/tavily.ts";
import { blobToBase64, inferMimeFromPath } from "../_shared/utils.ts";

const SYSTEM_PROMPT =
    `You are NoWork, a homework copilot tutor. The student is working on worksheets and notes.
Be concise, supportive, and pedagogical: explain concepts clearly, give hints before full answers,
encourage the student's own thinking. Match the student's casual register. If web research context is
provided, cite domains in parens. If knowledge base context is provided, reference it naturally.`;

interface ChatRequest {
    chat_id?: string;
    message: string;
    use_web?: boolean;
    knowledge_base_folder_id?: string;
    attachment_paths?: string[];
    session_id?: string;
}

interface StoredMessage {
    role: "user" | "assistant";
    content: string;
    timestamp: string;
    attachment_paths?: string[];
}

serve(async (req) => {
    const optionsRes = handleOptions(req);
    if (optionsRes) return optionsRes;

    try {
        const auth = await authenticate(req);
        if (!auth) return errorResponse("Unauthorized", 401);

        const body = (await req.json()) as ChatRequest;
        if (!body.message?.trim() && !(body.attachment_paths?.length)) {
            return errorResponse("message or attachments required", 400);
        }

        const supabase = adminClient();

        let chatId = body.chat_id;
        let history: StoredMessage[] = [];

        if (chatId) {
            const { data, error } = await supabase
                .from("chats")
                .select("messages")
                .eq("id", chatId)
                .eq("user_id", auth.userId)
                .single();
            if (error || !data) return errorResponse("Chat not found", 404);
            history = (data.messages as StoredMessage[]) ?? [];
        } else {
            const { data, error } = await supabase
                .from("chats")
                .insert({
                    user_id: auth.userId,
                    session_id: body.session_id ?? null,
                    knowledge_base_folder_id: body.knowledge_base_folder_id ?? null,
                    title: titleFromMessage(body.message),
                    messages: [],
                })
                .select("id")
                .single();
            if (error || !data) return errorResponse("Failed to create chat", 500);
            chatId = data.id as string;
        }

        // KB context: pull file metadata for the selected folder (or all user files if no folder)
        let kbContext: string | undefined;
        if (body.knowledge_base_folder_id !== undefined) {
            try {
                let q = supabase
                    .from("knowledge_base_items")
                    .select("filename, mime_type, metadata")
                    .eq("user_id", auth.userId);
                if (body.knowledge_base_folder_id) {
                    q = q.eq("folder_id", body.knowledge_base_folder_id);
                }
                const { data: kb } = await q.limit(20);
                if (kb && kb.length > 0) {
                    kbContext = kb.map((k: any) =>
                        `- ${k.filename}${k.mime_type ? ` (${k.mime_type})` : ""}`
                    ).join("\n");
                }
            } catch (e) {
                console.warn("KB context fetch failed:", e);
            }
        }

        // Web research
        let webContext: string | undefined;
        if (body.use_web) {
            try {
                const search = await tavilySearch({
                    query: body.message,
                    maxResults: 4,
                    includeAnswer: true,
                });
                const lines: string[] = [];
                if (search.answer) lines.push(`Quick answer: ${search.answer}`);
                search.results.forEach((r) => {
                    lines.push(`- ${r.title} (${r.url}): ${r.content.slice(0, 400)}`);
                });
                webContext = lines.join("\n");
            } catch (e) {
                console.warn("Tavily search failed:", e);
            }
        }

        // Attachment images: download from storage and base64 for vision
        const attachmentImages: { base64: string; mimeType: string }[] = [];
        if (body.attachment_paths?.length) {
            for (const path of body.attachment_paths) {
                try {
                    const { data, error } = await supabase.storage
                        .from("worksheets-input")
                        .download(path);
                    if (error || !data) continue;
                    attachmentImages.push({
                        base64: await blobToBase64(data),
                        mimeType: inferMimeFromPath(path),
                    });
                } catch (e) {
                    console.warn(`Failed to fetch attachment ${path}:`, e);
                }
            }
        }

        const geminiHistory: ChatMessage[] = history.map((m) => ({
            role: m.role === "assistant" ? "model" : "user",
            content: m.content,
        }));

        const reply = await chatTurn({
            history: geminiHistory,
            userMessage: body.message,
            systemPrompt: SYSTEM_PROMPT,
            webContext,
            kbContext,
            contextFiles: attachmentImages.length > 0 ? attachmentImages : undefined,
            model: GEMINI_FLASH,
        });

        const now = new Date().toISOString();
        const newHistory: StoredMessage[] = [
            ...history,
            {
                role: "user",
                content: body.message,
                timestamp: now,
                attachment_paths: body.attachment_paths,
            },
            { role: "assistant", content: reply, timestamp: now },
        ];

        await supabase
            .from("chats")
            .update({ messages: newHistory })
            .eq("id", chatId)
            .eq("user_id", auth.userId);

        return jsonResponse({
            chat_id: chatId,
            reply,
            used_web: body.use_web === true && webContext !== undefined,
            kb_used: kbContext !== undefined,
            attachments_count: attachmentImages.length,
        });
    } catch (err) {
        console.error("chat error:", err);
        return errorResponse(
            err instanceof Error ? err.message : String(err),
            500,
        );
    }
});

function titleFromMessage(msg: string): string {
    const firstLine = msg.split("\n")[0].trim();
    if (firstLine.length <= 50) return firstLine;
    return firstLine.slice(0, 47) + "…";
}
