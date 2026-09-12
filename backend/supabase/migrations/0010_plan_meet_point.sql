-- 0010: meet point of a plan as lat/lng (the client computes its own ETA with MapKit and posts it via set_plan_eta).
create or replace function public.plan_meet_point(p_plan uuid)
returns table (lat double precision, lng double precision, meet_name text)
language sql stable security invoker set search_path = public as $$
  select st_y(d.meet_point::geometry), st_x(d.meet_point::geometry), d.meet_name
  from public.planned_drives d
  where d.id = p_plan
    and d.meet_point is not null
    and (d.creator_id = auth.uid() or (d.crew_id is not null and public.is_crew_member(d.crew_id, auth.uid())));
$$;
grant execute on function public.plan_meet_point(uuid) to authenticated;
