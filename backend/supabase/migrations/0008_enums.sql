-- New ping kinds (enum values must be committed before anything uses them → own migration).
alter type public.ping_kind add value if not exists 'checkin';
alter type public.ping_kind add value if not exists 'sos';
