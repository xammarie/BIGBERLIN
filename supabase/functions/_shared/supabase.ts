import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

export function adminClient(): SupabaseClient {
    return createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
        { auth: { persistSession: false } },
    );
}

export function userClient(authHeader: string): SupabaseClient {
    return createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_ANON_KEY")!,
        {
            global: { headers: { Authorization: authHeader } },
            auth: { persistSession: false },
        },
    );
}

export async function authenticate(
    req: Request,
): Promise<{ userId: string; authHeader: string } | null> {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return null;

    const client = userClient(authHeader);
    const { data: { user }, error } = await client.auth.getUser();
    if (error || !user) return null;

    return { userId: user.id, authHeader };
}
