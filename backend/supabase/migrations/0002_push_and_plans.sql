-- Push notifications for pings / live plans / referral rewards, crew join by code, plan go-live.

create extension if not exists pg_net;

-- APNs device tokens for ordinary alert pushes (the PTT token lives in talk_members).
create table public.device_tokens (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  token      text not null,
  platform   text not null default 'ios' check (platform in ('ios', 'android')),
  environment text not null default 'production' check (environment in ('production', 'sandbox')),
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);
alter table public.device_tokens enable row level security;
create policy device_tokens_owner on public.device_tokens for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Join a crew with its invite code.
create or replace function public.join_crew(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select id into cid from public.crews where invite_code = upper(trim(p_code));
  if cid is null then raise exception 'unknown crew code'; end if;
  insert into public.crew_members (crew_id, user_id) values (cid, auth.uid()) on conflict do nothing;
  return cid;
end;
$$;
revoke execute on function public.join_crew(text) from anon;

-- Creator (or a crew admin/owner) flips a plan live; everyone going gets a push via the webhook below.
create or replace function public.go_live(p_plan uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d public.planned_drives%rowtype;
begin
  select * into d from public.planned_drives where id = p_plan;
  if not found then raise exception 'no such plan'; end if;
  if d.creator_id <> auth.uid() and not exists (
       select 1 from public.crew_members m where m.crew_id = d.crew_id and m.user_id = auth.uid() and m.role in ('owner', 'admin')) then
    raise exception 'only the creator or a crew admin can start this drive';
  end if;
  update public.planned_drives set status = 'live' where id = p_plan;
end;
$$;
revoke execute on function public.go_live(uuid) from anon;

-- Server-only view the push function uses (bypasses RLS via service role).
create or replace function public.plan_participants(p_plan uuid)
returns table (user_id uuid) language sql stable security definer set search_path = public as $$
  select r.user_id from public.plan_rsvps r where r.plan_id = p_plan and r.status in ('going', 'maybe');
$$;
revoke execute on function public.plan_participants(uuid) from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Webhooks → push-notify edge function, authenticated by a shared secret kept in a private,
-- non-API schema (applied as haza_private_settings). Rotate: update private.settings + the
-- PUSH_WEBHOOK_SECRET edge-function secret together.
-- ---------------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.settings (key text primary key, value text not null);
revoke all on private.settings from public, anon, authenticated;
insert into private.settings (key, value) values ('push_webhook_secret', '<see backend/README.md>')
  on conflict (key) do nothing;

create or replace function public.notify_push()
returns trigger language plpgsql security definer set search_path = public, private as $$
declare
  secret text;
  body jsonb;
begin
  select value into secret from private.settings where key = 'push_webhook_secret';
  if secret is null or secret = '' then return coalesce(new, old); end if;
  body := jsonb_build_object('type', tg_op, 'table', tg_table_name,
                             'record', to_jsonb(new), 'old_record', to_jsonb(old));
  perform net.http_post(
    url := 'https://ooeykcnrnvneklwoxyti.supabase.co/functions/v1/push-notify',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', secret),
    body := body,
    timeout_milliseconds := 5000);
  return coalesce(new, old);
end;
$$;
revoke execute on function public.notify_push() from anon, authenticated;

create trigger pings_push after insert on public.pings
  for each row execute procedure public.notify_push();
create trigger plans_live_push after update of status on public.planned_drives
  for each row when (new.status = 'live' and old.status is distinct from 'live') execute procedure public.notify_push();
create trigger referrals_push after update of status on public.referrals
  for each row when (new.status = 'rewarded' and old.status is distinct from 'rewarded') execute procedure public.notify_push();

-- ---------------------------------------------------------------------------
-- (applied as haza_friends_and_handles)
-- ---------------------------------------------------------------------------
alter table public.profiles add constraint profiles_handle_format
  check (handle is null or handle::text ~ '^[A-Za-z0-9_]{3,20}$');

create or replace function public.find_profile(p_handle text)
returns table (id uuid, handle text, display_name text, avatar_url text, is_friend boolean, request_pending boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.handle::text, p.display_name, p.avatar_url,
         public.are_friends(auth.uid(), p.id),
         exists (select 1 from public.friendships f where f.status = 'pending'
                 and ((f.user_id = auth.uid() and f.friend_id = p.id) or (f.user_id = p.id and f.friend_id = auth.uid())))
  from public.profiles p
  where p.handle = lower(trim(leading '@' from p_handle))::citext and p.id <> auth.uid();
$$;
revoke execute on function public.find_profile(text) from anon;

create or replace function public.pending_requests()
returns table (user_id uuid, handle text, display_name text, avatar_url text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, p.handle::text, p.display_name, p.avatar_url, f.created_at
  from public.friendships f join public.profiles p on p.id = f.user_id
  where f.friend_id = auth.uid() and f.status = 'pending'
  order by f.created_at desc;
$$;
revoke execute on function public.pending_requests() from anon;

create or replace function public.respond_request(p_from uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_accept then
    update public.friendships set status = 'accepted' where user_id = p_from and friend_id = auth.uid() and status = 'pending';
  else
    delete from public.friendships where user_id = p_from and friend_id = auth.uid() and status = 'pending';
  end if;
end;
$$;
revoke execute on function public.respond_request(uuid, boolean) from anon;

create trigger friend_request_push after insert on public.friendships
  for each row when (new.status = 'pending') execute procedure public.notify_push();
