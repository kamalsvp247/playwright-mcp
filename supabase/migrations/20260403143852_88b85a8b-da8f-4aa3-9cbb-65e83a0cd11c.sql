
-- Explicit deny for anon/authenticated on accounts
CREATE POLICY "Deny anon access on accounts"
ON public.accounts FOR ALL
TO anon
USING (false)
WITH CHECK (false);

CREATE POLICY "Deny authenticated access on accounts"
ON public.accounts FOR ALL
TO authenticated
USING (false)
WITH CHECK (false);

-- Explicit deny for anon/authenticated on password_reset_tokens
CREATE POLICY "Deny anon access on password_reset_tokens"
ON public.password_reset_tokens FOR ALL
TO anon
USING (false)
WITH CHECK (false);

CREATE POLICY "Deny authenticated access on password_reset_tokens"
ON public.password_reset_tokens FOR ALL
TO authenticated
USING (false)
WITH CHECK (false);

-- Explicit deny for anon/authenticated on svp_sessions
CREATE POLICY "Deny anon access on svp_sessions"
ON public.svp_sessions FOR ALL
TO anon
USING (false)
WITH CHECK (false);

CREATE POLICY "Deny authenticated access on svp_sessions"
ON public.svp_sessions FOR ALL
TO authenticated
USING (false)
WITH CHECK (false);

-- Explicit deny for anon/authenticated on svp_users
CREATE POLICY "Deny anon access on svp_users"
ON public.svp_users FOR ALL
TO anon
USING (false)
WITH CHECK (false);

CREATE POLICY "Deny authenticated access on svp_users"
ON public.svp_users FOR ALL
TO authenticated
USING (false)
WITH CHECK (false);
