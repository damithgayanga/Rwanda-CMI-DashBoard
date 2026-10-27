-- Permit N/A only as the non-team scheduling processing path.
ALTER TABLE public.cmi_processing_paths
  DROP CONSTRAINT IF EXISTS cmi_processing_path_allowed;
ALTER TABLE public.cmi_processing_paths
  ADD CONSTRAINT cmi_processing_path_allowed
  CHECK (processing_path IN ('Start from Off-Site', 'On-Site Only', 'N/A'));
