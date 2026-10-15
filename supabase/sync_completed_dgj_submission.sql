-- Preserve existing validation, role checks and function grants.
do $patch$
declare def text;
begin
 select pg_get_functiondef('public.dashboard_save_progress(text,text,text,text,text,date,date,numeric,numeric,numeric)'::regprocedure) into def;
 if position('Completion and classification are saved atomically' in def)=0 then
   def:=replace(def,E'end;\n$function$','
  -- Completion and classification are saved atomically for all progress roles.
  if v_is_submission and p_progress_pct>=100 and p_actual_finish is not null then
    update public.resources res
    set role=jsonb_set(res.role::jsonb,''{records}'',(
      select jsonb_agg(case
        when r->>''id''=p_cmi_record_id and r->>''mainCategory''=''TBS by CMI Team''
        then r || jsonb_build_object(''mainCategory'',''Submitted - CMI Team'',
          ''wasCmiTeam'',true,''mainCategoryUpdatedAt'',now())
        else r end order by ord)
      from jsonb_array_elements(res.role::jsonb->''records'') with ordinality as rows(r,ord)
    ))::text,updated_at=now()
    where res.resource_name=''__CMI_DASHBOARD_SHARED_STATE__''
      and exists (select 1 from jsonb_array_elements(res.role::jsonb->''records'') r
        where r->>''id''=p_cmi_record_id and r->>''mainCategory''=''TBS by CMI Team'');
  end if;
'||E'end;\n$function$');
   execute def;
 end if;
 select pg_get_functiondef('public.dashboard_save_shared_state(jsonb)'::regprocedure) into def;
 if position('Reconcile by stable register row ID' in def)=0 then
   def:=replace(def,'  update public.resources','
  -- Reconcile by stable register row ID, never by displayed CMI number.
  p_payload := jsonb_set(p_payload, ''{records}'', coalesce((
    select jsonb_agg(
      case when r->>''mainCategory''=''TBS by CMI Team'' and exists (
        select 1 from public.cmi_delivery_activities a
        where a.cmi_record_id=r->>''id''
          and (a.activity_id=''act-submit-dgj'' or lower(a.activity_name) like ''%submission to dgj%'')
          and a.progress_pct>=100 and a.actual_finish is not null
      ) then r || jsonb_build_object(''mainCategory'',''Submitted - CMI Team'',
        ''wasCmiTeam'',true,''mainCategoryUpdatedAt'',now())
      else r end order by ord
    )
    from jsonb_array_elements(p_payload->''records'') with ordinality as rows(r,ord)
  ), ''[]''::jsonb));
'||E'\n  update public.resources');
   execute def;
 end if;
end $patch$;

-- Repair completed team submissions already saved before this fix.
update public.resources res
set role=jsonb_set(res.role::jsonb,'{records}',(
  select jsonb_agg(case when r->>'mainCategory'='TBS by CMI Team' and exists (
    select 1 from public.cmi_delivery_activities a
    where a.cmi_record_id=r->>'id' and a.activity_id='act-submit-dgj'
      and a.progress_pct>=100 and a.actual_finish is not null
  ) then r || jsonb_build_object('mainCategory','Submitted - CMI Team','wasCmiTeam',true,'mainCategoryUpdatedAt',now())
  else r end order by ord)
  from jsonb_array_elements(res.role::jsonb->'records') with ordinality as rows(r,ord)
))::text,updated_at=now()
where res.resource_name='__CMI_DASHBOARD_SHARED_STATE__';
