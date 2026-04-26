// process-worksheet: core pipeline.
// flow:
//   1. authenticate
//   2. fetch session, inputs, handwriting sample
//   3. download images from storage
//   4. call Gemini for joint reasoning -> per-image standalone prompts
//   5. for each input: call gpt-image-2 with [worksheet, sample?] and the standalone prompt
//   6. upload outputs, insert rows, update session.status
// returns immediately, runs in background via EdgeRuntime.waitUntil

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handleOptions, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { adminClient, authenticate } from "../_shared/supabase.ts";
import { ModelMode, reasonOverWorksheet } from "../_shared/gemini.ts";
import { editWorksheetImage } from "../_shared/openai.ts";
import { ActionType, HandwritingMode } from "../_shared/prompts.ts";
import { blobToBase64, inferMimeFromPath } from "../_shared/utils.ts";
import {
    assertSafeStorageObjectName,
    enumValue,
    HttpError,
    LIMITS,
    readJsonObject,
    requireBlobSize,
    requirePost,
    responseMessage,
    responseStatus,
    sanitizeStoragePathForUser,
    uuid,
} from "../_shared/security.ts";

interface ProcessRequest {
    session_id: string;
    model?: ModelMode;
}

serve(async (req) => {
    const optionsRes = handleOptions(req);
    if (optionsRes) return optionsRes;

    try {
        requirePost(req);
        const auth = await authenticate(req);
        if (!auth) return errorResponse("Unauthorized", 401);

        const reqBody = await readJsonObject<ProcessRequest>(req);
        const session_id = uuid(reqBody.session_id, "session_id");
        const model = enumValue<ModelMode>(
            reqBody.model,
            "model",
            ["fast", "smart"] as const,
            "fast",
        );

        const supabase = adminClient();

        // Verify session ownership and load it
        const { data: session, error: sessionErr } = await supabase
            .from("sessions")
            .select(
                `id, user_id, action, status, mode, handwriting_sample_id,
                 created_at,
                 session_inputs(id, storage_path, "order"),
                 handwriting_samples(id, storage_path, name)`,
            )
            .eq("id", session_id)
            .eq("user_id", auth.userId)
            .maybeSingle();

        if (sessionErr) {
            console.error("Failed to load session:", sessionErr);
            return errorResponse("Failed to load session", 500);
        }
        if (!session) return errorResponse("Session not found", 404);
        if (session.status === "complete") {
            return jsonResponse({ status: session.status, session_id });
        }
        if (session.status === "processing") {
            const inputCount = ((session.session_inputs as any[]) ?? []).length;
            const { count, error: outputCountErr } = await supabase
                .from("session_outputs")
                .select("id", { count: "exact", head: true })
                .eq("session_id", session_id);
            if (outputCountErr) {
                throw new Error(`Output lookup failed: ${outputCountErr.message}`);
            }
            if (inputCount > 0 && (count ?? 0) >= inputCount) {
                await supabase.from("sessions").update({
                    status: "complete",
                    completed_at: new Date().toISOString(),
                }).eq("id", session_id).eq("user_id", auth.userId);
                return jsonResponse({ status: "complete", session_id });
            }
            const startedAt = Date.parse((session as any).created_at ?? "");
            const stale = Number.isFinite(startedAt) &&
                Date.now() - startedAt > 4 * 60 * 1000;
            if (!stale) {
                return jsonResponse({ status: session.status, session_id });
            }
            console.warn(
                `Restarting stale processing session ${session_id} with ${count ?? 0}/${inputCount} outputs`,
            );
        }

        // Mark as processing immediately
        await supabase.from("sessions").update({ status: "processing" }).eq(
            "id",
            session_id,
        ).eq("user_id", auth.userId);

        // Run the pipeline in background
        // @ts-ignore EdgeRuntime is available in supabase edge functions
        EdgeRuntime.waitUntil(runPipeline(session_id, auth.userId, model));

        return jsonResponse({ status: "started", session_id });
    } catch (err) {
        console.error("process-worksheet error:", err);
        return errorResponse(
            responseMessage(err, "Failed to start worksheet processing"),
            responseStatus(err),
        );
    }
});

async function runPipeline(
    sessionId: string,
    userId: string,
    model: ModelMode,
): Promise<void> {
    const supabase = adminClient();
    const t0 = Date.now();
    const stamp = (label: string) => {
        console.log(`[pipeline ${sessionId}] +${Date.now() - t0}ms ${label}`);
    };
    stamp(`start mode=${model}`);

    try {
        // Re-fetch with full data
        const { data: session, error } = await supabase
            .from("sessions")
            .select(
                `id, user_id, action, mode, handwriting_sample_id,
                 session_inputs(id, storage_path, "order"),
                 handwriting_samples(id, user_id, storage_path, name)`,
            )
            .eq("id", sessionId)
            .eq("user_id", userId)
            .single();

        if (error || !session) {
            throw new Error(`Failed to load session: ${error?.message}`);
        }

        const action = assertAction(session.action);
        const mode = assertMode(session.mode);
        const inputs = (session.session_inputs as any[])
            .sort((a, b) => a.order - b.order);

        if (inputs.length === 0) throw new Error("No inputs");
        if (inputs.length > LIMITS.worksheetImages) {
            throw new HttpError(400, "Too many worksheet images");
        }

        // Download all input images
        const downloadedInputs = await Promise.all(
            inputs.map(async (input) => {
                const ownedWorksheetPath = sanitizeStoragePathForUser(
                    input.storage_path,
                    userId,
                    "worksheet input path",
                );
                const safeWorksheetObjectName = assertSafeStorageObjectName(
                    ownedWorksheetPath,
                    "worksheet input path",
                );
                const { data, error: dlErr } = await supabase.storage
                    .from("worksheets-input")
                    .download(safeWorksheetObjectName);
                if (dlErr || !data) {
                    throw new Error(
                        `Failed to download input ${input.id}: ${dlErr?.message}`,
                    );
                }
                requireBlobSize(data, "worksheet image");
                const base64 = await blobToBase64(data);
                return {
                    id: input.id,
                    blob: data,
                    base64,
                    mimeType: inferMimeFromPath(safeWorksheetObjectName),
                };
            }),
        );

        // Download handwriting sample if mode === library
        let sample: { blob: Blob; mimeType: string } | null = null;
        if (mode === "library") {
            const sampleData = (session.handwriting_samples as any) ?? null;
            if (!sampleData) {
                throw new Error(
                    "Library mode requires a handwriting_sample_id on the session",
                );
            }
            if (sampleData.user_id !== userId) {
                throw new HttpError(403, "Handwriting sample is not owned by the current user");
            }
            const ownedSamplePath = sanitizeStoragePathForUser(
                sampleData.storage_path,
                userId,
                "handwriting sample path",
            );
            const safeSampleObjectName = assertSafeStorageObjectName(
                ownedSamplePath,
                "handwriting sample path",
            );
            const { data, error: dlErr } = await supabase.storage
                .from("handwriting")
                .download(safeSampleObjectName);
            if (dlErr || !data) {
                throw new Error(
                    `Failed to download handwriting sample: ${dlErr?.message}`,
                );
            }
            requireBlobSize(data, "handwriting sample");
            sample = {
                blob: data,
                mimeType: inferMimeFromPath(safeSampleObjectName),
            };
        }

        stamp(`downloads done (${downloadedInputs.length} inputs, sample=${sample ? "yes" : "no"})`);

        // Joint reasoning over all inputs
        stamp("calling reasonOverWorksheet (gemini)");
        const reasoning = await reasonOverWorksheet({
            images: downloadedInputs.map((i) => ({
                base64: i.base64,
                mimeType: i.mimeType,
            })),
            action,
            mode,
            modelMode: model,
        });
        stamp(`reasoning done — ${reasoning.images?.length ?? 0} prompts`);

        if (!reasoning.images?.length) {
            throw new Error("Gemini returned no per-image prompts");
        }
        const promptByIndex = validatedPrompts(reasoning, downloadedInputs.length);

        // Sequential per-image dispatch to image-edit model
        for (let i = 0; i < downloadedInputs.length; i++) {
            const input = downloadedInputs[i];
            const prompt = promptByIndex[i];

            stamp(`editWorksheetImage start (i=${i})`);
            const edited = await editWorksheetImage({
                worksheet: input.blob,
                worksheetName: `input-${i}.png`,
                prompt,
                handwritingSample: sample?.blob,
                handwritingSampleName: "handwriting_sample.png",
                mode: model,
            });
            requireBlobSize(edited, "edited worksheet image");
            stamp(`editWorksheetImage done (i=${i}, bytes=${edited.size})`);

            const outputContentType = imageContentType(edited.type);
            const outputExtension = imageExtension(outputContentType);
            const outputPath = sanitizeStoragePathForUser(
                `${userId}/${sessionId}/${i}-${Date.now()}.${outputExtension}`,
                userId,
                "worksheet output path",
            );
            const safeOutputObjectName = assertSafeStorageObjectName(
                outputPath,
                "worksheet output path",
            );
            const { error: uploadErr } = await supabase.storage
                .from("worksheets-output")
                .upload(safeOutputObjectName, edited, {
                    contentType: outputContentType,
                    upsert: false,
                });
            if (uploadErr) {
                throw new Error(`Upload failed: ${uploadErr.message}`);
            }
            stamp(`upload done (i=${i})`);

            await supabase.from("session_outputs").insert({
                session_id: sessionId,
                source_input_id: input.id,
                storage_path: safeOutputObjectName,
                prompt_used: prompt,
            });
            stamp(`db insert done (i=${i})`);
        }

        await supabase.from("sessions").update({
            status: "complete",
            completed_at: new Date().toISOString(),
        }).eq("id", sessionId).eq("user_id", userId);
        stamp("session marked complete");
    } catch (err) {
        const internalMessage = err instanceof Error ? err.message : String(err);
        const publicMessage = pipelinePublicMessage(err);
        console.error(`Pipeline failed for ${sessionId}:`, internalMessage);
        await supabase.from("sessions").update({
            status: "failed",
            error: publicMessage,
            completed_at: new Date().toISOString(),
        }).eq("id", sessionId).eq("user_id", userId);
    }
}

function assertAction(value: unknown): ActionType {
    const allowed: ActionType[] = [
        "correct",
        "complete",
        "fill_out",
        "annotate",
        "schrift_replace",
    ];
    if (typeof value !== "string" || !allowed.includes(value as ActionType)) {
        throw new HttpError(400, "Unsupported worksheet action");
    }
    return value as ActionType;
}

function assertMode(value: unknown): HandwritingMode {
    if (value !== "library" && value !== "adaptive") {
        throw new HttpError(400, "Unsupported handwriting mode");
    }
    return value;
}

function validatedPrompts(
    reasoning: { images?: { index: number; standalone_prompt: string }[] },
    expectedCount: number,
): string[] {
    const prompts = Array<string>(expectedCount).fill("");
    const seen = new Set<number>();
    for (const item of reasoning.images ?? []) {
        if (!Number.isInteger(item.index) || item.index < 0 || item.index >= expectedCount) {
            throw new Error("Gemini returned a prompt with an invalid image index");
        }
        if (seen.has(item.index)) {
            throw new Error("Gemini returned duplicate prompts for one image");
        }
        const prompt = item.standalone_prompt?.trim();
        if (!prompt) throw new Error("Gemini returned an empty image prompt");
        if (prompt.length > LIMITS.promptChars) {
            throw new Error("Gemini returned an oversized image prompt");
        }
        seen.add(item.index);
        prompts[item.index] = prompt;
    }
    if (seen.size !== expectedCount || prompts.some((prompt) => !prompt)) {
        throw new Error("Gemini did not return one prompt for every worksheet image");
    }
    return prompts;
}

function pipelinePublicMessage(err: unknown): string {
    if (err instanceof HttpError) return err.message;
    const message = err instanceof Error ? err.message : String(err);
    const safePrefixes = [
        "No inputs",
        "Library mode requires",
        "Gemini returned",
        "Gemini did not",
        "Image generation is not configured",
        "Unsupported",
    ];
    if (safePrefixes.some((prefix) => message.startsWith(prefix))) {
        return message;
    }
    return "Worksheet processing failed. Please retry with a smaller, clearer image.";
}

function imageContentType(type: string | undefined): string {
    if (type === "image/png" || type === "image/jpeg" || type === "image/webp") {
        return type;
    }
    return "image/png";
}

function imageExtension(contentType: string): string {
    switch (contentType) {
        case "image/jpeg":
            return "jpg";
        case "image/webp":
            return "webp";
        default:
            return "png";
    }
}
