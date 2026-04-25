export interface TavilyResult {
    title: string;
    url: string;
    content: string;
    score?: number;
}

export async function tavilySearch(params: {
    query: string;
    maxResults?: number;
    depth?: "basic" | "advanced";
    includeAnswer?: boolean;
    timeRange?: "day" | "week" | "month" | "year";
}): Promise<{ answer?: string; results: TavilyResult[] }> {
    const apiKey = Deno.env.get("TAVILY_API_KEY")!;

    const body: Record<string, unknown> = {
        query: params.query,
        max_results: params.maxResults ?? 5,
        search_depth: params.depth ?? "basic",
        include_answer: params.includeAnswer ?? true,
    };
    if (params.timeRange) body.time_range = params.timeRange;

    const res = await fetch("https://api.tavily.com/search", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify(body),
    });

    if (!res.ok) {
        throw new Error(`Tavily search failed: ${await res.text()}`);
    }
    const data = await res.json();
    return {
        answer: data.answer,
        results: data.results ?? [],
    };
}

export async function tavilyExtract(params: {
    urls: string[];
    extractDepth?: "basic" | "advanced";
}): Promise<Array<{ url: string; rawContent: string }>> {
    const apiKey = Deno.env.get("TAVILY_API_KEY")!;
    const res = await fetch("https://api.tavily.com/extract", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
            urls: params.urls,
            extract_depth: params.extractDepth ?? "basic",
        }),
    });
    if (!res.ok) {
        throw new Error(`Tavily extract failed: ${await res.text()}`);
    }
    const data = await res.json();
    return (data.results ?? []).map((r: any) => ({
        url: r.url,
        rawContent: r.raw_content,
    }));
}
