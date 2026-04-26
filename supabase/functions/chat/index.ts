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
import { chatTurn, ChatMessage, ModelMode } from "../_shared/gemini.ts";
import { tavilySearch } from "../_shared/tavily.ts";
import { blobToBase64, inferMimeFromPath } from "../_shared/utils.ts";
import {
    assertSafeStorageObjectName,
    enumValue,
    HttpError,
    LIMITS,
    optionalUuid,
    readJsonObject,
    requireBlobSize,
    requirePost,
    responseMessage,
    responseStatus,
    text,
    userStoragePathArray,
} from "../_shared/security.ts";

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
    model?: ModelMode;
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
        requirePost(req);
        const auth = await authenticate(req);
        if (!auth) return errorResponse("Unauthorized", 401);

        const body = await readJsonObject<ChatRequest>(req);
        const message = text(body.message ?? "", "message", LIMITS.chatMessageChars, {
            required: false,
        });
        const attachmentPaths = userStoragePathArray(
            body.attachment_paths,
            auth.userId,
            "attachment_paths",
            LIMITS.attachmentImages,
        );
        if (!message && attachmentPaths.length === 0) {
            throw new HttpError(400, "message or attachments required");
        }
        const model = enumValue<ModelMode>(
            body.model,
            "model",
            ["fast", "smart"] as const,
            "fast",
        );
        const requestedChatId = optionalUuid(body.chat_id, "chat_id");
        const requestedSessionId = optionalUuid(body.session_id, "session_id");
        const requestedFolderId = optionalUuid(
            body.knowledge_base_folder_id,
            "knowledge_base_folder_id",
        );

        const supabase = adminClient();

        if (requestedSessionId) {
            const { data: session, error } = await supabase
                .from("sessions")
                .select("id")
                .eq("id", requestedSessionId)
                .eq("user_id", auth.userId)
                .maybeSingle();
            if (error) throw new Error(`Session lookup failed: ${error.message}`);
            if (!session) throw new HttpError(404, "Session not found");
        }

        if (requestedFolderId) {
            const { data: folder, error } = await supabase
                .from("knowledge_base_folders")
                .select("id")
                .eq("id", requestedFolderId)
                .eq("user_id", auth.userId)
                .maybeSingle();
            if (error) throw new Error(`Folder lookup failed: ${error.message}`);
            if (!folder) throw new HttpError(404, "Knowledge base folder not found");
        }

        let chatId = requestedChatId;
        let history: StoredMessage[] = [];

        if (chatId) {
            const { data, error } = await supabase
                .from("chats")
                .select("messages")
                .eq("id", chatId)
                .eq("user_id", auth.userId)
                .single();
            if (error || !data) return errorResponse("Chat not found", 404);
            history = normalizeHistory(data.messages);
        } else {
            const { data, error } = await supabase
                .from("chats")
                .insert({
                    user_id: auth.userId,
                    session_id: requestedSessionId ?? null,
                    knowledge_base_folder_id: requestedFolderId ?? null,
                    title: titleFromMessage(message),
                    messages: [],
                })
                .select("id")
                .single();
            if (error || !data) {
                console.error("Failed to create chat:", error);
                return errorResponse("Failed to create chat", 500);
            }
            chatId = data.id as string;
        }

        // KB context: only when a concrete, owned folder is selected.
        let kbContext: string | undefined;
        if (requestedFolderId) {
            try {
                const { data: kb } = await supabase
                    .from("knowledge_base_items")
                    .select("filename, mime_type, metadata")
                    .eq("user_id", auth.userId)
                    .eq("folder_id", requestedFolderId)
                    .limit(20);
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
        if (body.use_web && message) {
            try {
                const search = await tavilySearch({
                    query: message,
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
        if (attachmentPaths.length) {
            for (const ownedAttachmentPath of attachmentPaths) {
                const safeAttachmentObjectName = assertSafeStorageObjectName(
                    ownedAttachmentPath,
                    "attachment path",
                );
                const { data, error } = await supabase.storage
                    .from("worksheets-input")
                    .download(safeAttachmentObjectName);
                if (error || !data) {
                    console.warn(
                        `Failed to fetch attachment ${safeAttachmentObjectName}:`,
                        error,
                    );
                    throw new HttpError(400, "Attachment could not be loaded");
                }
                requireBlobSize(data, "attachment image");
                attachmentImages.push({
                    base64: await blobToBase64(data),
                    mimeType: inferMimeFromPath(safeAttachmentObjectName),
                });
            }
        }

        const historyForModel = history.slice(-LIMITS.chatHistoryMessages);
        const geminiHistory: ChatMessage[] = historyForModel.map((m) => ({
            role: m.role === "assistant" ? "model" : "user",
            content: m.content.slice(0, LIMITS.chatMessageChars),
        }));

        const reply = await chatTurn({
            history: geminiHistory,
            userMessage: message,
            systemPrompt: SYSTEM_PROMPT,
            webContext,
            kbContext,
            contextFiles: attachmentImages.length > 0 ? attachmentImages : undefined,
            model,
        });

        const now = new Date().toISOString();
        const newHistory: StoredMessage[] = ([
            ...history,
            {
                role: "user",
                content: message,
                timestamp: now,
                attachment_paths: attachmentPaths.length ? attachmentPaths : undefined,
            },
            { role: "assistant", content: reply, timestamp: now },
        ]).slice(-LIMITS.storedChatMessages);

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
            responseMessage(err, "Chat request failed"),
            responseStatus(err),
        );
    }
});

function titleFromMessage(msg: string): string {
    const firstLine = msg.split("\n")[0].trim();
    if (firstLine.length <= 50) return firstLine;
    return firstLine.slice(0, 47) + "…";
}

function normalizeHistory(value: unknown): StoredMessage[] {
    if (!Array.isArray(value)) return [];
    const normalized: StoredMessage[] = [];
    for (const item of value) {
        if (!item || typeof item !== "object") continue;
        const m = item as Partial<StoredMessage>;
        if (
            (m.role !== "user" && m.role !== "assistant") ||
            typeof m.content !== "string"
        ) {
            continue;
        }
        normalized.push({
            role: m.role,
            content: m.content.slice(0, LIMITS.chatMessageChars),
            timestamp: typeof m.timestamp === "string"
                ? m.timestamp
                : new Date().toISOString(),
            attachment_paths: Array.isArray(m.attachment_paths)
                ? m.attachment_paths.filter((p) => typeof p === "string")
                : undefined,
        });
    }
    return normalized.slice(-LIMITS.storedChatMessages);
}
