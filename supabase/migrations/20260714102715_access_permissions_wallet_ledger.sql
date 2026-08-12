-- Access Portal RBAC + wallet ledger.
-- Existing accounts remain in LEGACY mode so current booking/payment behavior
-- is unchanged until an administrator explicitly switches them to MANAGED.

ALTER TABLE public.accounts
  ADD COLUMN IF NOT EXISTS permission_mode TEXT NOT NULL DEFAULT 'LEGACY'
    CHECK (permission_mode IN ('LEGACY', 'MANAGED')),
  ADD COLUMN IF NOT EXISTS self_registered BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE public.account_permissions (
  account_id TEXT NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  permission_key TEXT NOT NULL CHECK (permission_key IN (
    'booking.create',
    'payment.create',
    'wallet.deposit',
    'users.create'
  )),
  allowed BOOLEAN NOT NULL DEFAULT false,
  granted_by TEXT REFERENCES public.accounts(id) ON DELETE SET NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, permission_key)
);

CREATE INDEX idx_account_permissions_key
  ON public.account_permissions(permission_key, allowed);

CREATE TABLE public.wallets (
  account_id TEXT PRIMARY KEY REFERENCES public.accounts(id) ON DELETE CASCADE,
  balance NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  currency TEXT NOT NULL DEFAULT 'CREDIT',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id TEXT NOT NULL REFERENCES public.accounts(id) ON DELETE RESTRICT,
  transaction_type TEXT NOT NULL CHECK (transaction_type IN (
    'deposit',
    'booking_debit',
    'admin_credit',
    'admin_debit',
    'refund'
  )),
  amount NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
  direction TEXT NOT NULL CHECK (direction IN ('credit', 'debit')),
  balance_after NUMERIC(14, 2) NOT NULL CHECK (balance_after >= 0),
  reference_type TEXT,
  reference_id TEXT,
  idempotency_key TEXT NOT NULL UNIQUE,
  description TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by TEXT REFERENCES public.accounts(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_wallet_transactions_account_created
  ON public.wallet_transactions(account_id, created_at DESC);
CREATE INDEX idx_wallet_transactions_reference
  ON public.wallet_transactions(reference_type, reference_id);

CREATE TABLE public.booking_wallet_holds (
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

CREATE INDEX idx_booking_wallet_holds_available
  ON public.booking_wallet_holds(account_id, status, expires_at);

CREATE TABLE public.deposit_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id TEXT NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  amount NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
  status TEXT NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED')),
  payment_method TEXT NOT NULL,
  payment_reference TEXT,
  user_note TEXT,
  admin_note TEXT,
  processed_by TEXT REFERENCES public.accounts(id) ON DELETE SET NULL,
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_deposit_requests_status_created
  ON public.deposit_requests(status, created_at DESC);
CREATE INDEX idx_deposit_requests_account_created
  ON public.deposit_requests(account_id, created_at DESC);

CREATE TABLE public.access_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_account_id TEXT REFERENCES public.accounts(id) ON DELETE SET NULL,
  target_account_id TEXT REFERENCES public.accounts(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_access_audit_log_target_created
  ON public.access_audit_log(target_account_id, created_at DESC);

-- Every account gets a wallet, including pre-existing accounts.
INSERT INTO public.wallets(account_id)
SELECT id FROM public.accounts
ON CONFLICT (account_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.ensure_account_wallet()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.wallets(account_id)
  VALUES (NEW.id)
  ON CONFLICT (account_id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE TRIGGER ensure_account_wallet_after_insert
  AFTER INSERT ON public.accounts
  FOR EACH ROW EXECUTE FUNCTION public.ensure_account_wallet();

CREATE OR REPLACE FUNCTION public.reject_wallet_transaction_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'wallet transactions are immutable';
END;
$$;

CREATE TRIGGER wallet_transactions_immutable
  BEFORE UPDATE OR DELETE ON public.wallet_transactions
  FOR EACH ROW EXECUTE FUNCTION public.reject_wallet_transaction_mutation();

CREATE OR REPLACE FUNCTION public.wallet_place_booking_hold(
  p_account_id TEXT,
  p_amount NUMERIC,
  p_idempotency_key TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_wallet public.wallets%ROWTYPE;
  v_existing public.booking_wallet_holds%ROWTYPE;
  v_reserved NUMERIC(14, 2);
  v_hold_id UUID;
BEGIN
  IF p_amount <= 0 OR btrim(coalesce(p_idempotency_key, '')) = '' THEN
    RAISE EXCEPTION 'invalid hold request';
  END IF;

  SELECT * INTO v_existing
  FROM public.booking_wallet_holds
  WHERE idempotency_key = p_idempotency_key;
  IF FOUND THEN
    IF v_existing.account_id <> p_account_id OR v_existing.amount <> p_amount THEN
      RAISE EXCEPTION 'idempotency key conflict';
    END IF;
    IF v_existing.status = 'COMPLETED' OR
       (v_existing.status = 'PENDING' AND v_existing.expires_at > now()) THEN
      RETURN v_existing.id;
    END IF;
    v_hold_id := v_existing.id;
  END IF;

  INSERT INTO public.wallets(account_id) VALUES (p_account_id)
  ON CONFLICT (account_id) DO NOTHING;

  SELECT * INTO v_wallet
  FROM public.wallets
  WHERE account_id = p_account_id
  FOR UPDATE;

  UPDATE public.booking_wallet_holds
  SET status = 'EXPIRED'
  WHERE account_id = p_account_id
    AND status = 'PENDING'
    AND expires_at <= now();

  SELECT coalesce(sum(amount), 0) INTO v_reserved
  FROM public.booking_wallet_holds
  WHERE account_id = p_account_id
    AND status = 'PENDING'
    AND expires_at > now();

  IF v_wallet.balance - v_reserved < p_amount THEN
    RAISE EXCEPTION 'insufficient wallet balance';
  END IF;

  IF v_hold_id IS NOT NULL THEN
    UPDATE public.booking_wallet_holds
    SET status = 'PENDING', expires_at = now() + interval '15 minutes',
        reservation_id = NULL, completed_at = NULL
    WHERE id = v_hold_id;
  ELSE
    INSERT INTO public.booking_wallet_holds(account_id, amount, idempotency_key)
    VALUES (p_account_id, p_amount, p_idempotency_key)
    RETURNING id INTO v_hold_id;
  END IF;

  RETURN v_hold_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.wallet_complete_booking_hold(
  p_hold_id UUID,
  p_reservation_id TEXT,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_hold public.booking_wallet_holds%ROWTYPE;
  v_wallet public.wallets%ROWTYPE;
  v_tx public.wallet_transactions%ROWTYPE;
BEGIN
  SELECT * INTO v_hold
  FROM public.booking_wallet_holds
  WHERE id = p_hold_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'booking hold not found'; END IF;

  SELECT * INTO v_tx
  FROM public.wallet_transactions
  WHERE idempotency_key = 'booking:' || p_hold_id::text;
  IF FOUND THEN RETURN v_tx; END IF;

  IF v_hold.status <> 'PENDING' OR v_hold.expires_at <= now() THEN
    RAISE EXCEPTION 'booking hold is not active';
  END IF;

  SELECT * INTO v_wallet
  FROM public.wallets
  WHERE account_id = v_hold.account_id
  FOR UPDATE;

  IF v_wallet.balance < v_hold.amount THEN
    RAISE EXCEPTION 'insufficient wallet balance';
  END IF;

  UPDATE public.wallets
  SET balance = balance - v_hold.amount, updated_at = now()
  WHERE account_id = v_hold.account_id
  RETURNING * INTO v_wallet;

  INSERT INTO public.wallet_transactions(
    account_id, transaction_type, amount, direction, balance_after,
    reference_type, reference_id, idempotency_key, description, metadata
  ) VALUES (
    v_hold.account_id, 'booking_debit', v_hold.amount, 'debit', v_wallet.balance,
    'reservation', p_reservation_id, 'booking:' || p_hold_id::text,
    'Booking completed', coalesce(p_metadata, '{}'::jsonb)
  ) RETURNING * INTO v_tx;

  UPDATE public.booking_wallet_holds
  SET status = 'COMPLETED', reservation_id = p_reservation_id, completed_at = now()
  WHERE id = p_hold_id;

  RETURN v_tx;
END;
$$;

CREATE OR REPLACE FUNCTION public.wallet_release_booking_hold(p_hold_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.booking_wallet_holds
  SET status = 'RELEASED'
  WHERE id = p_hold_id AND status = 'PENDING';
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.wallet_post_adjustment(
  p_account_id TEXT,
  p_amount NUMERIC,
  p_direction TEXT,
  p_transaction_type TEXT,
  p_idempotency_key TEXT,
  p_description TEXT,
  p_created_by TEXT DEFAULT NULL,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_wallet public.wallets%ROWTYPE;
  v_tx public.wallet_transactions%ROWTYPE;
  v_next NUMERIC(14, 2);
BEGIN
  IF p_amount <= 0 OR p_direction NOT IN ('credit', 'debit') THEN
    RAISE EXCEPTION 'invalid wallet adjustment';
  END IF;
  IF p_transaction_type NOT IN ('deposit', 'admin_credit', 'admin_debit', 'refund') THEN
    RAISE EXCEPTION 'invalid transaction type';
  END IF;

  SELECT * INTO v_tx FROM public.wallet_transactions
  WHERE idempotency_key = p_idempotency_key;
  IF FOUND THEN RETURN v_tx; END IF;

  INSERT INTO public.wallets(account_id) VALUES (p_account_id)
  ON CONFLICT (account_id) DO NOTHING;
  SELECT * INTO v_wallet FROM public.wallets
  WHERE account_id = p_account_id FOR UPDATE;

  v_next := v_wallet.balance + CASE WHEN p_direction = 'credit' THEN p_amount ELSE -p_amount END;
  IF v_next < 0 THEN RAISE EXCEPTION 'insufficient wallet balance'; END IF;

  UPDATE public.wallets SET balance = v_next, updated_at = now()
  WHERE account_id = p_account_id RETURNING * INTO v_wallet;

  INSERT INTO public.wallet_transactions(
    account_id, transaction_type, amount, direction, balance_after,
    reference_type, reference_id, idempotency_key, description, metadata, created_by
  ) VALUES (
    p_account_id, p_transaction_type, p_amount, p_direction, v_wallet.balance,
    p_reference_type, p_reference_id, p_idempotency_key, p_description,
    coalesce(p_metadata, '{}'::jsonb), p_created_by
  ) RETURNING * INTO v_tx;
  RETURN v_tx;
END;
$$;

CREATE OR REPLACE FUNCTION public.wallet_approve_deposit(
  p_deposit_id UUID,
  p_admin_id TEXT,
  p_admin_note TEXT DEFAULT NULL
)
RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_deposit public.deposit_requests%ROWTYPE;
  v_tx public.wallet_transactions%ROWTYPE;
BEGIN
  SELECT * INTO v_deposit
  FROM public.deposit_requests
  WHERE id = p_deposit_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'deposit request not found'; END IF;

  SELECT * INTO v_tx FROM public.wallet_transactions
  WHERE idempotency_key = 'deposit:' || p_deposit_id::text;
  IF FOUND THEN RETURN v_tx; END IF;

  IF v_deposit.status <> 'PENDING' THEN
    RAISE EXCEPTION 'deposit request is not pending';
  END IF;

  SELECT * INTO v_tx FROM public.wallet_post_adjustment(
    v_deposit.account_id,
    v_deposit.amount,
    'credit',
    'deposit',
    'deposit:' || p_deposit_id::text,
    'Deposit approved',
    p_admin_id,
    'deposit_request',
    p_deposit_id::text,
    jsonb_build_object('payment_method', v_deposit.payment_method, 'payment_reference', v_deposit.payment_reference)
  );

  UPDATE public.deposit_requests
  SET status = 'APPROVED', admin_note = p_admin_note,
      processed_by = p_admin_id, processed_at = now(), updated_at = now()
  WHERE id = p_deposit_id;

  RETURN v_tx;
END;
$$;

CREATE OR REPLACE FUNCTION public.wallet_reject_deposit(
  p_deposit_id UUID,
  p_admin_id TEXT,
  p_admin_note TEXT DEFAULT NULL
)
RETURNS public.deposit_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_deposit public.deposit_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_deposit
  FROM public.deposit_requests
  WHERE id = p_deposit_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'deposit request not found'; END IF;
  IF v_deposit.status <> 'PENDING' THEN
    RAISE EXCEPTION 'deposit request is not pending';
  END IF;

  UPDATE public.deposit_requests
  SET status = 'REJECTED', admin_note = p_admin_note,
      processed_by = p_admin_id, processed_at = now(), updated_at = now()
  WHERE id = p_deposit_id
  RETURNING * INTO v_deposit;
  RETURN v_deposit;
END;
$$;

-- Edge Functions use service_role. Browser roles get no direct table access.
ALTER TABLE public.account_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.booking_wallet_holds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.access_audit_log ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.account_permissions FROM anon, authenticated;
REVOKE ALL ON TABLE public.wallets FROM anon, authenticated;
REVOKE ALL ON TABLE public.wallet_transactions FROM anon, authenticated;
REVOKE ALL ON TABLE public.booking_wallet_holds FROM anon, authenticated;
REVOKE ALL ON TABLE public.deposit_requests FROM anon, authenticated;
REVOKE ALL ON TABLE public.access_audit_log FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.ensure_account_wallet() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.wallet_place_booking_hold(TEXT, NUMERIC, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.wallet_complete_booking_hold(UUID, TEXT, JSONB) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.wallet_release_booking_hold(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.wallet_post_adjustment(TEXT, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.wallet_approve_deposit(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.wallet_reject_deposit(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.ensure_account_wallet() TO service_role;
GRANT EXECUTE ON FUNCTION public.wallet_place_booking_hold(TEXT, NUMERIC, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.wallet_complete_booking_hold(UUID, TEXT, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION public.wallet_release_booking_hold(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.wallet_post_adjustment(TEXT, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION public.wallet_approve_deposit(UUID, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.wallet_reject_deposit(UUID, TEXT, TEXT) TO service_role;
