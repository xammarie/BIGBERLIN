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
import { reasonOverWorksheet } from "../_shared/gemini.ts";
import { editWorksheetImage } from "../_shared/openai.ts";
import { ActionType, HandwritingMode } from "../_shared/prompts.ts";
import { blobToBase64, inferMimeFromPath } from "../_shared/utils.ts";

interface ProcessRequest {
    session_id: string;
}

serve(async (req) => {
    const optionsRes = handleOptions(req);
    if (optionsRes) return optionsRes;

    try {
        const auth = await authenticate(req);
        if (!auth) return errorResponse("Unauthorized", 401);

        const { session_id } = (await req.json()) as ProcessRequest;
        if (!session_id) return errorResponse("session_id required", 400);

        const supabase = adminClient();

        // Verify session ownership and load it
        const { data: session, error: sessionErr } = await supabase
            .from("sessions")
            .select(
                `id, user_id, action, status, mode, handwriting_sample_id,
                 session_inputs(id, storage_path, "order"),
                 handwriting_samples(id, storage_path, name)`,
            )
            .eq("id", session_id)
            .eq("user_id", auth.userId)
            .maybeSingle();

        if (sessionErr) return errorResponse(sessionErr.message, 500);
        if (!session) return errorResponse("Session not found", 404);
        if (session.status === "processing" || session.status === "complete") {
            return jsonResponse({ status: session.status, session_id });
        }

        // Mark as processing immediately
        await supabase.from("sessions").update({ status: "processing" }).eq(
            "id",
            session_id,
        );

        // Run the pipeline in background
        // @ts-ignore EdgeRuntime is available in supabase edge functions
        EdgeRuntime.waitUntil(runPipeline(session_id, auth.userId));

        return jsonResponse({ status: "started", session_id });
    } catch (err) {
        console.error("process-worksheet error:", err);
        return errorResponse(
            err instanceof Error ? err.message : String(err),
            500,
        );
    }
});

async function runPipeline(sessionId: string, userId: string): Promise<void> {
    const supabase = adminClient();

    try {
        // Re-fetch with full data
        const { data: session, error } = await supabase
            .from("sessions")
            .select(
                `id, user_id, action, mode, handwriting_sample_id,
                 session_inputs(id, storage_path, "order"),
                 handwriting_samples(id, storage_path, name)`,
            )
            .eq("id", sessionId)
            .single();

        if (error || !session) {
            throw new Error(`Failed to load session: ${error?.message}`);
        }

        const action = session.action as ActionType;
        const mode = session.mode as HandwritingMode;
        const inputs = (session.session_inputs as any[])
            .sort((a, b) => a.order - b.order);

        if (inputs.length === 0) throw new Error("No inputs");

        // Download all input images
        const downloadedInputs = await Promise.all(
            inputs.map(async (input) => {
                const { data, error: dlErr } = await supabase.storage
                    .from("worksheets-input")
                    .download(input.storage_path);
                if (dlErr || !data) {
                    throw new Error(
                        `Failed to download input ${input.id}: ${dlErr?.message}`,
                    );
                }
                const base64 = await blobToBase64(data);
                return {
                    id: input.id,
                    blob: data,
                    base64,
                    mimeType: inferMimeFromPath(input.storage_path),
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
            const { data, error: dlErr } = await supabase.storage
                .from("handwriting")
                .download(sampleData.storage_path);
            if (dlErr || !data) {
                throw new Error(
                    `Failed to download handwriting sample: ${dlErr?.message}`,
                );
            }
            sample = {
                blob: data,
                mimeType: inferMimeFromPath(sampleData.storage_path),
            };
        }

        // Joint reasoning over all inputs
        const reasoning = await reasonOverWorksheet({
            images: downloadedInputs.map((i) => ({
                base64: i.base64,
                mimeType: i.mimeType,
            })),
            action,
            mode,
        });

        if (!reasoning.images?.length) {
            throw new Error("Gemini returned no per-image prompts");
        }

        // Sequential per-image dispatch to gpt-image-2
        for (let i = 0; i < downloadedInputs.length; i++) {
            const input = downloadedInputs[i];
            const promptObj = reasoning.images.find((p) => p.index === i);
            if (!promptObj) {
                console.warn(`No prompt for index ${i}, skipping`);
                continue;
            }

            const edited = await editWorksheetImage({
                worksheet: input.blob,
                worksheetName: `input-${i}.png`,
                prompt: promptObj.standalone_prompt,
                handwritingSample: sample?.blob,
                handwritingSampleName: "handwriting_sample.png",
            });

            const outputPath = `${userId}/${sessionId}/${i}-${Date.now()}.png`;
            const { error: uploadErr } = await supabase.storage
                .from("worksheets-output")
                .upload(outputPath, edited, {
                    contentType: "image/png",
                    upsert: false,
                });
            if (uploadErr) {
                throw new Error(`Upload failed: ${uploadErr.message}`);
            }

            await supabase.from("session_outputs").insert({
                session_id: sessionId,
                source_input_id: input.id,
                storage_path: outputPath,
                prompt_used: promptObj.standalone_prompt,
            });
        }

        await supabase.from("sessions").update({
            status: "complete",
            completed_at: new Date().toISOString(),
        }).eq("id", sessionId);
    } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        console.error(`Pipeline failed for ${sessionId}:`, message);
        await supabase.from("sessions").update({
            status: "failed",
            error: message,
            completed_at: new Date().toISOString(),
        }).eq("id", sessionId);
    }
}
