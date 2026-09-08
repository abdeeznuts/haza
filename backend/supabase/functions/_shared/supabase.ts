import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL")!;
const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/** Client that acts as the calling user (RLS applies). */
export function userClient(req: Request): SupabaseClient {
  const auth = req.headers.get("Authorization") ?? "";
  return createClient(url, anon, { global: { headers: { Authorization: auth } } });
}

/** Privileged client for server-side reads/writes (bypasses RLS — use narrowly). */
export function adminClient(): SupabaseClient {
  return createClient(url, serviceRole, { auth: { persistSession: false } });
}

export async function requireUser(req: Request): Promise<{ id: string; client: SupabaseClient }> {
  const client = userClient(req);
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) throw new HttpError(401, "not signed in");
  return { id: data.user.id, client };
}

export class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Connection": "keep-alive" },
  });
}

export function handle(fn: (req: Request) => Promise<Response>): (req: Request) => Promise<Response> {
  return async (req) => {
    try {
      return await fn(req);
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.message }, e.status);
      console.error(e);
      return json({ error: "internal" }, 500);
    }
  };
}
