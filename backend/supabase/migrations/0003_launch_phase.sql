-- Launch phase: everything unlocked for everyone (Muhammad, Sep 8 2026: "don't worry about selling").
-- The subscription/referral plumbing stays intact and dormant. When it's time to sell, run:
--   update private.settings set value = 'false' where key = 'everything_unlocked';
-- and flip HazaBrand.everythingUnlocked to false in the app (it hides Pro UI while true).

insert into private.settings (key, value) values ('everything_unlocked', 'true')
  on conflict (key) do update set value = excluded.value;

create or replace function public.is_pro(u uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select s.value = 'true' from private.settings s where s.key = 'everything_unlocked'), false)
      or coalesce((select pro_until > now() from public.profiles where id = u), false)
      or exists (
        select 1 from public.subscriptions s
        where s.user_id = u and s.status in ('active', 'grace')
          and (s.expires_at is null or s.expires_at > now())
      );
$$;
revoke execute on function public.is_pro(uuid) from anon, authenticated;
