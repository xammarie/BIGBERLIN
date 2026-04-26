// All Gemini calls are routed through OpenRouter so we use one API key for
// LLMs + image-edit, dodge per-model free-tier quotas, and let the iOS client
// pick a "fast" or "smart" model per turn.

import {
    ActionType,
    buildSystemPrompt,
    GEMINI_RESPONSE_SCHEMA,
    HandwritingMode,
} from "./prompts.ts";

// Public model labels (the only thing the iOS app sends).
export type ModelMode = "fast" | "smart";

// OpenRouter ids.
export const GEMINI_FAST = "google/gemini-3.1-flash-lite-preview";
export const GEMINI_SMART = "google/gemini-3.1-pro-preview";

// Reasoning that backs worksheet processing + explainer prompts. Always smart
// — these calls plan out gpt-image-2 prompts and Hera prompts and chat depends
// on them being right.
export const GEMINI_REASONING = GEMINI_SMART;

// Compatibility aliases so any older imports keep building. Treat them as
// "default chat model" — fast.
export const GEMINI_FLASH = GEMINI_FAST;
export const GEMINI_FLASH_LITE = GEMINI_FAST;
export const GEMINI_PRO = GEMINI_SMART;

const OR_URL = "https://openrouter.ai/api/v1/chat/completions";

function resolveModel(mode?: ModelMode | string): string {
    if (mode === "smart") return GEMINI_SMART;
    if (mode === "fast") return GEMINI_FAST;
    return GEMINI_FAST;
}

function orHeaders(): HeadersInit {
    const apiKey = Deno.env.get("OPENROUTER_API_KEY");
    if (!apiKey) throw new Error("OPENROUTER_API_KEY is not set");
    return {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://nowork.app",
        "X-Title": "NoWork",
    };
}

interface ORImage {
    base64: string;
    mimeType: string;
}

type ORContent =
    | { type: "text"; text: string }
    | { type: "image_url"; image_url: { url: string } };

type ORMessage = {
    role: "system" | "user" | "assistant";
    content: string | ORContent[];
};

function imageBlock(img: ORImage): ORContent {
    return {
        type: "image_url",
        image_url: { url: `data:${img.mimeType};base64,${img.base64}` },
    };
}

async function callOR(body: Record<string, unknown>): Promise<string> {
    const res = await fetch(OR_URL, {
        method: "POST",
        headers: orHeaders(),
        body: JSON.stringify(body),
    });
    if (!res.ok) {
        throw new Error(`OpenRouter chat failed (${res.status}): ${await res.text()}`);
    }
    const data = await res.json();
    if (data?.error) {
        throw new Error(`OpenRouter error: ${data.error.message ?? "unknown"}`);
    }
    const content = data?.choices?.[0]?.message?.content;
    if (typeof content === "string") return content;
    if (Array.isArray(content)) {
        return content
            .map((c: any) => (typeof c === "string" ? c : c?.text ?? ""))
            .join("");
    }
    throw new Error("OpenRouter returned no message content");
}

// ----------------------------------------------------------------------------
// Worksheet reasoning
// ----------------------------------------------------------------------------

export interface ReasoningResult {
    images: { index: number; standalone_prompt: string }[];
}

export async function reasonOverWorksheet(params: {
    images: ORImage[];
    action: ActionType;
    mode: HandwritingMode;
    extraContext?: string;
}): Promise<ReasoningResult> {
    const systemPrompt = buildSystemPrompt(
        params.action,
        params.mode,
        params.images.length,
    );

    const userContent: ORContent[] = [];
    if (params.extraContext) {
        userContent.push({ type: "text", text: `Context:\n${params.extraContext}` });
    }
    params.images.forEach((img, i) => {
        userContent.push({ type: "text", text: `[Image index ${i}]` });
        userContent.push(imageBlock(img));
    });

    const text = await callOR({
        model: GEMINI_REASONING,
        temperature: 0.4,
        response_format: {
            type: "json_schema",
            json_schema: {
                name: "worksheet_reasoning",
                strict: true,
                schema: GEMINI_RESPONSE_SCHEMA,
            },
        },
        messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: userContent },
        ] satisfies ORMessage[],
    });

    return parseLooseJson<ReasoningResult>(text);
}

/**
 * Tolerant JSON parser. Handles plain JSON, ```json fences, ``` fences without
 * a language tag, and stray prefix/suffix text by extracting the substring
 * between the first `{` (or `[`) and its matching closer. Logs the raw body
 * on failure so the supabase function logs reveal what went wrong.
 */
function parseLooseJson<T>(raw: string): T {
    const tryParse = (s: string): T | null => {
        try {
            return JSON.parse(s) as T;
        } catch {
            return null;
        }
    };

    let direct = tryParse(raw);
    if (direct) return direct;

    let body = raw.trim();

    // Strip ```json … ``` or ``` … ```
    const fenceMatch = body.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (fenceMatch) {
        const stripped = tryParse(fenceMatch[1].trim());
        if (stripped) return stripped;
        body = fenceMatch[1].trim();
    }

    // Slice from first { or [ to last } or ]
    const start = body.search(/[\[{]/);
    const end = Math.max(body.lastIndexOf("}"), body.lastIndexOf("]"));
    if (start >= 0 && end > start) {
        const sliced = tryParse(body.slice(start, end + 1));
        if (sliced) return sliced;
    }

    console.error("Gemini returned unparseable JSON:", raw.slice(0, 800));
    throw new Error(
        `Gemini reasoning response wasn't JSON. head="${raw.slice(0, 200)}"`,
    );
}

// ----------------------------------------------------------------------------
// Chat turn
// ----------------------------------------------------------------------------

export interface ChatMessage {
    role: "user" | "model";
    content: string;
}

export async function chatTurn(params: {
    history: ChatMessage[];
    userMessage: string;
    systemPrompt?: string;
    contextFiles?: ORImage[];
    webContext?: string;
    kbContext?: string;
    /** Public model label. Raw provider model ids are intentionally not accepted. */
    model?: ModelMode | string;
}): Promise<string> {
    const messages: ORMessage[] = [];
    if (params.systemPrompt) {
        messages.push({ role: "system", content: params.systemPrompt });
    }
    for (const m of params.history) {
        messages.push({
            role: m.role === "model" ? "assistant" : "user",
            content: m.content,
        });
    }

    const userContent: ORContent[] = [{ type: "text", text: params.userMessage }];
    if (params.kbContext) {
        userContent.push({
            type: "text",
            text: `\n\n[Knowledge base context]\n${params.kbContext}`,
        });
    }
    if (params.webContext) {
        userContent.push({
            type: "text",
            text: `\n\n[Live web research]\n${params.webContext}`,
        });
    }
    if (params.contextFiles?.length) {
        for (const f of params.contextFiles) userContent.push(imageBlock(f));
    }
    messages.push({ role: "user", content: userContent });

    return callOR({
        model: resolveModel(params.model),
        temperature: 0.7,
        messages,
    });
}

// ----------------------------------------------------------------------------
// Explainer prompt for Hera
// ----------------------------------------------------------------------------

export async function generateExplainerPrompt(params: {
    topic: string;
    context?: string;
}): Promise<string> {
    const systemPrompt =
        `You are a creative director for educational explainer videos. Given a topic
and any provided context (chat history, KB excerpts, web research), produce a TIGHT
single-paragraph video prompt for a generative video model. Anti-slop: no flashy
effects, no clichés, no AI-isms. Concrete visual metaphors. Pedagogical clarity.
8-12 seconds of footage. Output ONLY the prompt text, no preamble.`;

    const userText = params.context
        ? `Topic: ${params.topic}\n\nContext:\n${params.context}`
        : `Topic: ${params.topic}`;

    const text = await callOR({
        model: GEMINI_REASONING,
        temperature: 0.6,
        messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: userText },
        ] satisfies ORMessage[],
    });

    return text.trim() || params.topic;
}
