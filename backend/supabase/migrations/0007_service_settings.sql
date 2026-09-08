-- Edge Functions read configuration from Deno.env first and fall back to private.settings through this
-- service-role-only RPC (see functions/_shared/settings.ts). Keys are the lower-cased secret names:
--   livekit_url, livekit_api_key, livekit_api_secret, push_webhook_secret,
--   apns_team_id, apns_key_id, apns_private_key, apns_bundle_id, apns_env
-- Set one with:  insert into private.settings values ('livekit_url', 'wss://…') on conflict (key) do update set value = excluded.value;
create or replace function public.service_setting(p_key text)
returns text language sql stable security definer set search_path = private, public as $$
  select s.value from private.settings s where s.key = p_key;
$$;
revoke execute on function public.service_setting(text) from public, anon, authenticated;
grant execute on function public.service_setting(text) to service_role;

insert into private.settings (key, value) values ('apns_bundle_id', 'app.haza.ios'), ('apns_env', 'sandbox')
  on conflict (key) do nothing;
