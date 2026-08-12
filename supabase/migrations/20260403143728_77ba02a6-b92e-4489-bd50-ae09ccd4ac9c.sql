
-- Enable RLS on tables that don't have it yet
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.password_reset_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.svp_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.svp_users ENABLE ROW LEVEL SECURITY;

-- Policies for accounts: only service role (edge functions) can access
CREATE POLICY "Service role full access on accounts"
ON public.accounts FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Policies for password_reset_tokens: only service role
CREATE POLICY "Service role full access on password_reset_tokens"
ON public.password_reset_tokens FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Policies for svp_sessions: only service role
CREATE POLICY "Service role full access on svp_sessions"
ON public.svp_sessions FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Policies for svp_users: only service role
CREATE POLICY "Service role full access on svp_users"
ON public.svp_users FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- test_centers: add service role write access (read policy already exists)
CREATE POLICY "Service role full access on test_centers"
ON public.test_centers FOR ALL
TO service_role
USING (true)
WITH CHECK (true);
