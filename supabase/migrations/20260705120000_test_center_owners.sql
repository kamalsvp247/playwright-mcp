-- Links an SVP account (public.svp_users) to the test center(s) it owns/manages.
-- Ownership is determined by this table, not by anything the SVP upstream API returns:
-- the test-center-owner portal is a feature of this app, layered on top of the real
-- SVP login (svp_users / svp_sessions), same as the individual-labor booking flow.

CREATE TABLE public.test_center_owners (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL REFERENCES public.svp_users(id) ON DELETE CASCADE,
  site_id INTEGER NOT NULL REFERENCES public.test_centers(site_id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'owner' CHECK (role IN ('owner', 'manager', 'viewer')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, site_id)
);

CREATE INDEX idx_test_center_owners_user_id ON public.test_center_owners(user_id);
CREATE INDEX idx_test_center_owners_site_id ON public.test_center_owners(site_id);

ALTER TABLE public.test_center_owners ENABLE ROW LEVEL SECURITY;

-- Edge functions use the service_role key and bypass RLS. No end-user policies are
-- added since users never query this table directly (mirrors svp_users / svp_sessions).
CREATE POLICY "Service role full access on test_center_owners"
  ON public.test_center_owners FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
