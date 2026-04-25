const OPENAI_IMAGE_MODEL = "gpt-image-2";

export interface EditImageParams {
    worksheet: Blob;
    worksheetName?: string;
    prompt: string;
    handwritingSample?: Blob;
    handwritingSampleName?: string;
    size?: "auto" | "1024x1024" | "1024x1536" | "1536x1024";
    quality?: "low" | "medium" | "high" | "auto";
}

export async function editWorksheetImage(
    params: EditImageParams,
): Promise<Blob> {
    const apiKey = Deno.env.get("OPENAI_API_KEY")!;

    const form = new FormData();
    form.append("model", OPENAI_IMAGE_MODEL);
    form.append(
        "image[]",
        params.worksheet,
        params.worksheetName ?? "worksheet.png",
    );
    if (params.handwritingSample) {
        form.append(
            "image[]",
            params.handwritingSample,
            params.handwritingSampleName ?? "handwriting_sample.png",
        );
    }
    form.append("prompt", params.prompt);
    form.append("size", params.size ?? "auto");
    form.append("quality", params.quality ?? "high");

    const res = await fetch("https://api.openai.com/v1/images/edits", {
        method: "POST",
        headers: { Authorization: `Bearer ${apiKey}` },
        body: form,
    });

    if (!res.ok) {
        throw new Error(`OpenAI image edit failed: ${await res.text()}`);
    }

    const data = await res.json();
    const b64 = data?.data?.[0]?.b64_json;
    if (!b64) throw new Error("OpenAI returned no image");
    const binary = atob(b64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return new Blob([bytes], { type: "image/png" });
}
