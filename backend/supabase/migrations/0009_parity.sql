-- Parity round (Life360 / Find My / Wheelz): battery sharing, ghost mode, places + arrive/leave alerts,
-- drive-start alerts + convoy suggestions, driving stats, plan ETAs, check-in / SOS pings, location timeline.

-- ---------------------------------------------------------------------------
-- Battery level + ghost mode
-- ---------------------------------------------------------------------------
alter table public.live_locations
  add column if not exists battery_pct smallint check (battery_pct between 0 and 100),
  add column if not exists is_charging boolean;
alter table public.profiles add column if not exists ghost_until timestamptz;   -- null = visible, 'infinity' = until turned off

-- ---------------------------------------------------------------------------
-- Places (Home is still profiles.home_point; these are the extra ones) + arrive/leave events
-- ---------------------------------------------------------------------------
create table if not exists public.places (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  name       text not null,
  kind       text not null default 'custom' check (kind in ('home', 'work', 'school', 'gym', 'custom')),
  point      geography(Point, 4326) not null,
  radius_m   integer not null default 150 check (radius_m between 50 and 2000),
  share_with text not null default 'friends' check (share_with in ('friends', 'nobody')),
  created_at timestamptz not null default now()
);
create index if not exists places_user_idx on public.places (user_id);
alter table public.places enable row level security;
create policy places_owner on public.places for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy places_friends_read on public.places for select using (share_with = 'friends' and public.are_friends(auth.uid(), user_id));

create table if not exists public.place_events (
  id       uuid primary key default gen_random_uuid(),
  user_id  uuid not null references public.profiles (id) on delete cascade,
  place_id uuid not null references public.places (id) on delete cascade,
  event    text not null check (event in ('arrive', 'leave')),
  at       timestamptz not null default now()
);
create index if not exists place_events_user_idx on public.place_events (user_id, at desc);
alter table public.place_events enable row level security;
create policy place_events_owner on public.place_events for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy place_events_friends_read on public.place_events for select
  using (public.are_friends(auth.uid(), user_id) and exists (select 1 from public.places p where p.id = place_id and p.share_with = 'friends'));

-- What I want to hear about each friend.
create table if not exists public.friend_prefs (
  user_id       uuid not null references public.profiles (id) on delete cascade,
  friend_id     uuid not null references public.profiles (id) on delete cascade,
  notify_drives boolean not null default true,
  notify_places boolean not null default true,
  primary key (user_id, friend_id)
);
alter table public.friend_prefs enable row level security;
create policy friend_prefs_owner on public.friend_prefs for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Drive events (started / ended) and per-drive driving stats
-- ---------------------------------------------------------------------------
create table if not exists public.drive_events (
  id       uuid primary key default gen_random_uuid(),
  user_id  uuid not null references public.profiles (id) on delete cascade,
  event    text not null check (event in ('started', 'ended')),
  point    geography(Point, 4326),
  drive_id uuid,
  at       timestamptz not null default now()
);
create index if not exists drive_events_user_idx on public.drive_events (user_id, at desc);
alter table public.drive_events enable row level security;
create policy drive_events_owner on public.drive_events for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy drive_events_friends_read on public.drive_events for select using (public.are_friends(auth.uid(), user_id));

alter table public.drives
  add column if not exists hard_brakes integer not null default 0,
  add column if not exists rapid_accels integer not null default 0,
  add column if not exists max_g real,
  add column if not exists zero_to_sixty_s real;

-- ---------------------------------------------------------------------------
-- Plan ETAs and check-in / SOS pings
-- ---------------------------------------------------------------------------
alter table public.plan_rsvps
  add column if not exists eta_at timestamptz,
  add column if not exists eta_updated_at timestamptz;
alter table public.pings
  add column if not exists point geography(Point, 4326),
  add column if not exists note text;

create or replace function public.plan_etas(p_plan uuid)
returns table (user_id uuid, display_name text, status public.rsvp_status, eta_at timestamptz, eta_updated_at timestamptz, is_driving boolean)
language sql stable security definer set search_path = public as $$
  select r.user_id, p.display_name, r.status, r.eta_at, r.eta_updated_at, coalesce(l.is_driving, false)
  from public.plan_rsvps r
  join public.profiles p on p.id = r.user_id
  left join public.live_locations l on l.user_id = r.user_id
  where r.plan_id = p_plan
    and (r.user_id = auth.uid() or public.are_friends(auth.uid(), r.user_id)
         or exists (select 1 from public.planned_drives d where d.id = p_plan and (d.creator_id = auth.uid() or public.is_crew_member(d.crew_id, auth.uid()))))
  order by r.eta_at nulls last;
$$;
revoke execute on function public.plan_etas(uuid) from anon;

-- SOS: one ping per friend, all at once, with my position.
create or replace function public.send_sos(p_lat double precision, p_lng double precision, p_note text default null)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer := 0; f record;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  for f in select friend_id from public.friendships where user_id = auth.uid() and status = 'accepted' loop
    insert into public.pings (from_user, to_user, kind, point, note)
    values (auth.uid(), f.friend_id, 'sos', st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, p_note);
    n := n + 1;
  end loop;
  return n;
end;
$$;
revoke execute on function public.send_sos(double precision, double precision, text) from anon;

-- ---------------------------------------------------------------------------
-- Location timeline: a cheap sample of live_locations every 15 minutes (only when it moved), 90 days kept.
-- ---------------------------------------------------------------------------
create table if not exists public.location_history (
  user_id uuid not null references public.profiles (id) on delete cascade,
  at      timestamptz not null,
  point   geography(Point, 4326) not null,
  primary key (user_id, at)
);
alter table public.location_history enable row level security;
create policy location_history_owner on public.location_history for select using (user_id = auth.uid());

create or replace function public.sample_location_history()
returns void language sql security definer set search_path = public as $$
  insert into public.location_history (user_id, at, point)
  select l.user_id, l.updated_at, l.point
  from public.live_locations l
  where l.updated_at > now() - interval '16 minutes'
    and not exists (
      select 1 from public.location_history h
      where h.user_id = l.user_id and h.at > now() - interval '16 minutes' and st_dwithin(h.point, l.point, 100))
  on conflict do nothing;
  delete from public.location_history where at < now() - interval '90 days';
$$;
revoke execute on function public.sample_location_history() from anon, authenticated;
select cron.schedule('haza_history_sample', '*/15 * * * *', $$select public.sample_location_history()$$);

-- The timeline the app shows for one day: drives, place events and sampled positions.
create or replace function public.my_timeline(p_day date)
returns table (kind text, at timestamptz, title text, lat double precision, lng double precision, ref_id uuid)
language sql stable security definer set search_path = public as $$
  select 'drive', d.started_at, format('%s mi drive', round((d.distance_m / 1609.344)::numeric, 1)),
         st_y(d.start_point::geometry), st_x(d.start_point::geometry), d.id
  from public.drives d where d.user_id = auth.uid() and d.started_at::date = p_day
  union all
  select 'place_' || e.event, e.at, p.name, st_y(p.point::geometry), st_x(p.point::geometry), e.place_id
  from public.place_events e join public.places p on p.id = e.place_id
  where e.user_id = auth.uid() and e.at::date = p_day
  union all
  select 'position', h.at, null, st_y(h.point::geometry), st_x(h.point::geometry), null
  from public.location_history h where h.user_id = auth.uid() and h.at::date = p_day
  order by 2;
$$;
revoke execute on function public.my_timeline(date) from anon;

-- ---------------------------------------------------------------------------
-- friends_live: battery, ghost, current place label
-- ---------------------------------------------------------------------------
drop function if exists public.friends_live();
create or replace function public.friends_live()
returns table (user_id uuid, display_name text, avatar_url text, lat double precision, lng double precision,
               speed_mps real, heading_deg real, is_driving boolean, vehicle_id uuid, updated_at timestamptz, at_home boolean,
               battery_pct smallint, is_charging boolean, place_name text)
language sql stable security definer set search_path = public as $$
  select l.user_id, p.display_name, p.avatar_url,
         case when p.home_point is not null and st_dwithin(l.point, p.home_point, p.home_radius_m)
              then st_y(p.home_point::geometry) else st_y(l.point::geometry) end as lat,
         case when p.home_point is not null and st_dwithin(l.point, p.home_point, p.home_radius_m)
              then st_x(p.home_point::geometry) else st_x(l.point::geometry) end as lng,
         case when p.share_speed then l.speed_mps else null end as speed_mps,
         l.heading_deg, l.is_driving, l.vehicle_id, l.updated_at,
         (p.home_point is not null and st_dwithin(l.point, p.home_point, p.home_radius_m)) as at_home,
         l.battery_pct, l.is_charging,
         (select pl.name from public.places pl
            where pl.user_id = l.user_id and pl.share_with = 'friends' and st_dwithin(l.point, pl.point, pl.radius_m)
            order by st_distance(l.point, pl.point) limit 1) as place_name
  from public.live_locations l
  join public.profiles p on p.id = l.user_id
  where public.are_friends(auth.uid(), l.user_id)
    and p.visibility <> 'nobody'
    and (p.ghost_until is null or p.ghost_until < now())
    and l.updated_at > now() - interval '2 hours';
$$;
revoke execute on function public.friends_live() from anon;

-- ---------------------------------------------------------------------------
-- Inbox broadcasts for the new events (extends 0006's inbox_broadcast)
-- ---------------------------------------------------------------------------
create or replace function public.inbox_broadcast()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  who text;
  r record;
  pname text;
  pt geometry;
begin
  if tg_table_name = 'pings' then
    select display_name into who from public.profiles where id = new.from_user;
    perform realtime.send(
      jsonb_build_object('type', 'ping', 'from_user', new.from_user, 'from_name', coalesce(who, 'A friend'),
                         'kind', new.kind, 'channel_id', new.channel_id, 'id', new.id, 'note', new.note,
                         'lat', case when new.point is not null then st_y(new.point::geometry) end,
                         'lng', case when new.point is not null then st_x(new.point::geometry) end),
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
  elsif tg_table_name = 'place_events' then
    select display_name into who from public.profiles where id = new.user_id;
    select p.name into pname from public.places p where p.id = new.place_id and p.share_with = 'friends';
    if pname is not null then
      for r in select f.user_id from public.friend_prefs f
               where f.friend_id = new.user_id and f.notify_places and public.are_friends(f.user_id, new.user_id) loop
        perform realtime.send(
          jsonb_build_object('type', 'place', 'user_id', new.user_id, 'name', coalesce(who, 'A friend'),
                             'place_name', pname, 'event', new.event),
          'inbox', 'user:' || r.user_id::text, true);
      end loop;
    end if;
  elsif tg_table_name = 'drive_events' then
    select display_name into who from public.profiles where id = new.user_id;
    if new.event = 'started' then
      for r in select f.user_id from public.friend_prefs f
               where f.friend_id = new.user_id and f.notify_drives and public.are_friends(f.user_id, new.user_id) loop
        perform realtime.send(
          jsonb_build_object('type', 'drive_started', 'user_id', new.user_id, 'name', coalesce(who, 'A friend'),
                             'lat', case when new.point is not null then st_y(new.point::geometry) end,
                             'lng', case when new.point is not null then st_x(new.point::geometry) end),
          'inbox', 'user:' || r.user_id::text, true);
      end loop;
      -- Convoy suggestion: friends already driving within 1.5 km hear about each other.
      if new.point is not null then
        for r in select l.user_id, st_distance(l.point, new.point) as d
                 from public.live_locations l
                 where l.user_id <> new.user_id and l.is_driving and l.updated_at > now() - interval '5 minutes'
                   and public.are_friends(new.user_id, l.user_id) and st_dwithin(l.point, new.point, 1500) loop
          perform realtime.send(
            jsonb_build_object('type', 'convoy_suggest', 'user_id', new.user_id, 'name', coalesce(who, 'A friend'), 'distance_m', round(r.d)),
            'inbox', 'user:' || r.user_id::text, true);
          perform realtime.send(
            jsonb_build_object('type', 'convoy_suggest', 'user_id', r.user_id,
                               'name', (select display_name from public.profiles where id = r.user_id), 'distance_m', round(r.d)),
            'inbox', 'user:' || new.user_id::text, true);
        end loop;
      end if;
    end if;
  end if;
  return new;
end;
$$;
revoke execute on function public.inbox_broadcast() from anon, authenticated;

drop trigger if exists place_events_inbox on public.place_events;
create trigger place_events_inbox after insert on public.place_events
  for each row execute procedure public.inbox_broadcast();
drop trigger if exists drive_events_inbox on public.drive_events;
create trigger drive_events_inbox after insert on public.drive_events
  for each row execute procedure public.inbox_broadcast();

-- Push notifications for the same events on entitled builds.
drop trigger if exists place_events_push on public.place_events;
create trigger place_events_push after insert on public.place_events
  for each row execute procedure public.notify_push();
drop trigger if exists drive_events_push on public.drive_events;
create trigger drive_events_push after insert on public.drive_events
  for each row when (new.event = 'started') execute procedure public.notify_push();

-- Friend list with prefs (for the Friends screen toggles).
create or replace function public.my_friend_prefs()
returns table (friend_id uuid, notify_drives boolean, notify_places boolean)
language sql stable security definer set search_path = public as $$
  select f.friend_id, coalesce(fp.notify_drives, true), coalesce(fp.notify_places, true)
  from public.friendships f
  left join public.friend_prefs fp on fp.user_id = auth.uid() and fp.friend_id = f.friend_id
  where f.user_id = auth.uid() and f.status = 'accepted';
$$;
revoke execute on function public.my_friend_prefs() from anon;

-- (applied as haza_places_rpc)
create or replace function public.my_places()
returns table (id uuid, user_id uuid, name text, kind text, lat double precision, lng double precision, radius_m integer, share_with text)
language sql stable security definer set search_path = public as $$
  select p.id, p.user_id, p.name, p.kind, st_y(p.point::geometry), st_x(p.point::geometry), p.radius_m, p.share_with
  from public.places p where p.user_id = auth.uid() order by p.created_at;
$$;
revoke execute on function public.my_places() from anon;

create or replace function public.set_ghost(p_until timestamptz)
returns void language sql security definer set search_path = public as $$
  update public.profiles set ghost_until = p_until where id = auth.uid();
$$;
revoke execute on function public.set_ghost(timestamptz) from anon;

create or replace function public.set_plan_eta(p_plan uuid, p_eta timestamptz)
returns void language sql security definer set search_path = public as $$
  update public.plan_rsvps set eta_at = p_eta, eta_updated_at = now() where plan_id = p_plan and user_id = auth.uid();
$$;
revoke execute on function public.set_plan_eta(uuid, timestamptz) from anon;

create or replace function public.weekly_recap()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'drives', count(*),
    'miles', round(coalesce(sum(distance_m), 0)::numeric / 1609.344, 1),
    'hours', round(coalesce(sum(duration_s), 0)::numeric / 3600, 1),
    'best_zero_sixty', min(zero_to_sixty_s),
    'max_g', max(max_g),
    'hard_brakes', coalesce(sum(hard_brakes), 0),
    'rapid_accels', coalesce(sum(rapid_accels), 0),
    'top_speed_mps', max(max_speed_mps)
  )
  from public.drives where user_id = auth.uid() and started_at > now() - interval '7 days';
$$;
revoke execute on function public.weekly_recap() from anon;
