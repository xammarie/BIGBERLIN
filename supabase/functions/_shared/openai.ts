// Image edits default to OpenRouter because the hackathon project can run there
// without OpenAI org verification. Set IMAGE_PROVIDER=openai to prefer the
// official Images API when the OpenAI org is verified, or IMAGE_PROVIDER=auto
// to try the other provider after a provider failure.

import { blobToBase64 } from "./utils.ts";

const OPENAI_IMAGES_EDIT_URL = "https://api.openai.com/v1/images/edits";
const OPENAI_IMAGE_MODEL = Deno.env.get("OPENAI_IMAGE_MODEL") ?? "gpt-image-2";
const IMAGE_PROVIDER = (Deno.env.get("IMAGE_PROVIDER") ?? "openrouter")
    .toLowerCase();
const MAX_FETCHED_IMAGE_BYTES = 12 * 1024 * 1024;

// OpenRouter fallback models, picked by `mode`.
const IMAGE_MODEL_FAST = "google/gemini-3.1-flash-image-preview";
const IMAGE_MODEL_SMART = "openai/gpt-5.4-image-2";
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

export type ImageEditMode = "fast" | "smart";

export interface EditImageParams {
    worksheet: Blob;
    worksheetName?: string;
    prompt: string;
    handwritingSample?: Blob;
    handwritingSampleName?: string;
    size?: "auto" | "1024x1024" | "1024x1536" | "1536x1024";
    quality?: "low" | "medium" | "high" | "auto";
    mode?: ImageEditMode;
}

interface ORImage {
    type: string;
    image_url?: { url: string };
}

interface ORResponse {
    choices?: {
        message?: {
            content?: string;
            images?: ORImage[];
        };
    }[];
    error?: { message?: string; code?: string | number };
}

interface OpenAIImageResponse {
    data?: { b64_json?: string; url?: string }[];
    error?: { message?: string; code?: string | number };
}

export async function editWorksheetImage(
    params: EditImageParams,
): Promise<Blob> {
    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    const openrouterKey = Deno.env.get("OPENROUTER_API_KEY");
    const preferOpenAI = IMAGE_PROVIDER === "openai" || !openrouterKey;
    const allowCrossProviderFallback = IMAGE_PROVIDER === "auto";

    if (preferOpenAI && openaiKey) {
        try {
            return await editWithOpenAI(params, openaiKey);
        } catch (err) {
            const message = err instanceof Error ? err.message : String(err);
            console.error(
                "OpenAI image edit failed; falling back to OpenRouter:",
                message,
            );
            if (!openrouterKey || !allowCrossProviderFallback) throw err;
        }
    }

    try {
        return await editWithOpenRouter(params);
    } catch (openrouterErr) {
        if (!openaiKey || preferOpenAI || !allowCrossProviderFallback) {
            throw openrouterErr;
        }

        const message = openrouterErr instanceof Error
            ? openrouterErr.message
            : String(openrouterErr);
        console.error(
            "OpenRouter image edit failed; falling back to OpenAI:",
            message,
        );
        return editWithOpenAI(params, openaiKey);
    }
}

async function editWithOpenAI(
    params: EditImageParams,
    apiKey: string,
): Promise<Blob> {
    const form = new FormData();
    form.append("model", OPENAI_IMAGE_MODEL);
    form.append("prompt", params.prompt);
    form.append("quality", params.quality ?? "high");
    form.append("input_fidelity", "high");
    form.append("size", params.size ?? "auto");
    form.append("output_format", "png");
    form.append("n", "1");

    form.append(
        "image[]",
        params.worksheet,
        safeImageFilename(
            params.worksheetName,
            params.worksheet.type,
            "worksheet.png",
        ),
    );
    if (params.handwritingSample) {
        form.append(
            "image[]",
            params.handwritingSample,
            safeImageFilename(
                params.handwritingSampleName,
                params.handwritingSample.type,
                "handwriting-sample.png",
            ),
        );
    }

    const res = await fetch(OPENAI_IMAGES_EDIT_URL, {
        method: "POST",
        headers: {
            Authorization: `Bearer ${apiKey}`,
            Accept: "application/json",
        },
        body: form,
    });

    const requestId = res.headers.get("x-request-id") ?? undefined;
    const raw = await res.text();
    let data: OpenAIImageResponse | null = null;
    try {
        data = JSON.parse(raw) as OpenAIImageResponse;
    } catch {
        // handled below with raw response head
    }

    if (!res.ok) {
        const providerMessage = data?.error?.message ?? raw.slice(0, 500);
        const statusLabel = requestId
            ? `${res.status}, request ${requestId}`
            : String(res.status);
        throw new Error(
            `OpenAI image edit failed (${statusLabel}): ${providerMessage}`,
        );
    }

    if (data?.error) {
        throw new Error(
            `OpenAI image edit error${requestId ? ` (${requestId})` : ""}: ${
                data.error.message ?? "unknown"
            }`,
        );
    }

    const b64 = data?.data?.[0]?.b64_json;
    if (typeof b64 === "string" && b64.length > 0) {
        return base64ToBlob(b64, "image/png");
    }

    const imageUrl = data?.data?.[0]?.url;
    if (typeof imageUrl === "string" && imageUrl.length > 0) {
        return await fetchImageBlob(imageUrl);
    }

    console.error("OpenAI image response (no image extracted):", {
        requestId,
        length: raw.length,
        head: raw.slice(0, 800),
    });
    throw new Error(
        `OpenAI returned no image${requestId ? ` (request ${requestId})` : ""}`,
    );
}

async function editWithOpenRouter(params: EditImageParams): Promise<Blob> {
    const apiKey = Deno.env.get("OPENROUTER_API_KEY");
    if (!apiKey) {
        throw new Error(
            "Image generation is not configured: OPENAI_API_KEY or OPENROUTER_API_KEY is required",
        );
    }

    const worksheetB64 = await blobToBase64(params.worksheet);
    const worksheetMime = params.worksheet.type || "image/png";

    const userContent: unknown[] = [
        { type: "text", text: params.prompt },
        {
            type: "image_url",
            image_url: { url: `data:${worksheetMime};base64,${worksheetB64}` },
        },
    ];

    if (params.handwritingSample) {
        const sampleB64 = await blobToBase64(params.handwritingSample);
        const sampleMime = params.handwritingSample.type || "image/png";
        userContent.push({
            type: "image_url",
            image_url: { url: `data:${sampleMime};base64,${sampleB64}` },
        });
    }

    const model = params.mode === "smart" ? IMAGE_MODEL_SMART : IMAGE_MODEL_FAST;
    const body = {
        model,
        modalities: ["image", "text"],
        messages: [{ role: "user", content: userContent }],
    };

    const res = await fetch(OPENROUTER_URL, {
        method: "POST",
        headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
            Accept: "text/event-stream, application/json",
            "HTTP-Referer": "https://nowork.app",
            "X-Title": "NoWork",
        },
        // OR returns image-gen models as SSE regardless of stream flag, so
        // we just always parse the body as text and handle both shapes.
        body: JSON.stringify({ ...body, stream: true }),
    });

    if (!res.ok) {
        throw new Error(
            `OpenRouter image edit failed (${res.status}): ${await res.text()}`,
        );
    }

    const raw = await res.text();
    const imageUrl = extractImageUrl(raw);
    if (!imageUrl) {
        // Log the body so we can fix forward without burning another image gen.
        console.error("OR image-gen response (no image extracted):", {
            length: raw.length,
            head: raw.slice(0, 800),
            tail: raw.slice(Math.max(0, raw.length - 400)),
        });
        throw new Error(
            `OpenRouter returned no image. body[0..400]="${raw.slice(0, 400)}"`,
        );
    }

    return dataUrlToPngBlob(imageUrl);
}

/**
 * Extracts the generated image URL from an OpenRouter response. Handles three
 * shapes because OR's image-gen behaviour is poorly documented:
 *   1. Plain JSON body (non-streamed)
 *   2. SSE stream of `data: {...}` chunks with `delta.images[]` or `message.images[]`
 *   3. Anything else — a regex scan that pulls the first `data:image/...;base64,...`
 *      URI out of the raw bytes. The base64 alphabet is unambiguous in JSON, so
 *      this is robust even if OR moves the field around.
 */
function extractImageUrl(body: string): string | null {
    const trimmed = body.trim();
    if (!trimmed) return null;

    // 1. Plain JSON
    if (trimmed.startsWith("{")) {
        try {
            const data = JSON.parse(trimmed) as ORResponse;
            if (data.error) throw new Error(data.error.message ?? "unknown");
            const url = data.choices?.[0]?.message?.images?.[0]?.image_url?.url;
            if (typeof url === "string" && url.startsWith("data:image")) return url;
        } catch {
            // fall through
        }
    }

    // 2. SSE: keep the last data:image we see; surface mid-stream errors loudly.
    let imageUrl: string | null = null;
    for (const rawLine of body.split(/\r?\n/)) {
        const line = rawLine.trim();
        // SSE comment lines (`: OPENROUTER PROCESSING`) and blank lines: skip
        if (!line.startsWith("data:")) continue;
        const payload = line.slice(5).trim();
        if (!payload || payload === "[DONE]") continue;
        let chunk: any;
        try {
            chunk = JSON.parse(payload);
        } catch {
            continue;
        }
        // Mid-stream error frame
        const err = chunk?.error ?? chunk?.choices?.[0]?.error;
        if (err) {
            throw new Error(
                `OpenRouter mid-stream error: ${err.message ?? JSON.stringify(err)}`,
            );
        }
        const url =
            chunk?.choices?.[0]?.message?.images?.[0]?.image_url?.url ??
            chunk?.choices?.[0]?.delta?.images?.[0]?.image_url?.url ??
            chunk?.message?.images?.[0]?.image_url?.url;
        if (typeof url === "string" && url.startsWith("data:image")) {
            imageUrl = url;
        }
    }
    if (imageUrl) return imageUrl;

    // 3. Last-ditch regex over the raw body. data:image/...;base64,XXX[/=]+
    //    Captures whatever PNG/JPEG/WebP the model emits.
    const match = body.match(
        /data:image\/(?:png|jpeg|jpg|webp);base64,[A-Za-z0-9+/=]+/,
    );
    return match ? match[0] : null;
}

function dataUrlToPngBlob(dataUrl: string): Blob {
    // Expected: data:image/png;base64,XXXX  (model may emit jpeg/webp too)
    const match = /^data:([^;]+);base64,(.+)$/.exec(dataUrl);
    if (!match) {
        throw new Error("OpenRouter returned a malformed image data URL");
    }
    const mime = match[1] || "image/png";
    const b64 = match[2];
    return base64ToBlob(b64, mime);
}

function base64ToBlob(b64: string, mime: string): Blob {
    const binary = atob(b64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return new Blob([bytes], { type: mime });
}

async function fetchImageBlob(url: string): Promise<Blob> {
    const safeUrl = providerImageUrl(url);
    const res = await fetch(safeUrl);
    if (!res.ok) {
        throw new Error(
            `Image URL fetch failed (${res.status}): ${await res.text()}`,
        );
    }
    const blob = await res.blob();
    const contentType = res.headers.get("content-type") ?? blob.type ?? "image/png";
    if (!contentType.startsWith("image/") || blob.size > MAX_FETCHED_IMAGE_BYTES) {
        throw new Error("Image URL response was not a bounded image");
    }
    return new Blob([blob], { type: contentType });
}

function providerImageUrl(url: string): string {
    const parsed = new URL(url);
    const host = parsed.hostname.toLowerCase();
    const allowedHost = host.endsWith(".openai.com") ||
        host.endsWith(".oaistatic.com") ||
        host.endsWith(".blob.core.windows.net");
    if (parsed.protocol !== "https:" || !allowedHost) {
        throw new Error("OpenAI returned an untrusted image URL");
    }
    return parsed.toString();
}

function safeImageFilename(
    requestedName: string | undefined,
    mimeType: string | undefined,
    fallback: string,
): string {
    const trimmed = requestedName?.trim();
    if (trimmed && /^[A-Za-z0-9._-]{1,120}$/.test(trimmed)) return trimmed;
    const ext = extensionForMime(mimeType);
    return fallback.replace(/\.[A-Za-z0-9]+$/, `.${ext}`);
}

function extensionForMime(mimeType: string | undefined): string {
    switch (mimeType) {
        case "image/jpeg":
        case "image/jpg":
            return "jpg";
        case "image/webp":
            return "webp";
        default:
            return "png";
    }
}
