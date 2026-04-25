import {
    ActionType,
    buildSystemPrompt,
    GEMINI_RESPONSE_SCHEMA,
    HandwritingMode,
} from "./prompts.ts";

export const GEMINI_PRO = "gemini-3.1-pro";
export const GEMINI_FLASH = "gemini-3.1-flash";
export const GEMINI_FLASH_LITE = "gemini-3.1-flash-lite";

interface GeminiImage {
    base64: string;
    mimeType: string;
}

export interface ReasoningResult {
    images: { index: number; standalone_prompt: string }[];
}

export async function reasonOverWorksheet(params: {
    images: GeminiImage[];
    action: ActionType;
    mode: HandwritingMode;
    extraContext?: string;
}): Promise<ReasoningResult> {
    const apiKey = Deno.env.get("GOOGLE_API_KEY")!;
    const systemPrompt = buildSystemPrompt(
        params.action,
        params.mode,
        params.images.length,
    );

    const userParts: any[] = [];
    if (params.extraContext) {
        userParts.push({ text: `Context:\n${params.extraContext}` });
    }
    params.images.forEach((img, i) => {
        userParts.push({ text: `[Image index ${i}]` });
        userParts.push({
            inline_data: { mime_type: img.mimeType, data: img.base64 },
        });
    });

    const body = {
        system_instruction: { parts: [{ text: systemPrompt }] },
        contents: [{ role: "user", parts: userParts }],
        generationConfig: {
            response_mime_type: "application/json",
            response_schema: GEMINI_RESPONSE_SCHEMA,
            temperature: 0.4,
        },
    };

    const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_PRO}:generateContent?key=${apiKey}`,
        {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(body),
        },
    );

    if (!res.ok) {
        throw new Error(`Gemini reasoning failed: ${await res.text()}`);
    }

    const data = await res.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text) throw new Error("Gemini returned no content");
    return JSON.parse(text);
}

export interface ChatMessage {
    role: "user" | "model";
    content: string;
}

export async function chatTurn(params: {
    history: ChatMessage[];
    userMessage: string;
    systemPrompt?: string;
    contextFiles?: GeminiImage[];
    webContext?: string;
    kbContext?: string;
    model?: string;
}): Promise<string> {
    const apiKey = Deno.env.get("GOOGLE_API_KEY")!;
    const model = params.model ?? GEMINI_FLASH;

    const contents = params.history.map((m) => ({
        role: m.role === "model" ? "model" : "user",
        parts: [{ text: m.content }],
    }));

    const userParts: any[] = [{ text: params.userMessage }];
    if (params.kbContext) {
        userParts.push({
            text: `\n\n[Knowledge base context]\n${params.kbContext}`,
        });
    }
    if (params.webContext) {
        userParts.push({
            text: `\n\n[Live web research]\n${params.webContext}`,
        });
    }
    if (params.contextFiles?.length) {
        params.contextFiles.forEach((f) =>
            userParts.push({
                inline_data: { mime_type: f.mimeType, data: f.base64 },
            })
        );
    }
    contents.push({ role: "user", parts: userParts });

    const body: any = {
        contents,
        generationConfig: { temperature: 0.7 },
    };
    if (params.systemPrompt) {
        body.system_instruction = { parts: [{ text: params.systemPrompt }] };
    }

    const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
        {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(body),
        },
    );

    if (!res.ok) {
        throw new Error(`Gemini chat failed: ${await res.text()}`);
    }
    const data = await res.json();
    return data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
}

export async function generateExplainerPrompt(params: {
    topic: string;
    context?: string;
}): Promise<string> {
    const apiKey = Deno.env.get("GOOGLE_API_KEY")!;
    const systemPrompt =
        `You are a creative director for educational explainer videos. Given a topic
and any provided context (chat history, KB excerpts, web research), produce a TIGHT
single-paragraph video prompt for a generative video model. Anti-slop: no flashy
effects, no clichés, no AI-isms. Concrete visual metaphors. Pedagogical clarity.
8-12 seconds of footage. Output ONLY the prompt text, no preamble.`;

    const userText = params.context
        ? `Topic: ${params.topic}\n\nContext:\n${params.context}`
        : `Topic: ${params.topic}`;

    const body = {
        system_instruction: { parts: [{ text: systemPrompt }] },
        contents: [{ role: "user", parts: [{ text: userText }] }],
        generationConfig: { temperature: 0.6 },
    };

    const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_PRO}:generateContent?key=${apiKey}`,
        {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(body),
        },
    );
    if (!res.ok) {
        throw new Error(`Gemini explainer prompt failed: ${await res.text()}`);
    }
    const data = await res.json();
    return data?.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ??
        params.topic;
}
