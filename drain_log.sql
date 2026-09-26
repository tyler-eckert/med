-- ============================================================================
--  med.eckerthaus.com — drain log table (lives in the Food Supabase project)
--  Paste into Supabase → SQL Editor → Run. Safe to re-run.
--  Uses the same allowed_emails / is_member() gate as the recipe app.
-- ============================================================================
create table if not exists public.drain_log (
  id          uuid primary key default gen_random_uuid(),
  logged_at   timestamptz not null default now(),          -- stored in UTC, shown in Central time
  left_ml     numeric(6,1) check (left_ml  >= 0),
  right_ml    numeric(6,1) check (right_ml >= 0),
  note        text,
  created_by  uuid references auth.users on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  check (left_ml is not null or right_ml is not null)
);
create index if not exists drain_log_logged_at_idx on public.drain_log (logged_at desc);

alter table public.drain_log enable row level security;
drop policy if exists "members full access" on public.drain_log;
create policy "members full access" on public.drain_log for all to authenticated
  using (public.is_member()) with check (public.is_member());

grant select, insert, update, delete on public.drain_log to authenticated;

-- Daily totals by Central-time calendar day (handy for querying in Supabase)
create or replace view public.drain_daily with (security_invoker = true) as
select (logged_at at time zone 'America/Chicago')::date      as day_ct,
       coalesce(sum(left_ml), 0)                              as left_ml,
       coalesce(sum(right_ml), 0)                             as right_ml,
       coalesce(sum(left_ml), 0) + coalesce(sum(right_ml), 0) as total_ml,
       count(*)                                               as entries
from public.drain_log
group by 1
order by 1 desc;
grant select on public.drain_daily to authenticated;

-- Live sync between devices
do $$ begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'drain_log') then
    alter publication supabase_realtime add table public.drain_log;
  end if;
end $$;
