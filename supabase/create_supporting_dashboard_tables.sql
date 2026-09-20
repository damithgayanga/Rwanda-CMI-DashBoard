-- Supporting Supabase tables for the Rwanda CMI Dashboard
-- Run this migration in the Supabase SQL Editor.
-- Existing tables retained: public.cmis, public.resources, public.cmi_delivery_activities

create extension if not exists pgcrypto;

-- ============================================================
-- 1) ACTIVITY MASTER
-- Master list used by Activity List, Resource Allocation,
-- Progress Update and the Delivery Plan.
-- ============================================================
create table if not exists public.activity_master (
  activity_id text primary key,
  activity_name text not null,
  description text not null default '',
  active boolean not null default true,
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.activity_master
(activity_id, activity_name, description, active, display_order)
values
('act-measure','Measurement Works & Valuation','Measurement, BOQ / marked-up drawings, QA/QC and valuation.',true,1),
('act-finalise','Review of Valuation and Compilation of all Documents','Review the valuation and compile all supporting documents for the CMI submission package.',true,2),
('act-final-review','Final Review of the Submission','Final internal review before submission to DGJ.',true,3),
('act-submit-dgj','Submission to DGJ','Issue the completed CMI submission to DG Jones.',true,4),
('act-priority','Allocate Priority Levels / Initial Judgement','Initial review, value judgement and priority allocation for Unallocated / unvalued CMIs.',true,5),
('act-investigate','Further Investigation','Further investigate closed / uncertain CMIs and confirm the required commercial action.',true,6),
('act-clearance','Technical and Commercial Clearance','Technical and commercial review / clearance, including CMIs stated as covered elsewhere.',true,7)
on conflict (activity_id) do update
set activity_name=excluded.activity_name,
    description=excluded.description,
    active=excluded.active,
    display_order=excluded.display_order,
    updated_at=now();

-- ============================================================
-- 2) DELIVERY WBS
-- Stores both Level 1 groups and Level 2 activities used by
-- the high-level Delivery Plan.
-- ============================================================
create table if not exists public.delivery_wbs (
  wbs_id text primary key,
  parent_wbs_id text references public.delivery_wbs(wbs_id) on delete cascade,
  wbs_level integer not null check (wbs_level in (1,2)),
  wbs_name text not null,
  count_source text not null default 'All',
  activity_id text references public.activity_master(activity_id) on update cascade,
  planned_start date,
  planned_finish date,
  active boolean not null default true,
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (wbs_level=1 and parent_wbs_id is null)
    or
    (wbs_level=2 and parent_wbs_id is not null)
  )
);

insert into public.delivery_wbs
(wbs_id,parent_wbs_id,wbs_level,wbs_name,count_source,activity_id,planned_start,planned_finish,active,display_order)
values
('wbs-high',null,1,'High Priority CMIs','High',null,null,null,true,1),
('wbs-medium',null,1,'Medium Priority CMIs','Medium',null,null,null,true,2),
('wbs-low',null,1,'Low Priority CMIs','Low',null,null,null,true,3),
('wbs-other',null,1,'Other CMI Reviews','Other',null,null,null,true,4)
on conflict (wbs_id) do update
set parent_wbs_id=excluded.parent_wbs_id,
    wbs_level=excluded.wbs_level,
    wbs_name=excluded.wbs_name,
    count_source=excluded.count_source,
    activity_id=excluded.activity_id,
    planned_start=excluded.planned_start,
    planned_finish=excluded.planned_finish,
    active=excluded.active,
    display_order=excluded.display_order,
    updated_at=now();

insert into public.delivery_wbs
(wbs_id,parent_wbs_id,wbs_level,wbs_name,count_source,activity_id,planned_start,planned_finish,active,display_order)
values
('high-measure','wbs-high',2,'Measurement Works & Valuation','High','act-measure','2026-09-09','2026-09-25',true,1),
('high-finalise','wbs-high',2,'Review of Valuation and Compilation of all Documents','High','act-finalise','2026-09-21','2026-10-02',true,2),
('high-clearance','wbs-high',2,'Technical and Commercial Clearance','High','act-clearance','2026-09-28','2026-10-05',true,3),
('high-review','wbs-high',2,'Final Review of the Submission','High','act-final-review','2026-10-05','2026-10-07',true,4),
('high-dgj','wbs-high',2,'Submission to DGJ','High','act-submit-dgj','2026-10-08','2026-10-09',true,5),

('medium-measure','wbs-medium',2,'Measurement Works & Valuation','Medium','act-measure','2026-09-21','2026-10-30',true,1),
('medium-finalise','wbs-medium',2,'Review of Valuation and Compilation of all Documents','Medium','act-finalise','2026-10-19','2026-11-06',true,2),
('medium-clearance','wbs-medium',2,'Technical and Commercial Clearance','Medium','act-clearance','2026-11-02','2026-11-10',true,3),
('medium-review','wbs-medium',2,'Final Review of the Submission','Medium','act-final-review','2026-11-09','2026-11-13',true,4),
('medium-dgj','wbs-medium',2,'Submission to DGJ','Medium','act-submit-dgj','2026-11-16','2026-11-20',true,5),

('low-measure','wbs-low',2,'Measurement Works & Valuation','Low','act-measure','2026-10-26','2026-11-27',true,1),
('low-finalise','wbs-low',2,'Review of Valuation and Compilation of all Documents','Low','act-finalise','2026-11-16','2026-12-04',true,2),
('low-clearance','wbs-low',2,'Technical and Commercial Clearance','Low','act-clearance','2026-11-30','2026-12-07',true,3),
('low-review','wbs-low',2,'Final Review of the Submission','Low','act-final-review','2026-12-07','2026-12-09',true,4),
('low-dgj','wbs-low',2,'Submission to DGJ','Low','act-submit-dgj','2026-12-10','2026-12-16',true,5),

('unallocated-priority','wbs-other',2,'Allocate Priority Levels / Initial Judgement','Unallocated','act-priority','2026-09-01','2026-09-30',true,1),
('investigate-closed','wbs-other',2,'Further Investigation','Investigated','act-investigate','2026-09-01','2026-10-16',true,2),
('included-review','wbs-other',2,'Technical and Commercial Clearance','Included','act-clearance','2026-09-01','2026-10-30',true,3)
on conflict (wbs_id) do update
set parent_wbs_id=excluded.parent_wbs_id,
    wbs_level=excluded.wbs_level,
    wbs_name=excluded.wbs_name,
    count_source=excluded.count_source,
    activity_id=excluded.activity_id,
    planned_start=excluded.planned_start,
    planned_finish=excluded.planned_finish,
    active=excluded.active,
    display_order=excluded.display_order,
    updated_at=now();

create index if not exists idx_delivery_wbs_parent
  on public.delivery_wbs(parent_wbs_id);

create index if not exists idx_delivery_wbs_activity
  on public.delivery_wbs(activity_id);

-- ============================================================
-- 3) DASHBOARD SETTINGS
-- Shared business settings only. User-specific visual state such
-- as expanded/collapsed rows should remain in the browser.
-- ============================================================
create table if not exists public.dashboard_settings (
  setting_key text primary key,
  setting_value jsonb not null,
  description text not null default '',
  updated_at timestamptz not null default now()
);

insert into public.dashboard_settings(setting_key,setting_value,description)
values
('tracker_start','"2026-09-09"'::jsonb,'Date from which current delivery tracking is measured.'),
('default_delivery_target','"2026-12-16"'::jsonb,'Current target date for the CMI delivery programme.'),
('weekly_capacity','12'::jsonb,'Current assumed CMI production capacity per week.'),
('full_offsite_team_start','"2026-09-21"'::jsonb,'Date from which the full off-site team is assumed available.'),
('unallocated_portfolio_allowance','2000000'::jsonb,'Portfolio allowance used for Unallocated / unvalued CMI dashboard analysis.'),
('provisional_portfolio_allowance','3000000'::jsonb,'Portfolio allowance used for provisional-sum / investigation dashboard analysis.')
on conflict (setting_key) do update
set setting_value=excluded.setting_value,
    description=excluded.description,
    updated_at=now();

-- ============================================================
-- Shared updated_at trigger
-- ============================================================
create or replace function public.set_dashboard_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at=now();
  return new;
end;
$$;

drop trigger if exists trg_activity_master_updated_at on public.activity_master;
create trigger trg_activity_master_updated_at
before update on public.activity_master
for each row execute function public.set_dashboard_updated_at();

drop trigger if exists trg_delivery_wbs_updated_at on public.delivery_wbs;
create trigger trg_delivery_wbs_updated_at
before update on public.delivery_wbs
for each row execute function public.set_dashboard_updated_at();

drop trigger if exists trg_dashboard_settings_updated_at on public.dashboard_settings;
create trigger trg_dashboard_settings_updated_at
before update on public.dashboard_settings
for each row execute function public.set_dashboard_updated_at();

-- ============================================================
-- RLS
-- The current dashboard uses the Supabase publishable/anon key
-- without user authentication, so these policies match the
-- application's present access model. Tighten them if auth is
-- introduced later.
-- ============================================================
alter table public.activity_master enable row level security;
alter table public.delivery_wbs enable row level security;
alter table public.dashboard_settings enable row level security;

drop policy if exists "dashboard read activity master" on public.activity_master;
create policy "dashboard read activity master"
on public.activity_master for select to anon,authenticated using (true);
drop policy if exists "dashboard insert activity master" on public.activity_master;
create policy "dashboard insert activity master"
on public.activity_master for insert to anon,authenticated with check (true);
drop policy if exists "dashboard update activity master" on public.activity_master;
create policy "dashboard update activity master"
on public.activity_master for update to anon,authenticated using (true) with check (true);
drop policy if exists "dashboard delete activity master" on public.activity_master;
create policy "dashboard delete activity master"
on public.activity_master for delete to anon,authenticated using (true);

drop policy if exists "dashboard read delivery wbs" on public.delivery_wbs;
create policy "dashboard read delivery wbs"
on public.delivery_wbs for select to anon,authenticated using (true);
drop policy if exists "dashboard insert delivery wbs" on public.delivery_wbs;
create policy "dashboard insert delivery wbs"
on public.delivery_wbs for insert to anon,authenticated with check (true);
drop policy if exists "dashboard update delivery wbs" on public.delivery_wbs;
create policy "dashboard update delivery wbs"
on public.delivery_wbs for update to anon,authenticated using (true) with check (true);
drop policy if exists "dashboard delete delivery wbs" on public.delivery_wbs;
create policy "dashboard delete delivery wbs"
on public.delivery_wbs for delete to anon,authenticated using (true);

drop policy if exists "dashboard read settings" on public.dashboard_settings;
create policy "dashboard read settings"
on public.dashboard_settings for select to anon,authenticated using (true);
drop policy if exists "dashboard insert settings" on public.dashboard_settings;
create policy "dashboard insert settings"
on public.dashboard_settings for insert to anon,authenticated with check (true);
drop policy if exists "dashboard update settings" on public.dashboard_settings;
create policy "dashboard update settings"
on public.dashboard_settings for update to anon,authenticated using (true) with check (true);
drop policy if exists "dashboard delete settings" on public.dashboard_settings;
create policy "dashboard delete settings"
on public.dashboard_settings for delete to anon,authenticated using (true);
