-- 0011: friend notification prefs default ON (matches my_friend_prefs, which coalesces to true).
-- A friend who never touched the toggles still gets "Ali is driving" / "Ali arrived at Work".
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
      for r in select f.user_id from public.friendships f
               left join public.friend_prefs fp on fp.user_id = f.user_id and fp.friend_id = f.friend_id
               where f.friend_id = new.user_id and f.status = 'accepted' and coalesce(fp.notify_places, true) loop
        perform realtime.send(
          jsonb_build_object('type', 'place', 'user_id', new.user_id, 'name', coalesce(who, 'A friend'),
                             'place_name', pname, 'event', new.event),
          'inbox', 'user:' || r.user_id::text, true);
      end loop;
    end if;
  elsif tg_table_name = 'drive_events' then
    select display_name into who from public.profiles where id = new.user_id;
    if new.event = 'started' then
      for r in select f.user_id from public.friendships f
               left join public.friend_prefs fp on fp.user_id = f.user_id and fp.friend_id = f.friend_id
               where f.friend_id = new.user_id and f.status = 'accepted' and coalesce(fp.notify_drives, true) loop
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
