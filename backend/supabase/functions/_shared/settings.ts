// Configuration lookup: an Edge Function secret (Deno.env) wins; otherwise the same name, lower-cased,
// in the database's private.settings table (readable only through the service-role-only RPC
// public.service_setting). This lets keys be set with SQL — no dashboard visit required — and lets
// the database triggers and the functions share one copy of PUSH_WEBHOOK_SECRET.
import { adminClient } from "./supabase.ts";

const cache = new Map<string, { value: string; at: number }>();

export async function setting(name: string): Promise<string | undefined> {
  const env = Deno.env.get(name);
  if (env) return env;
  const hit = cache.get(name);
  if (hit && Date.now() - hit.at < 60_000) return hit.value;
  try {
    const { data } = await adminClient().rpc("service_setting", { p_key: name.toLowerCase() });
    if (typeof data === "string" && data.length > 0) {
      cache.set(name, { value: data, at: Date.now() });
      return data;
    }
  } catch (e) {
    console.error("service_setting", name, e);
  }
  return undefined;
}
