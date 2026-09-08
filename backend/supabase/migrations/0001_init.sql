-- Haza backend — initial schema
-- Postgres 17 + PostGIS. Applied to the live project via Supabase MCP.

create extension if not exists postgis;
create extension if not exists citext;
create extension if not exists pgcrypto;
create extension if not exists pg_cron;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.friendship_status as enum ('pending', 'accepted', 'blocked');
create type public.share_visibility  as enum ('friends', 'crew', 'nobody');
create type public.crew_role         as enum ('owner', 'admin', 'member');
create type public.rsvp_status       as enum ('going', 'maybe', 'no');
create type public.plan_status       as enum ('draft', 'scheduled', 'live', 'done', 'cancelled');
create type public.channel_kind      as enum ('crew', 'direct', 'plan');
create type public.ping_kind         as enum ('talk', 'wave', 'meet', 'where');
create type public.radar_brand       as enum ('valentine', 'uniden', 'escort', 'radenso', 'other');
create type public.radar_band        as enum ('X', 'K', 'Ka', 'Ku', 'Laser');
create type public.referral_status   as enum ('claimed', 'qualified', 'rewarded', 'rejected');
create type public.sub_status        as enum ('active', 'grace', 'expired', 'revoked');
create type public.home_source       as enum ('manual', 'inferred', 'contacts');

-- ---------------------------------------------------------------------------
-- Profiles (1:1 with auth.users)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id             uuid primary key references auth.users (id) on delete cascade,
  handle         citext unique,
  display_name   text not null default '',
  avatar_url     text,
  units          text not null default 'mph' check (units in ('mph', 'kmh')),
  share_speed    boolean not null default true,
  visibility     public.share_visibility not null default 'friends',
  home_point     geography(Point, 4326),
  home_source    public.home_source,
  home_confidence real check (home_confidence between 0 and 1),
  home_radius_m  integer not null default 150,
  invite_code    text unique not null default upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 8)),
  referred_by    uuid references public.profiles (id),
  pro_until      timestamptz,                     -- server-granted Pro (referral rewards, promos)
  onboarding_done boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index profiles_handle_idx on public.profiles (handle);

-- Public-safe view of a profile (no home, no invite code)
create view public.profile_cards with (security_invoker = true) as
  select id, handle, display_name, avatar_url from public.profiles;

-- ---------------------------------------------------------------------------
-- Vehicles (the garage)
-- ---------------------------------------------------------------------------
create table public.vehicles (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references public.profiles (id) on delete cascade,
  make       text not null,
  model      text not null,
  year       smallint check (year between 1900 and 2100),
  nickname   text,
  color_hex  text check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  is_primary boolean not null default false,
  created_at timestamptz not null default now()
);
create index vehicles_owner_idx on public.vehicles (owner_id);
create unique index vehicles_one_primary on public.vehicles (owner_id) where is_primary;

-- ---------------------------------------------------------------------------
-- Friendships (stored one row per direction once accepted)
-- ---------------------------------------------------------------------------
create table public.friendships (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  friend_id  uuid not null references public.profiles (id) on delete cascade,
  status     public.friendship_status not null default 'pending',
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);
create index friendships_friend_idx on public.friendships (friend_id, status);

create or replace function public.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.friendships
    where user_id = a and friend_id = b and status = 'accepted'
  );
$$;

-- ---------------------------------------------------------------------------
-- Crews (groups of car friends) and planned drives
-- ---------------------------------------------------------------------------
create table public.crews (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  emoji       text not null default '🏁',
  created_by  uuid not null references public.profiles (id),
  invite_code text unique not null default upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 8)),
  created_at  timestamptz not null default now()
);

create table public.crew_members (
  crew_id   uuid not null references public.crews (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  role      public.crew_role not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (crew_id, user_id)
);
create index crew_members_user_idx on public.crew_members (user_id);

create or replace function public.is_crew_member(c uuid, u uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.crew_members where crew_id = c and user_id = u);
$$;

create table public.planned_drives (
  id          uuid primary key default gen_random_uuid(),
  crew_id     uuid references public.crews (id) on delete cascade,
  creator_id  uuid not null references public.profiles (id),
  title       text not null,
  notes       text,
  starts_at   timestamptz not null,
  meet_point  geography(Point, 4326),
  meet_name   text,
  route_hint  text,
  status      public.plan_status not null default 'scheduled',
  created_at  timestamptz not null default now()
);
create index planned_drives_crew_idx on public.planned_drives (crew_id, starts_at);

create table public.plan_rsvps (
  plan_id  uuid not null references public.planned_drives (id) on delete cascade,
  user_id  uuid not null references public.profiles (id) on delete cascade,
  status   public.rsvp_status not null default 'going',
  primary key (plan_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Live location (last-known row; the high-rate stream goes over Realtime Broadcast)
-- ---------------------------------------------------------------------------
create table public.live_locations (
  user_id     uuid primary key references public.profiles (id) on delete cascade,
  point       geography(Point, 4326) not null,
  speed_mps   real,
  heading_deg real,
  accuracy_m  real,
  is_driving  boolean not null default false,
  drive_id    uuid,
  vehicle_id  uuid references public.vehicles (id) on delete set null,
  updated_at  timestamptz not null default now()
);
create index live_locations_geo_idx on public.live_locations using gist (point);

-- ---------------------------------------------------------------------------
-- Drives
-- ---------------------------------------------------------------------------
create table public.drives (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  vehicle_id    uuid references public.vehicles (id) on delete set null,
  plan_id       uuid references public.planned_drives (id) on delete set null,
  started_at    timestamptz not null,
  ended_at      timestamptz,
  distance_m    real not null default 0,
  duration_s    integer not null default 0,
  avg_speed_mps real,
  max_speed_mps real,               -- private to the owner; never surfaced socially (App Review 1.4.4)
  start_point   geography(Point, 4326),
  end_point     geography(Point, 4326),
  route         geography(LineString, 4326),  -- simplified polyline
  is_auto       boolean not null default true,
  created_at    timestamptz not null default now()
);
create index drives_user_started_idx on public.drives (user_id, started_at desc);

create table public.drive_points (
  drive_id  uuid not null references public.drives (id) on delete cascade,
  ts        timestamptz not null,
  point     geography(Point, 4326) not null,
  speed_mps real,
  primary key (drive_id, ts)
);

-- ---------------------------------------------------------------------------
-- Talk (walkie-talkie) channels
-- ---------------------------------------------------------------------------
create table public.talk_channels (
  id           uuid primary key default gen_random_uuid(),
  kind         public.channel_kind not null,
  crew_id      uuid references public.crews (id) on delete cascade,
  plan_id      uuid references public.planned_drives (id) on delete cascade,
  peer_a       uuid references public.profiles (id) on delete cascade,
  peer_b       uuid references public.profiles (id) on delete cascade,
  livekit_room text unique not null default ('pace-' || replace(gen_random_uuid()::text, '-', '')),
  created_at   timestamptz not null default now(),
  check (
    (kind = 'crew'   and crew_id is not null) or
    (kind = 'plan'   and plan_id is not null) or
    (kind = 'direct' and peer_a is not null and peer_b is not null and peer_a < peer_b)
  )
);
create unique index talk_channels_crew_uidx   on public.talk_channels (crew_id) where kind = 'crew';
create unique index talk_channels_plan_uidx   on public.talk_channels (plan_id) where kind = 'plan';
create unique index talk_channels_direct_uidx on public.talk_channels (peer_a, peer_b) where kind = 'direct';

create table public.talk_members (
  channel_id    uuid not null references public.talk_channels (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  ptt_token     text,                -- ephemeral APNs PTT token (base64), set while joined
  ptt_token_at  timestamptz,
  joined        boolean not null default false,
  muted         boolean not null default false,
  primary key (channel_id, user_id)
);
create index talk_members_user_idx on public.talk_members (user_id);

create or replace function public.can_access_channel(c uuid, u uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.talk_channels t
    where t.id = c and (
      (t.kind = 'crew'   and public.is_crew_member(t.crew_id, u)) or
      (t.kind = 'plan'   and exists (select 1 from public.plan_rsvps r where r.plan_id = t.plan_id and r.user_id = u)) or
      (t.kind = 'direct' and (t.peer_a = u or t.peer_b = u))
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- Pings ("ping them on the app to start talking")
-- ---------------------------------------------------------------------------
create table public.pings (
  id         uuid primary key default gen_random_uuid(),
  from_user  uuid not null references public.profiles (id) on delete cascade,
  to_user    uuid not null references public.profiles (id) on delete cascade,
  kind       public.ping_kind not null default 'talk',
  channel_id uuid references public.talk_channels (id) on delete set null,
  created_at timestamptz not null default now(),
  seen_at    timestamptz
);
create index pings_to_idx on public.pings (to_user, created_at desc);

-- ---------------------------------------------------------------------------
-- Radar detectors and shared alerts
-- ---------------------------------------------------------------------------
create table public.radar_devices (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles (id) on delete cascade,
  brand          public.radar_brand not null,
  model          text,
  ble_identifier text,
  firmware       text,
  last_seen_at   timestamptz,
  created_at     timestamptz not null default now()
);
create index radar_devices_user_idx on public.radar_devices (user_id);

create table public.radar_alerts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  ts          timestamptz not null default now(),
  point       geography(Point, 4326) not null,
  band        public.radar_band not null,
  freq_mhz    integer,
  strength    smallint,          -- 0..255 raw, from the detector
  direction   text check (direction in ('front', 'side', 'rear')),
  heading_deg real,
  expires_at  timestamptz not null default now() + interval '15 minutes'
);
create index radar_alerts_geo_idx on public.radar_alerts using gist (point);
create index radar_alerts_expires_idx on public.radar_alerts (expires_at);

-- ---------------------------------------------------------------------------
-- Referrals and subscriptions
-- ---------------------------------------------------------------------------
create table public.referrals (
  id           uuid primary key default gen_random_uuid(),
  referrer_id  uuid not null references public.profiles (id) on delete cascade,
  referee_id   uuid not null unique references public.profiles (id) on delete cascade,
  code         text not null,
  status       public.referral_status not null default 'claimed',
  device_hash  text,
  created_at   timestamptz not null default now(),
  qualified_at timestamptz,
  rewarded_at  timestamptz,
  check (referrer_id <> referee_id)
);
create index referrals_referrer_idx on public.referrals (referrer_id, status);

create table public.subscriptions (
  user_id                 uuid primary key references public.profiles (id) on delete cascade,
  product_id              text not null,
  original_transaction_id text not null unique,
  expires_at              timestamptz,
  status                  public.sub_status not null default 'active',
  environment             text not null default 'Production',
  auto_renew              boolean,
  updated_at              timestamptz not null default now()
);

create table public.appstore_events (
  id               bigserial primary key,
  notification_type text,
  subtype          text,
  original_transaction_id text,
  received_at      timestamptz not null default now(),
  payload          jsonb not null
);

-- Single source of truth for "is this user Pro?"
create or replace function public.is_pro(u uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select pro_until > now() from public.profiles where id = u), false)
      or exists (
        select 1 from public.subscriptions s
        where s.user_id = u and s.status in ('active', 'grace')
          and (s.expires_at is null or s.expires_at > now())
      );
$$;

-- ---------------------------------------------------------------------------
-- Home inference samples (only overnight dwell samples are stored)
-- ---------------------------------------------------------------------------
create table public.home_samples (
  user_id  uuid not null references public.profiles (id) on delete cascade,
  ts       timestamptz not null,
  point    geography(Point, 4326) not null,
  primary key (user_id, ts)
);

-- Infers home as the densest 150 m cluster of overnight (00:00–05:00 local) dwell samples
-- seen on at least 3 distinct nights. Returns no row when not confident.
create or replace function public.infer_home(u uuid)
returns table (home_point geography, confidence real, night_count integer)
language plpgsql stable security definer set search_path = public as $$
declare
  total_nights integer;
begin
  select count(distinct (hs.ts at time zone 'UTC')::date) into total_nights
  from public.home_samples hs where hs.user_id = u;
  if total_nights is null or total_nights < 3 then return; end if;

  return query
  with clustered as (
    select hs.point as pt, hs.ts as sample_ts,
           st_clusterdbscan(hs.point::geometry, eps := 0.0015, minpoints := 3) over () as cid
    from public.home_samples hs
    where hs.user_id = u
  ),
  ranked as (
    select c.cid,
           st_centroid(st_collect(c.pt::geometry))::geography as centroid,
           count(distinct (c.sample_ts at time zone 'UTC')::date) as nights
    from clustered c
    where c.cid is not null
    group by c.cid
    order by nights desc
    limit 1
  )
  select r.centroid, least(1.0, r.nights::real / greatest(total_nights, 5))::real, r.nights::integer
  from ranked r
  where r.nights >= 3;
end;
$$;

-- Applies inference to the profile when the user has not set home manually.
create or replace function public.apply_home_inference()
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select p.id from public.profiles p where p.home_source is distinct from 'manual' loop
    update public.profiles p
       set home_point = h.home_point, home_confidence = h.confidence, home_source = 'inferred', updated_at = now()
      from public.infer_home(r.id) h
     where p.id = r.id and h.home_point is not null;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- The onboarding "briefing": what's missing for this user (server-known part)
-- ---------------------------------------------------------------------------
create or replace function public.briefing(u uuid)
returns table (key text, severity text, title text, detail text)
language sql stable security definer set search_path = public as $$
  select * from (
    select 'no_vehicle'::text, 'setup'::text, 'Add your car'::text,
           'Friends see your car on the map. Takes 10 seconds.'::text
    where not exists (select 1 from public.vehicles v where v.owner_id = u)
    union all
    select 'no_friends', 'setup', 'Invite a friend',
           'Haza is empty alone. Share your link — they tap accept.'
    where not exists (select 1 from public.friendships f where f.user_id = u and f.status = 'accepted')
    union all
    select 'no_home', 'privacy', 'Home not set',
           'Set home so Haza can hide your street from friends automatically. It can also learn it over a few nights.'
    where not exists (select 1 from public.profiles p where p.id = u and p.home_point is not null)
    union all
    select 'home_inferred', 'privacy', 'Haza thinks it found your home',
           'Confirm it so the privacy bubble is right.'
    where exists (select 1 from public.profiles p where p.id = u and p.home_source = 'inferred' and p.home_confidence < 0.9)
    union all
    select 'no_crew', 'feature', 'Start a crew',
           'A crew gets its own walkie-talkie channel and planned drives.'
    where not exists (select 1 from public.crew_members m where m.user_id = u)
    union all
    select 'no_radar', 'feature', 'Pair a radar detector',
           'Valentine One Gen2 pairs over Bluetooth. Alerts show on the map and go to your crew.'
    where not exists (select 1 from public.radar_devices d where d.user_id = u)
    union all
    select 'referral_progress', 'pro', 'Free Pro from referrals',
           (select count(*)::text || ' friends joined with your link' from public.referrals r where r.referrer_id = u and r.status in ('qualified','rewarded'))
    where not public.is_pro(u)
  ) b(key, severity, title, detail);
$$;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (new.id,
          coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''),
          new.raw_user_meta_data ->> 'avatar_url')
  on conflict (id) do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;
create trigger profiles_touch before update on public.profiles
  for each row execute procedure public.touch_updated_at();

-- Accepting a friendship writes the mirror row.
create or replace function public.mirror_friendship()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- Only the outermost statement mirrors; the mirror row's own trigger firing is a no-op.
  if pg_trigger_depth() > 1 then return new; end if;
  if new.status = 'accepted' and not exists (
       select 1 from public.friendships where user_id = new.friend_id and friend_id = new.user_id and status = 'accepted') then
    insert into public.friendships (user_id, friend_id, status)
    values (new.friend_id, new.user_id, 'accepted')
    on conflict (user_id, friend_id) do update set status = 'accepted';
  end if;
  return new;
end;
$$;
create trigger friendships_mirror after insert or update of status on public.friendships
  for each row execute procedure public.mirror_friendship();

-- Referral qualification: the referee's first drive >= 1 mile qualifies the referral and
-- rewards both sides with server-side Pro time (a StoreKit-independent grant — see 3.1.1 note).
create or replace function public.qualify_referral_on_drive()
returns trigger language plpgsql security definer set search_path = public as $$
declare ref public.referrals%rowtype;
begin
  if new.ended_at is null or new.distance_m < 1609 then return new; end if;
  select * into ref from public.referrals where referee_id = new.user_id and status = 'claimed';
  if not found then return new; end if;

  update public.referrals set status = 'rewarded', qualified_at = now(), rewarded_at = now() where id = ref.id;
  -- 30 days for the referrer, 14 days for the new user. Stacks on top of existing time.
  update public.profiles set pro_until = greatest(coalesce(pro_until, now()), now()) + interval '30 days' where id = ref.referrer_id;
  update public.profiles set pro_until = greatest(coalesce(pro_until, now()), now()) + interval '14 days' where id = ref.referee_id;
  return new;
end;
$$;
create trigger drives_qualify_referral after insert or update of ended_at on public.drives
  for each row execute procedure public.qualify_referral_on_drive();

-- ---------------------------------------------------------------------------
-- RPCs used by the app
-- ---------------------------------------------------------------------------

-- Claim an invite code (called once, right after sign-up).
create or replace function public.claim_invite(p_code text, p_device_hash text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); referrer uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  select id into referrer from public.profiles where invite_code = upper(trim(p_code));
  if referrer is null then return jsonb_build_object('ok', false, 'reason', 'unknown_code'); end if;
  if referrer = me then return jsonb_build_object('ok', false, 'reason', 'own_code'); end if;
  if exists (select 1 from public.referrals where referee_id = me) then
    return jsonb_build_object('ok', false, 'reason', 'already_claimed');
  end if;
  if p_device_hash is not null and exists (select 1 from public.referrals where device_hash = p_device_hash) then
    return jsonb_build_object('ok', false, 'reason', 'device_reused');
  end if;
  insert into public.referrals (referrer_id, referee_id, code, device_hash) values (referrer, me, upper(trim(p_code)), p_device_hash);
  update public.profiles set referred_by = referrer where id = me;
  -- auto-friend the two people
  insert into public.friendships (user_id, friend_id, status) values (referrer, me, 'accepted')
    on conflict (user_id, friend_id) do update set status = 'accepted';
  return jsonb_build_object('ok', true, 'referrer', referrer);
end;
$$;

-- Friends' last-known positions, with the home privacy bubble applied.
create or replace function public.friends_live()
returns table (user_id uuid, display_name text, avatar_url text, lat double precision, lng double precision,
               speed_mps real, heading_deg real, is_driving boolean, vehicle_id uuid, updated_at timestamptz, at_home boolean)
language sql stable security definer set search_path = public as $$
  select l.user_id, p.display_name, p.avatar_url,
         case when p.home_point is not null and st_dwithin(l.point, p.home_point, p.home_radius_m)
              then st_y(p.home_point::geometry) else st_y(l.point::geometry) end as lat,
         case when p.home_point is not null and st_dwithin(l.point, p.home_point, p.home_radius_m)
              then st_x(p.home_point::geometry) else st_x(l.point::geometry) end as lng,
         case when p.share_speed then l.speed_mps else null end as speed_mps,
         l.heading_deg, l.is_driving, l.vehicle_id, l.updated_at,
         (p.home_point is not null and st_dwithin(l.point, p.home_point, p.home_radius_m)) as at_home
  from public.live_locations l
  join public.profiles p on p.id = l.user_id
  where public.are_friends(auth.uid(), l.user_id)
    and p.visibility <> 'nobody'
    and l.updated_at > now() - interval '2 hours';
$$;

-- Friends within N meters of me who are online (the "nearby, talk now" list).
create or replace function public.friends_nearby(p_radius_m integer default 1500)
returns table (user_id uuid, display_name text, distance_m double precision, is_driving boolean)
language sql stable security definer set search_path = public as $$
  select f.id, f.display_name,
         st_distance(me.point, l.point) as distance_m, l.is_driving
  from public.live_locations me
  join public.live_locations l on l.user_id <> me.user_id
  join public.profiles f on f.id = l.user_id
  where me.user_id = auth.uid()
    and public.are_friends(auth.uid(), l.user_id)
    and l.updated_at > now() - interval '10 minutes'
    and st_dwithin(me.point, l.point, p_radius_m)
  order by distance_m;
$$;

-- Ensure/get a direct talk channel with a friend.
create or replace function public.direct_channel(p_friend uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare a uuid; b uuid; cid uuid;
begin
  if not public.are_friends(auth.uid(), p_friend) then raise exception 'not friends'; end if;
  a := least(auth.uid(), p_friend); b := greatest(auth.uid(), p_friend);
  select id into cid from public.talk_channels where kind = 'direct' and peer_a = a and peer_b = b;
  if cid is null then
    insert into public.talk_channels (kind, peer_a, peer_b) values ('direct', a, b) returning id into cid;
    insert into public.talk_members (channel_id, user_id) values (cid, a), (cid, b) on conflict do nothing;
  end if;
  return cid;
end;
$$;

-- Radar alerts from friends near me in the last 15 minutes.
create or replace function public.radar_alerts_near(p_lat double precision, p_lng double precision, p_radius_m integer default 8000)
returns table (id uuid, user_id uuid, band public.radar_band, freq_mhz integer, strength smallint, direction text,
               lat double precision, lng double precision, ts timestamptz)
language sql stable security definer set search_path = public as $$
  select a.id, a.user_id, a.band, a.freq_mhz, a.strength, a.direction,
         st_y(a.point::geometry), st_x(a.point::geometry), a.ts
  from public.radar_alerts a
  where a.expires_at > now()
    and (a.user_id = auth.uid() or public.are_friends(auth.uid(), a.user_id))
    and st_dwithin(a.point, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, p_radius_m)
  order by a.ts desc limit 50;
$$;

-- Delete my account (App Review 5.1.1(v)). Cascades through every table.
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles        enable row level security;
alter table public.vehicles        enable row level security;
alter table public.friendships     enable row level security;
alter table public.crews           enable row level security;
alter table public.crew_members    enable row level security;
alter table public.planned_drives  enable row level security;
alter table public.plan_rsvps      enable row level security;
alter table public.live_locations  enable row level security;
alter table public.drives          enable row level security;
alter table public.drive_points    enable row level security;
alter table public.talk_channels   enable row level security;
alter table public.talk_members    enable row level security;
alter table public.pings           enable row level security;
alter table public.radar_devices   enable row level security;
alter table public.radar_alerts    enable row level security;
alter table public.referrals       enable row level security;
alter table public.subscriptions   enable row level security;
alter table public.appstore_events enable row level security;
alter table public.home_samples    enable row level security;

-- profiles: I see mine fully; friends see cards via the view/RPCs.
create policy profiles_self_select on public.profiles for select using (id = auth.uid() or public.are_friends(auth.uid(), id));
create policy profiles_self_update on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

create policy vehicles_owner on public.vehicles for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy vehicles_friends_read on public.vehicles for select using (public.are_friends(auth.uid(), owner_id));

create policy friendships_mine on public.friendships for select using (user_id = auth.uid() or friend_id = auth.uid());
create policy friendships_request on public.friendships for insert with check (user_id = auth.uid() and status = 'pending');
create policy friendships_respond on public.friendships for update using (friend_id = auth.uid() or user_id = auth.uid());
create policy friendships_remove on public.friendships for delete using (user_id = auth.uid() or friend_id = auth.uid());

create policy crews_member_read on public.crews for select using (public.is_crew_member(id, auth.uid()));
create policy crews_create on public.crews for insert with check (created_by = auth.uid());
create policy crews_owner_update on public.crews for update using (created_by = auth.uid());
create policy crew_members_read on public.crew_members for select using (public.is_crew_member(crew_id, auth.uid()));
create policy crew_members_join on public.crew_members for insert with check (user_id = auth.uid());
create policy crew_members_leave on public.crew_members for delete using (user_id = auth.uid());

create policy plans_read on public.planned_drives for select
  using (creator_id = auth.uid() or (crew_id is not null and public.is_crew_member(crew_id, auth.uid())));
create policy plans_write on public.planned_drives for insert with check (creator_id = auth.uid());
create policy plans_update on public.planned_drives for update using (creator_id = auth.uid());
create policy rsvps_read on public.plan_rsvps for select
  using (exists (select 1 from public.planned_drives d where d.id = plan_id and (d.creator_id = auth.uid() or public.is_crew_member(d.crew_id, auth.uid()))));
create policy rsvps_mine on public.plan_rsvps for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy live_self on public.live_locations for all using (user_id = auth.uid()) with check (user_id = auth.uid());
-- friends read through friends_live()/friends_nearby() only (privacy bubble applied there)

create policy drives_owner on public.drives for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy drives_friends_read on public.drives for select using (public.are_friends(auth.uid(), user_id));
create policy drive_points_owner on public.drive_points for all
  using (exists (select 1 from public.drives d where d.id = drive_id and d.user_id = auth.uid()))
  with check (exists (select 1 from public.drives d where d.id = drive_id and d.user_id = auth.uid()));

create policy channels_read on public.talk_channels for select using (public.can_access_channel(id, auth.uid()));
create policy talk_members_read on public.talk_members for select using (public.can_access_channel(channel_id, auth.uid()));
create policy talk_members_self on public.talk_members for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy talk_members_join on public.talk_members for insert with check (user_id = auth.uid() and public.can_access_channel(channel_id, auth.uid()));

create policy pings_mine on public.pings for select using (from_user = auth.uid() or to_user = auth.uid());
create policy pings_send on public.pings for insert with check (from_user = auth.uid() and public.are_friends(auth.uid(), to_user));
create policy pings_seen on public.pings for update using (to_user = auth.uid());

create policy radar_devices_owner on public.radar_devices for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy radar_alerts_insert on public.radar_alerts for insert with check (user_id = auth.uid());
create policy radar_alerts_read on public.radar_alerts for select using (user_id = auth.uid() or public.are_friends(auth.uid(), user_id));

create policy referrals_mine on public.referrals for select using (referrer_id = auth.uid() or referee_id = auth.uid());
create policy subscriptions_mine on public.subscriptions for select using (user_id = auth.uid());
create policy home_samples_owner on public.home_samples for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Realtime authorization (private Broadcast channels)
--   topic "loc:<user_id>"  — a user's live stream; friends may listen
--   topic "crew:<crew_id>" — crew room (positions, talk state, radar alerts)
-- ---------------------------------------------------------------------------
create policy realtime_loc_listen on realtime.messages for select to authenticated
  using (
    (select realtime.topic()) like 'loc:%'
    and (
      substring((select realtime.topic()) from 5)::uuid = auth.uid()
      or public.are_friends(auth.uid(), substring((select realtime.topic()) from 5)::uuid)
    )
  );
create policy realtime_loc_send on realtime.messages for insert to authenticated
  with check (
    (select realtime.topic()) like 'loc:%'
    and substring((select realtime.topic()) from 5)::uuid = auth.uid()
  );
create policy realtime_crew_listen on realtime.messages for select to authenticated
  using ((select realtime.topic()) like 'crew:%' and public.is_crew_member(substring((select realtime.topic()) from 6)::uuid, auth.uid()));
create policy realtime_crew_send on realtime.messages for insert to authenticated
  with check ((select realtime.topic()) like 'crew:%' and public.is_crew_member(substring((select realtime.topic()) from 6)::uuid, auth.uid()));

-- ---------------------------------------------------------------------------
-- Housekeeping jobs
-- ---------------------------------------------------------------------------
select cron.schedule('pace_expire_radar', '*/5 * * * *', $$delete from public.radar_alerts where expires_at < now()$$);
select cron.schedule('pace_stale_locations', '*/15 * * * *', $$delete from public.live_locations where updated_at < now() - interval '24 hours'$$);
select cron.schedule('pace_home_inference', '30 9 * * *', $$select public.apply_home_inference()$$);
select cron.schedule('pace_prune_points', '0 4 * * *',
  $$delete from public.drive_points dp using public.drives d
    where d.id = dp.drive_id and d.started_at < now() - interval '30 days' and not public.is_pro(d.user_id)$$);

-- ---------------------------------------------------------------------------
-- Hardening (applied as migration pace_harden_functions)
-- ---------------------------------------------------------------------------
revoke execute on function public.apply_home_inference() from anon, authenticated;
revoke execute on function public.infer_home(uuid) from anon, authenticated;
revoke execute on function public.are_friends(uuid, uuid) from anon, authenticated;
revoke execute on function public.is_crew_member(uuid, uuid) from anon, authenticated;
revoke execute on function public.can_access_channel(uuid, uuid) from anon, authenticated;
revoke execute on function public.is_pro(uuid) from anon, authenticated;
revoke execute on function public.briefing(uuid) from anon, authenticated;
revoke execute on function public.handle_new_user() from anon, authenticated;
revoke execute on function public.mirror_friendship() from anon, authenticated;
revoke execute on function public.qualify_referral_on_drive() from anon, authenticated;
revoke execute on function public.touch_updated_at() from anon, authenticated;
revoke execute on function public.st_estimatedextent(text, text) from anon, authenticated;
revoke execute on function public.st_estimatedextent(text, text, text) from anon, authenticated;
revoke execute on function public.st_estimatedextent(text, text, text, boolean) from anon, authenticated;
revoke execute on function public.claim_invite(text, text) from anon;
revoke execute on function public.direct_channel(uuid) from anon;
revoke execute on function public.friends_live() from anon;
revoke execute on function public.friends_nearby(integer) from anon;
revoke execute on function public.radar_alerts_near(double precision, double precision, integer) from anon;
revoke execute on function public.delete_my_account() from anon;

create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); return new; end;
$$;

-- Self-scoped wrappers the app calls.
create or replace function public.my_briefing()
returns table (key text, severity text, title text, detail text)
language sql stable security definer set search_path = public as $$
  select * from public.briefing(auth.uid());
$$;
revoke execute on function public.my_briefing() from anon;

create or replace function public.my_pro()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'is_pro', public.is_pro(auth.uid()),
    'pro_until', (select pro_until from public.profiles where id = auth.uid()),
    'subscription', (select jsonb_build_object('product_id', product_id, 'expires_at', expires_at, 'status', status)
                     from public.subscriptions where user_id = auth.uid()),
    'referrals', (select count(*) from public.referrals where referrer_id = auth.uid() and status = 'rewarded'));
$$;
revoke execute on function public.my_pro() from anon;

create or replace function public.my_home_suggestion()
returns table (lat double precision, lng double precision, confidence real, night_count integer)
language sql stable security definer set search_path = public as $$
  select st_y(h.home_point::geometry), st_x(h.home_point::geometry), h.confidence, h.night_count
  from public.infer_home(auth.uid()) h;
$$;
revoke execute on function public.my_home_suggestion() from anon;
