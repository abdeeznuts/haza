-- In-app inbox over Realtime: every user has a private topic `user:<uid>` that only they can listen to.
-- Database triggers broadcast pings, friend requests and plans going live into it (realtime.send),
-- so a phone with the app open (or kept alive by an active talk channel) reacts instantly — no APNs
-- needed. Push notifications (push-notify) still cover the closed-app case on entitled builds.

create policy realtime_inbox_listen on realtime.messages for select to authenticated
  using ((select realtime.topic()) = 'user:' || auth.uid()::text);

create or replace function public.inbox_broadcast()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  who text;
  r record;
begin
  if tg_table_name = 'pings' then
    select display_name into who from public.profiles where id = new.from_user;
    perform realtime.send(
      jsonb_build_object('type', 'ping', 'from_user', new.from_user, 'from_name', coalesce(who, 'A friend'),
                         'kind', new.kind, 'channel_id', new.channel_id, 'id', new.id),
      'inbox', 'user:' || new.to_user::text, true);
  elsif tg_table_name = 'friendships' and new.status = 'pending' then
    select display_name into who from public.profiles where id = new.user_id;
    perform realtime.send(
      jsonb_build_object('type', 'friend_request', 'from_user', new.user_id, 'from_name', coalesce(who, 'Someone')),
      'inbox', 'user:' || new.friend_id::text, true);
  elsif tg_table_name = 'friendships' and new.status = 'accepted' and (old.status is distinct from 'accepted') then
    select display_name into who from public.profiles where id = new.friend_id;
    perform realtime.send(
      jsonb_build_object('type', 'friend_accepted', 'user_id', new.friend_id, 'name', coalesce(who, 'A friend')),
      'inbox', 'user:' || new.user_id::text, true);
  elsif tg_table_name = 'planned_drives' and new.status = 'live' then
    for r in select p.user_id from public.plan_rsvps p where p.plan_id = new.id and p.status in ('going', 'maybe') and p.user_id <> new.creator_id loop
      perform realtime.send(
        jsonb_build_object('type', 'plan_live', 'plan_id', new.id, 'title', new.title, 'meet_name', new.meet_name),
        'inbox', 'user:' || r.user_id::text, true);
    end loop;
  end if;
  return new;
end;
$$;
revoke execute on function public.inbox_broadcast() from anon, authenticated;

create trigger pings_inbox after insert on public.pings
  for each row execute procedure public.inbox_broadcast();
create trigger friendships_inbox after insert or update of status on public.friendships
  for each row execute procedure public.inbox_broadcast();
create trigger plans_live_inbox after update of status on public.planned_drives
  for each row when (new.status = 'live' and old.status is distinct from 'live') execute procedure public.inbox_broadcast();
