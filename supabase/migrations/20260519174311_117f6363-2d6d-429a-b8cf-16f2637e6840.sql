CREATE TABLE public.exam_session_centers (
  exam_session_id BIGINT PRIMARY KEY,
  site_id INTEGER NOT NULL REFERENCES public.test_centers(site_id) ON DELETE RESTRICT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_exam_session_centers_site_id ON public.exam_session_centers(site_id);

ALTER TABLE public.exam_session_centers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read exam session centers"
ON public.exam_session_centers
FOR SELECT
TO anon, authenticated
USING (true);

CREATE POLICY "Service role full access on exam_session_centers"
ON public.exam_session_centers
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

CREATE TRIGGER update_exam_session_centers_updated_at
BEFORE UPDATE ON public.exam_session_centers
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();