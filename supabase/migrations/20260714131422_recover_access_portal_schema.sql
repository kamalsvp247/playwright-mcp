-- Recover Access Portal schema that was removed after its original migrations
-- had already been recorded as applied. Existing SVP and wallet data is kept.

CREATE TABLE IF NOT EXISTS public.accounts (
  id TEXT NOT NULL DEFAULT gen_random_uuid()::text PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  password TEXT NOT NULL,
  role public.access_role NOT NULL DEFAULT 'USER',
  status public.account_status NOT NULL DEFAULT 'PENDING',
  agency_id TEXT REFERENCES public.accounts(id) ON DELETE SET NULL,
  created_by_id TEXT REFERENCES public.accounts(id) ON DELETE SET NULL,
  permission_mode TEXT NOT NULL DEFAULT 'LEGACY'
    CHECK (permission_mode IN ('LEGACY', 'MANAGED')),
  self_registered BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_accounts_role ON public.accounts(role);
CREATE INDEX IF NOT EXISTS idx_accounts_status ON public.accounts(status);
CREATE INDEX IF NOT EXISTS idx_accounts_agency_id ON public.accounts(agency_id);

DROP TRIGGER IF EXISTS update_accounts_updated_at ON public.accounts;
CREATE TRIGGER update_accounts_updated_at
  BEFORE UPDATE ON public.accounts
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.account_permissions (
  account_id TEXT NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  permission_key TEXT NOT NULL CHECK (permission_key IN (
    'booking.create', 'payment.create', 'wallet.deposit', 'users.create'
  )),
  allowed BOOLEAN NOT NULL DEFAULT false,
  granted_by TEXT REFERENCES public.accounts(id) ON DELETE SET NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, permission_key)
);

CREATE INDEX IF NOT EXISTS idx_account_permissions_key
  ON public.account_permissions(permission_key, allowed);

CREATE TABLE IF NOT EXISTS public.booking_wallet_holds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id TEXT NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  amount NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
  status TEXT NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'COMPLETED', 'RELEASED', 'EXPIRED')),
  idempotency_key TEXT NOT NULL UNIQUE,
  reservation_id TEXT,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '15 minutes'),
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_booking_wallet_holds_available
  ON public.booking_wallet_holds(account_id, status, expires_at);

CREATE TABLE IF NOT EXISTS public.access_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_account_id TEXT REFERENCES public.accounts(id) ON DELETE SET NULL,
  target_account_id TEXT REFERENCES public.accounts(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_access_audit_log_target_created
  ON public.access_audit_log(target_account_id, created_at DESC);

-- The account table was removed while wallet rows survived. Restore the
-- constraints without deleting those historical orphan rows. PostgreSQL still
-- enforces NOT VALID foreign keys for all new or changed rows.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'wallets_account_id_fkey' AND conrelid = 'public.wallets'::regclass) THEN
    ALTER TABLE public.wallets ADD CONSTRAINT wallets_account_id_fkey
      FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'wallet_transactions_account_id_fkey' AND conrelid = 'public.wallet_transactions'::regclass) THEN
    ALTER TABLE public.wallet_transactions ADD CONSTRAINT wallet_transactions_account_id_fkey
      FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE RESTRICT NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'wallet_transactions_created_by_fkey' AND conrelid = 'public.wallet_transactions'::regclass) THEN
    ALTER TABLE public.wallet_transactions ADD CONSTRAINT wallet_transactions_created_by_fkey
      FOREIGN KEY (created_by) REFERENCES public.accounts(id) ON DELETE SET NULL NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'deposit_requests_account_id_fkey' AND conrelid = 'public.deposit_requests'::regclass) THEN
    ALTER TABLE public.deposit_requests ADD CONSTRAINT deposit_requests_account_id_fkey
      FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'deposit_requests_processed_by_fkey' AND conrelid = 'public.deposit_requests'::regclass) THEN
    ALTER TABLE public.deposit_requests ADD CONSTRAINT deposit_requests_processed_by_fkey
      FOREIGN KEY (processed_by) REFERENCES public.accounts(id) ON DELETE SET NULL NOT VALID;
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS ensure_account_wallet_after_insert ON public.accounts;
CREATE TRIGGER ensure_account_wallet_after_insert
  AFTER INSERT ON public.accounts
  FOR EACH ROW EXECUTE FUNCTION public.ensure_account_wallet();

DROP TRIGGER IF EXISTS wallet_transactions_immutable ON public.wallet_transactions;
CREATE TRIGGER wallet_transactions_immutable
  BEFORE UPDATE OR DELETE ON public.wallet_transactions
  FOR EACH ROW EXECUTE FUNCTION public.reject_wallet_transaction_mutation();

ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.booking_wallet_holds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.access_audit_log ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.accounts FROM anon, authenticated;
REVOKE ALL ON TABLE public.account_permissions FROM anon, authenticated;
REVOKE ALL ON TABLE public.wallets FROM anon, authenticated;
REVOKE ALL ON TABLE public.wallet_transactions FROM anon, authenticated;
REVOKE ALL ON TABLE public.booking_wallet_holds FROM anon, authenticated;
REVOKE ALL ON TABLE public.deposit_requests FROM anon, authenticated;
REVOKE ALL ON TABLE public.access_audit_log FROM anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.accounts TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.account_permissions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.wallets TO service_role;
GRANT SELECT, INSERT ON TABLE public.wallet_transactions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.booking_wallet_holds TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.deposit_requests TO service_role;
GRANT SELECT, INSERT ON TABLE public.access_audit_log TO service_role;
