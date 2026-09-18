-- Dedicated persistence table for Rwanda CMI Delivery Plan detailed activities
-- One row = one CMI activity shown in the detailed Delivery Plan Gantt.

create extension if not exists pgcrypto;

create table if not exists public.cmi_delivery_activities (
  id uuid primary key default gen_random_uuid(),
  cmi_key text not null,
  cmi_no text not null,
  cmi_record_id text,
  activity_id text not null,
  activity_name text not null,
  planned_start date,
  planned_finish date,
  actual_start date,
  actual_finish date,
  progress_pct numeric(5,2) not null default 0 check (progress_pct >= 0 and progress_pct <= 100),
  site_resource text,
  offsite_resource text,
  display_order integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (cmi_key, activity_id)
);

create index if not exists idx_cmi_delivery_activities_cmi_key
  on public.cmi_delivery_activities (cmi_key);

create index if not exists idx_cmi_delivery_activities_planned
  on public.cmi_delivery_activities (planned_start, planned_finish);

create index if not exists idx_cmi_delivery_activities_actual
  on public.cmi_delivery_activities (actual_start, actual_finish);

create or replace function public.set_cmi_delivery_activities_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_cmi_delivery_activities_updated_at on public.cmi_delivery_activities;
create trigger trg_cmi_delivery_activities_updated_at
before update on public.cmi_delivery_activities
for each row execute function public.set_cmi_delivery_activities_updated_at();

alter table public.cmi_delivery_activities enable row level security;

drop policy if exists "dashboard can read cmi delivery activities" on public.cmi_delivery_activities;
create policy "dashboard can read cmi delivery activities"
on public.cmi_delivery_activities for select
to anon, authenticated
using (true);

drop policy if exists "dashboard can insert cmi delivery activities" on public.cmi_delivery_activities;
create policy "dashboard can insert cmi delivery activities"
on public.cmi_delivery_activities for insert
to anon, authenticated
with check (true);

drop policy if exists "dashboard can update cmi delivery activities" on public.cmi_delivery_activities;
create policy "dashboard can update cmi delivery activities"
on public.cmi_delivery_activities for update
to anon, authenticated
using (true)
with check (true);

drop policy if exists "dashboard can delete cmi delivery activities" on public.cmi_delivery_activities;
create policy "dashboard can delete cmi delivery activities"
on public.cmi_delivery_activities for delete
to anon, authenticated
using (true);
