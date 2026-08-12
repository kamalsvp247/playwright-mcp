
-- Drop overly permissive policies
DROP POLICY "Service role full access on svp_users" ON public.svp_users;
DROP POLICY "Service role full access on svp_sessions" ON public.svp_sessions;

-- These tables should only be accessed by edge functions via service_role key
-- which bypasses RLS entirely. No policies needed for regular users.
