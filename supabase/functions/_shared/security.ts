export class HttpError extends Error {
    status: number;

    constructor(status: number, message: string) {
        super(message);
        this.name = "HttpError";
        this.status = status;
    }
}

export const LIMITS = {
    chatMessageChars: 4_000,
    chatHistoryMessages: 40,
    storedChatMessages: 80,
    worksheetImages: 8,
    attachmentImages: 8,
    imageBytes: 12 * 1024 * 1024,
    promptChars: 8_000,
    topicChars: 1_000,
    searchQueryChars: 500,
    titleChars: 80,
};

const UUID_RE =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const STORAGE_PATH_RE = /^[A-Za-z0-9._/-]+$/;
const JOB_ID_RE = /^[A-Za-z0-9._:-]{1,200}$/;

export function requirePost(req: Request): void {
    if (req.method !== "POST") {
        throw new HttpError(405, "Method not allowed");
    }
}

export async function readJsonObject<T>(req: Request): Promise<T> {
    try {
        const body = await req.json();
        if (!body || typeof body !== "object" || Array.isArray(body)) {
            throw new HttpError(400, "JSON object body required");
        }
        return body as T;
    } catch (err) {
        if (err instanceof HttpError) throw err;
        throw new HttpError(400, "Invalid JSON body");
    }
}

export function uuid(value: unknown, field: string): string {
    if (typeof value !== "string" || !UUID_RE.test(value)) {
        throw new HttpError(400, `${field} must be a valid UUID`);
    }
    return value.toLowerCase();
}

export function optionalUuid(
    value: unknown,
    field: string,
): string | undefined {
    if (value === undefined || value === null || value === "") return undefined;
    return uuid(value, field);
}

export function text(
    value: unknown,
    field: string,
    maxChars: number,
    options: { required?: boolean } = { required: true },
): string {
    if (value === undefined || value === null) {
        if (options.required === false) return "";
        throw new HttpError(400, `${field} required`);
    }
    if (typeof value !== "string") {
        throw new HttpError(400, `${field} must be a string`);
    }
    const trimmed = value.trim();
    if (options.required !== false && !trimmed) {
        throw new HttpError(400, `${field} required`);
    }
    if (trimmed.length > maxChars) {
        throw new HttpError(400, `${field} is too long`);
    }
    return trimmed;
}

export function enumValue<T extends string>(
    value: unknown,
    field: string,
    allowed: readonly T[],
    fallback?: T,
): T {
    if ((value === undefined || value === null || value === "") && fallback) {
        return fallback;
    }
    if (typeof value !== "string" || !allowed.includes(value as T)) {
        throw new HttpError(400, `${field} has an invalid value`);
    }
    return value as T;
}

export function boundedInt(
    value: unknown,
    field: string,
    fallback: number,
    min: number,
    max: number,
): number {
    if (value === undefined || value === null || value === "") return fallback;
    if (typeof value !== "number" || !Number.isInteger(value)) {
        throw new HttpError(400, `${field} must be an integer`);
    }
    return Math.min(max, Math.max(min, value));
}

export function jobId(value: unknown): string {
    if (typeof value !== "string" || !JOB_ID_RE.test(value)) {
        throw new HttpError(400, "job_id has an invalid value");
    }
    return value;
}

export function userStoragePath(
    value: unknown,
    userId: string,
    field = "storage path",
): string {
    if (typeof value !== "string") {
        throw new HttpError(400, `${field} must be a string`);
    }
    const path = value.trim();
    const ownerPrefix = `${userId.toLowerCase()}/`;
    if (
        path.length === 0 ||
        path.length > 512 ||
        path.startsWith("/") ||
        path.includes("..") ||
        path.includes("//") ||
        !path.startsWith(ownerPrefix) ||
        !STORAGE_PATH_RE.test(path)
    ) {
        throw new HttpError(403, `${field} is not owned by the current user`);
    }
    return path;
}

export function sanitizeStoragePathForUser(
    value: unknown,
    userId: string,
    field = "storage path",
): string {
    return userStoragePath(value, userId, field);
}

export function userStoragePathArray(
    value: unknown,
    userId: string,
    field: string,
    maxItems: number,
): string[] {
    if (value === undefined || value === null) return [];
    if (!Array.isArray(value)) {
        throw new HttpError(400, `${field} must be an array`);
    }
    if (value.length > maxItems) {
        throw new HttpError(400, `${field} contains too many items`);
    }
    return [
        ...new Set(value.map((path) =>
            sanitizeStoragePathForUser(path, userId, field)
        )),
    ];
}

export function requireBlobSize(blob: Blob, label: string): void {
    if (blob.size <= 0) throw new HttpError(400, `${label} is empty`);
    if (blob.size > LIMITS.imageBytes) {
        throw new HttpError(413, `${label} is too large`);
    }
}

export function responseMessage(err: unknown, fallback: string): string {
    if (err instanceof HttpError) return err.message;
    return fallback;
}

export function responseStatus(err: unknown): number {
    if (err instanceof HttpError) return err.status;
    return 500;
}
