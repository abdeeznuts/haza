-- Route playback: the driver's own route, plus friends' routes that overlapped in time
-- ("the cars that were with you"). Friends' routes are clipped 150 m around their home.

create or replace function public.drive_route(p_drive uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(st_asgeojson(d.route::geometry)::jsonb -> 'coordinates', '[]'::jsonb)
  from public.drives d
  where d.id = p_drive and d.user_id = auth.uid();
$$;
revoke execute on function public.drive_route(uuid) from anon;

create or replace function public.drive_companions(p_drive uuid)
returns table (drive_id uuid, user_id uuid, display_name text, started_at timestamptz, ended_at timestamptz, coordinates jsonb)
language sql stable security definer set search_path = public as $$
  with mine as (
    select d.started_at, coalesce(d.ended_at, d.started_at + make_interval(secs => d.duration_s)) as ended_at
    from public.drives d where d.id = p_drive and d.user_id = auth.uid()
  ),
  theirs as (
    select d.id, d.user_id, p.display_name, d.started_at,
           coalesce(d.ended_at, d.started_at + make_interval(secs => d.duration_s)) as ended_at,
           d.route, p.home_point
    from public.drives d
    join public.profiles p on p.id = d.user_id
    cross join mine
    where d.user_id <> auth.uid()
      and public.are_friends(auth.uid(), d.user_id)
      and d.route is not null
      and tstzrange(d.started_at, coalesce(d.ended_at, d.started_at + make_interval(secs => d.duration_s)))
          && tstzrange(mine.started_at - interval '10 minutes', mine.ended_at + interval '10 minutes')
  )
  select t.id, t.user_id, t.display_name, t.started_at, t.ended_at,
         coalesce((
           select jsonb_agg(jsonb_build_array(st_x(pt.geom), st_y(pt.geom)) order by pt.path[1])
           from st_dumppoints(t.route::geometry) pt
           where t.home_point is null or not st_dwithin(pt.geom::geography, t.home_point, 150)
         ), '[]'::jsonb)
  from theirs t
  order by t.started_at;
$$;
revoke execute on function public.drive_companions(uuid) from anon;
