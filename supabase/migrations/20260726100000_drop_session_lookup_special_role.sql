-- Revert: remove the SESSION_LOOKUP special_role feature entirely.
DROP INDEX IF EXISTS public.idx_accounts_special_role;

ALTER TABLE public.accounts
  DROP COLUMN IF EXISTS special_role;
