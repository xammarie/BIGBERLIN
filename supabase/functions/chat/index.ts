// chat: text chat with Gemini Flash. Optional inline web research via Tavily.
// payload: { chat_id?: string, message: string, use_web?: boolean, session_id?: string }
// returns the assistant message and the (created or updated) chat_id.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { errorResponse, handleOptions, jsonResponse } from "../_shared/cors.ts";
import { adminClient, authenticate } from "../_shared/supabase.ts";
import { chatTurn, ChatMessage } from "../_shared/gemini.ts";
import { tavilySearch } from "../_shared/tavily.ts";

const SYSTEM_PROMPT =
    `You are a homework copilot tutor. The student is working on worksheets and notes.
Be concise, supportive, and pedagogical: explain concepts clearly, give hints before full answers,
encourage the student's own thinking. If web research context is provided, cite it as "(source: <domain>)".`;

interface ChatRequest {
    chat_id?: string;
    message: string;
    use_web?: boolean;
    session_id?: string;
}

interface StoredMessage {
    role: "user" | "assistant";
    content: string;
    timestamp: string;
}

serve(async (req) => {
    const optionsRes = handleOptions(req);
    if (optionsRes) return optionsRes;

    try {
        const auth = await authenticate(req);
        if (!auth) return errorResponse("Unauthorized", 401);

        const body = (await req.json()) as ChatRequest;
        if (!body.message?.trim()) {
            return errorResponse("message required", 400);
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
                    messages: [],
                })
                .select("id")
                .single();
            if (error || !data) return errorResponse("Failed to create chat", 500);
            chatId = data.id as string;
        }

        // Optional web research
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

        const geminiHistory: ChatMessage[] = history.map((m) => ({
            role: m.role === "assistant" ? "model" : "user",
            content: m.content,
        }));

        const reply = await chatTurn({
            history: geminiHistory,
            userMessage: body.message,
            systemPrompt: SYSTEM_PROMPT,
            webContext,
        });

        const now = new Date().toISOString();
        const newHistory: StoredMessage[] = [
            ...history,
            { role: "user", content: body.message, timestamp: now },
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
        });
    } catch (err) {
        console.error("chat error:", err);
        return errorResponse(
            err instanceof Error ? err.message : String(err),
            500,
        );
    }
});
