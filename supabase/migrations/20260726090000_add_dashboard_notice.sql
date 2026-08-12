-- A single admin-controlled announcement banner shown on every user's
-- dashboard (e.g. "system under maintenance" notices). Singleton row,
-- toggled on/off, editable message.

CREATE TABLE public.access_dashboard_notice (
  singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  message TEXT NOT NULL DEFAULT '',
  updated_by TEXT REFERENCES public.accounts(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.access_dashboard_notice(singleton, enabled, message)
VALUES (TRUE, FALSE, '')
ON CONFLICT (singleton) DO NOTHING;

ALTER TABLE public.access_dashboard_notice ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.access_dashboard_notice FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.access_dashboard_notice TO service_role;
