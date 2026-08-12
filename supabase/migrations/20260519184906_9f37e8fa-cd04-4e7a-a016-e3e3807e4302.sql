
CREATE TABLE public.section_center_rules (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  city text,
  category_id text,
  section text,
  site_id integer NOT NULL,
  priority integer NOT NULL DEFAULT 0,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE INDEX idx_section_center_rules_lookup ON public.section_center_rules (city, category_id, section);

ALTER TABLE public.section_center_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read section rules"
  ON public.section_center_rules FOR SELECT
  TO anon, authenticated
  USING (true);

CREATE POLICY "Service role full access on section_center_rules"
  ON public.section_center_rules FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE TRIGGER update_section_center_rules_updated_at
  BEFORE UPDATE ON public.section_center_rules
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
