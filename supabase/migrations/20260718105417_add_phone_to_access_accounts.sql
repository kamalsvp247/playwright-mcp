-- Existing accounts remain valid without a phone number. Every new Agency/User
-- creation path enforces a canonical international number at the API boundary.
ALTER TABLE public.accounts
  ADD COLUMN IF NOT EXISTS phone TEXT;

ALTER TABLE public.accounts
  DROP CONSTRAINT IF EXISTS accounts_phone_e164_check;

ALTER TABLE public.accounts
  ADD CONSTRAINT accounts_phone_e164_check
  CHECK (phone IS NULL OR phone ~ '^\+[1-9][0-9]{7,14}$');

CREATE UNIQUE INDEX IF NOT EXISTS accounts_phone_unique
  ON public.accounts(phone)
  WHERE phone IS NOT NULL;
