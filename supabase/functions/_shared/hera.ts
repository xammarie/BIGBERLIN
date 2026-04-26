// Hera video generation API wrapper.
// Docs: https://docs.hera.video/api-reference/introduction
// API shape inferred — adjust endpoint paths once docs are confirmed at venue.

const HERA_BASE = "https://api.hera.video/v1";

export interface HeraVideoJob {
    jobId: string;
    status: "queued" | "processing" | "complete" | "failed";
    videoUrl?: string;
    error?: string;
}

export async function startVideoGeneration(params: {
    prompt: string;
    durationSeconds?: number;
    resolution?: "720p" | "1080p";
}): Promise<{ jobId: string }> {
    const apiKey = Deno.env.get("HERA_API_KEY");
    if (!apiKey) throw new Error("HERA_API_KEY is not set");
    const res = await fetch(`${HERA_BASE}/videos`, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
            prompt: params.prompt,
            duration: params.durationSeconds ?? 8,
            resolution: params.resolution ?? "720p",
        }),
    });
    if (!res.ok) {
        throw new Error(`Hera start failed: ${await res.text()}`);
    }
    const data = await res.json();
    const jobId = data.id ?? data.job_id ?? data.jobId;
    if (typeof jobId !== "string" || jobId.length === 0) {
        throw new Error("Hera start returned no job id");
    }
    return { jobId };
}

export async function getVideoStatus(jobId: string): Promise<HeraVideoJob> {
    const apiKey = Deno.env.get("HERA_API_KEY");
    if (!apiKey) throw new Error("HERA_API_KEY is not set");
    const res = await fetch(`${HERA_BASE}/videos/${jobId}`, {
        headers: { Authorization: `Bearer ${apiKey}` },
    });
    if (!res.ok) throw new Error(`Hera status failed: ${await res.text()}`);
    const data = await res.json();
    return {
        jobId,
        status: data.status,
        videoUrl: data.video_url ?? data.url,
        error: data.error,
    };
}
