-- Dedicated "Session Lookup" role, separate from the existing
-- ADMIN/AGENCY/USER account.role and from the account_permissions
-- checkbox table. An admin assigns this role directly to a managed
-- USER account; the account then gains access to the numeric
-- exam-session lookup endpoint without needing any other permission
-- flag toggled.
--
-- Kept as its own column (rather than overloading accounts.role) so
-- the existing ADMIN/AGENCY/USER routing, dashboards, and auth checks
-- throughout the app are unaffected.

ALTER TABLE public.accounts
  ADD COLUMN IF NOT EXISTS special_role TEXT NULL
    CHECK (special_role IS NULL OR special_role IN ('SESSION_LOOKUP'));

CREATE INDEX IF NOT EXISTS idx_accounts_special_role
  ON public.accounts(special_role)
  WHERE special_role IS NOT NULL;
