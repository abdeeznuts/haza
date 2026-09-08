-- Email/OTP sign-ups carry no name: default to the part before the @ so nobody is ever blank on the map.
-- The app asks "What should friends call you?" once after the first sign-in anyway.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (new.id,
          coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''),
                   nullif(new.raw_user_meta_data ->> 'name', ''),
                   nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
                   'Driver'),
          new.raw_user_meta_data ->> 'avatar_url')
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke execute on function public.handle_new_user() from anon, authenticated;
