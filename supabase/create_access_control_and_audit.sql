-- Rwanda CMI Dashboard - access control and audit trail
-- Uses Supabase Auth for secure password handling.
-- Users sign in with a dashboard username; the UI resolves that username
-- to the Supabase Auth email internally.
--
-- IMPORTANT: create each user in Supabase Authentication > Users first,
-- then insert a matching row in public.dashboard_users.

create extension if not exists citext;
create extension if not exists pgcrypto;

-- ============================================================
-- USER PROFILES / ACCESS LEVELS
-- ============================================================
create table if not exists public.dashboard_users (
  id uuid primary key references auth.users(id) on delete cascade,
  username citext not null unique,
  login_email citext not null unique,
  display_name text not null default '',
  access_role text not null check (access_role in ('admin','management','progress')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.dashboard_login_email(p_username text)
returns text
language sql
security definer
stable
set search_path = public
as $$
  select login_email::text
  from public.dashboard_users
  where lower(username::text)=lower(trim(p_username))
    and active=true
  limit 1;
$$;

revoke all on function public.dashboard_login_email(text) from public;
grant execute on function public.dashboard_login_email(text) to anon, authenticated;

create or replace function public.current_dashboard_role()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select access_role
  from public.dashboard_users
  where id=auth.uid() and active=true
  limit 1;
$$;

create or replace function public.current_dashboard_username()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select username::text
  from public.dashboard_users
  where id=auth.uid() and active=true
  limit 1;
$$;

-- ============================================================
-- AUDIT LOG
-- ============================================================
create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  user_id uuid,
  username text,
  access_role text,
  table_name text not null,
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  record_key text,
  old_data jsonb,
  new_data jsonb,
  changed_at timestamptz not null default now()
);

create index if not exists idx_audit_log_changed_at on public.audit_log(changed_at desc);
create index if not exists idx_audit_log_user on public.audit_log(username, changed_at desc);
create index if not exists idx_audit_log_table on public.audit_log(table_name, changed_at desc);

create or replace function public.dashboard_record_key(payload jsonb)
returns text
language sql
immutable
as $$
  select coalesce(
    payload->>'cmi_key',
    payload->>'cmi_no',
    payload->>'activity_id',
    payload->>'wbs_id',
    payload->>'setting_key',
    payload->>'resource_name',
    payload->>'username',
    payload->>'id',
    ''
  );
$$;

create or replace function public.audit_dashboard_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_key text;
begin
  if tg_op='INSERT' then
    v_new=to_jsonb(new);
    v_key=public.dashboard_record_key(v_new);
  elsif tg_op='UPDATE' then
    v_old=to_jsonb(old);
    v_new=to_jsonb(new);
    v_key=public.dashboard_record_key(v_new);
  else
    v_old=to_jsonb(old);
    v_key=public.dashboard_record_key(v_old);
  end if;

  insert into public.audit_log
    (user_id,username,access_role,table_name,action,record_key,old_data,new_data)
  values
    (auth.uid(),public.current_dashboard_username(),public.current_dashboard_role(),
     tg_table_name,tg_op,nullif(v_key,''),v_old,v_new);

  if tg_op='DELETE' then return old; else return new; end if;
end;
$$;

-- Progress users may update only actual progress fields in the detailed plan.
create or replace function public.guard_progress_delivery_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text:=public.current_dashboard_role();
begin
  if v_role='progress' then
    if tg_op<>'UPDATE' then
      raise exception 'Progress Update users may only update existing activity progress.';
    end if;

    if new.cmi_key is distinct from old.cmi_key
       or new.cmi_no is distinct from old.cmi_no
       or new.cmi_record_id is distinct from old.cmi_record_id
       or new.activity_id is distinct from old.activity_id
       or new.activity_name is distinct from old.activity_name
       or new.planned_start is distinct from old.planned_start
       or new.planned_finish is distinct from old.planned_finish
       or new.site_resource is distinct from old.site_resource
       or new.offsite_resource is distinct from old.offsite_resource
       or new.display_order is distinct from old.display_order then
      raise exception 'Progress Update users cannot change Delivery Plan allocation or planned data.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_progress_delivery_update on public.cmi_delivery_activities;
create trigger trg_guard_progress_delivery_update
before insert or update or delete on public.cmi_delivery_activities
for each row execute function public.guard_progress_delivery_update();

-- ============================================================
-- UPDATED AT
-- ============================================================
create or replace function public.set_dashboard_user_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at=now(); return new; end;
$$;

drop trigger if exists trg_dashboard_users_updated_at on public.dashboard_users;
create trigger trg_dashboard_users_updated_at
before update on public.dashboard_users
for each row execute function public.set_dashboard_user_updated_at();

-- ============================================================
-- REPLACE EXISTING POLICIES ON DASHBOARD TABLES
-- ============================================================
do $$
declare
  r record;
begin
  for r in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname='public'
      and tablename in (
        'dashboard_users','audit_log','cmis','resources','activity_master',
        'cmi_delivery_activities','delivery_wbs','dashboard_settings'
      )
  loop
    execute format('drop policy if exists %I on %I.%I',r.policyname,r.schemaname,r.tablename);
  end loop;
end $$;

alter table public.dashboard_users enable row level security;
alter table public.audit_log enable row level security;
alter table public.cmis enable row level security;
alter table public.resources enable row level security;
alter table public.activity_master enable row level security;
alter table public.cmi_delivery_activities enable row level security;
alter table public.delivery_wbs enable row level security;
alter table public.dashboard_settings enable row level security;

-- User profile: own profile, plus Admin can see all.
create policy dashboard_users_select
on public.dashboard_users for select to authenticated
using (id=auth.uid() or public.current_dashboard_role()='admin');

create policy dashboard_users_admin_insert
on public.dashboard_users for insert to authenticated
with check (public.current_dashboard_role()='admin');

create policy dashboard_users_admin_update
on public.dashboard_users for update to authenticated
using (public.current_dashboard_role()='admin')
with check (public.current_dashboard_role()='admin');

create policy dashboard_users_admin_delete
on public.dashboard_users for delete to authenticated
using (public.current_dashboard_role()='admin');

-- Audit log is visible only to Admin. Inserts are done by security-definer triggers.
create policy audit_log_admin_select
on public.audit_log for select to authenticated
using (public.current_dashboard_role()='admin');

-- CMI Register: everyone may read; Admin + Management may change.
create policy cmis_authenticated_read
on public.cmis for select to authenticated
using (public.current_dashboard_role() in ('admin','management','progress'));

create policy cmis_admin_management_insert
on public.cmis for insert to authenticated
with check (public.current_dashboard_role() in ('admin','management'));

create policy cmis_admin_management_update
on public.cmis for update to authenticated
using (public.current_dashboard_role() in ('admin','management'))
with check (public.current_dashboard_role() in ('admin','management'));

create policy cmis_admin_management_delete
on public.cmis for delete to authenticated
using (public.current_dashboard_role() in ('admin','management'));

-- Resources: everyone may read; Admin + Management may maintain organisation resources.
create policy resources_authenticated_read
on public.resources for select to authenticated
using (public.current_dashboard_role() in ('admin','management','progress'));

create policy resources_admin_management_insert
on public.resources for insert to authenticated
with check (public.current_dashboard_role() in ('admin','management'));

create policy resources_admin_management_update
on public.resources for update to authenticated
using (public.current_dashboard_role() in ('admin','management'))
with check (public.current_dashboard_role() in ('admin','management'));

create policy resources_admin_management_delete
on public.resources for delete to authenticated
using (public.current_dashboard_role() in ('admin','management'));

-- Activity master: everyone may read names; only Admin maintains the master list.
create policy activity_master_authenticated_read
on public.activity_master for select to authenticated
using (public.current_dashboard_role() in ('admin','management','progress'));

create policy activity_master_admin_insert
on public.activity_master for insert to authenticated
with check (public.current_dashboard_role()='admin');

create policy activity_master_admin_update
on public.activity_master for update to authenticated
using (public.current_dashboard_role()='admin')
with check (public.current_dashboard_role()='admin');

create policy activity_master_admin_delete
on public.activity_master for delete to authenticated
using (public.current_dashboard_role()='admin');

-- Detailed Delivery Plan:
-- all three roles can read;
-- Admin + Management may create/delete/fully edit;
-- Progress users can UPDATE existing rows, constrained by the guard trigger above.
create policy delivery_activity_authenticated_read
on public.cmi_delivery_activities for select to authenticated
using (public.current_dashboard_role() in ('admin','management','progress'));

create policy delivery_activity_admin_management_insert
on public.cmi_delivery_activities for insert to authenticated
with check (public.current_dashboard_role() in ('admin','management'));

create policy delivery_activity_authenticated_update
on public.cmi_delivery_activities for update to authenticated
using (public.current_dashboard_role() in ('admin','management','progress'))
with check (public.current_dashboard_role() in ('admin','management','progress'));

create policy delivery_activity_admin_management_delete
on public.cmi_delivery_activities for delete to authenticated
using (public.current_dashboard_role() in ('admin','management'));

-- Delivery WBS + shared settings: all can read; Admin + Management can change.
create policy delivery_wbs_authenticated_read
on public.delivery_wbs for select to authenticated
using (public.current_dashboard_role() in ('admin','management','progress'));

create policy delivery_wbs_admin_management_insert
on public.delivery_wbs for insert to authenticated
with check (public.current_dashboard_role() in ('admin','management'));

create policy delivery_wbs_admin_management_update
on public.delivery_wbs for update to authenticated
using (public.current_dashboard_role() in ('admin','management'))
with check (public.current_dashboard_role() in ('admin','management'));

create policy delivery_wbs_admin_management_delete
on public.delivery_wbs for delete to authenticated
using (public.current_dashboard_role() in ('admin','management'));

create policy dashboard_settings_authenticated_read
on public.dashboard_settings for select to authenticated
using (public.current_dashboard_role() in ('admin','management','progress'));

create policy dashboard_settings_admin_management_insert
on public.dashboard_settings for insert to authenticated
with check (public.current_dashboard_role() in ('admin','management'));

create policy dashboard_settings_admin_management_update
on public.dashboard_settings for update to authenticated
using (public.current_dashboard_role() in ('admin','management'))
with check (public.current_dashboard_role() in ('admin','management'));

create policy dashboard_settings_admin_management_delete
on public.dashboard_settings for delete to authenticated
using (public.current_dashboard_role() in ('admin','management'));

-- ============================================================
-- AUDIT TRIGGERS
-- ============================================================
do $$
declare
  t text;
begin
  foreach t in array array[
    'dashboard_users','cmis','resources','activity_master',
    'cmi_delivery_activities','delivery_wbs','dashboard_settings'
  ]
  loop
    execute format('drop trigger if exists trg_audit_%I on public.%I',t,t);
    execute format(
      'create trigger trg_audit_%I after insert or update or delete on public.%I for each row execute function public.audit_dashboard_change()',
      t,t
    );
  end loop;
end $$;
