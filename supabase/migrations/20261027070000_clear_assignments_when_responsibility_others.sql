-- Clear current CMI Team scheduling assignments when responsibility becomes Others.
-- This acts on future manual overrides only; existing CMIs are not backfilled.
CREATE OR REPLACE FUNCTION public.clear_cmi_team_assignments_for_others()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_record_id text;
BEGIN
  IF NEW.latest_responsibility IS DISTINCT FROM 'Others'
    OR (TG_OP = 'UPDATE' AND OLD.latest_responsibility IS NOT DISTINCT FROM 'Others')
  THEN
    RETURN NEW;
  END IF;

  v_record_id := NULLIF(BTRIM(NEW.cmi_record_id), '');
  IF v_record_id IS NULL THEN
    RAISE EXCEPTION 'Cannot clear CMI Team assignment: missing CMI record ID';
  END IF;

  -- Use the register record ID, not CMI number: a number can have duplicates.
  UPDATE public.cmi_processing_paths
     SET processing_path = 'N/A', updated_at = now()
   WHERE cmi_record_id = v_record_id
     AND processing_path IS DISTINCT FROM 'N/A';

  -- If no processing-path record exists, create a record-specific override.
  IF NOT EXISTS (
    SELECT 1 FROM public.cmi_processing_paths
     WHERE cmi_record_id = v_record_id
  ) THEN
    INSERT INTO public.cmi_processing_paths
      (cmi_key, cmi_record_id, cmi_no, processing_path, updated_at)
    VALUES
      (v_record_id, v_record_id, NEW.cmi_no, 'N/A', now())
    ON CONFLICT (cmi_key) DO UPDATE
      SET processing_path = EXCLUDED.processing_path,
          updated_at = now()
    WHERE public.cmi_processing_paths.cmi_record_id = EXCLUDED.cmi_record_id;
  END IF;

  -- Null means unassigned in the activity schema; the UI should display N/A.
  -- Do not touch progress, dates, costs, activity rows or historical audit data.
  UPDATE public.cmi_delivery_activities
     SET site_resource = NULL,
         offsite_resource = NULL,
         updated_at = now()
   WHERE cmi_record_id = v_record_id
     AND (site_resource IS NOT NULL OR offsite_resource IS NOT NULL);

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS clear_cmi_team_assignments_on_others ON public.cmi_delivery_responsibility_latest;
CREATE TRIGGER clear_cmi_team_assignments_on_others
AFTER INSERT OR UPDATE OF latest_responsibility
ON public.cmi_delivery_responsibility_latest
FOR EACH ROW
EXECUTE FUNCTION public.clear_cmi_team_assignments_for_others();
