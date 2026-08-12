-- Distinguish agency-issued manual credits/debits from administrator actions
-- while preserving the existing immutable wallet ledger.
ALTER TABLE public.wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_transaction_type_check;

ALTER TABLE public.wallet_transactions
  ADD CONSTRAINT wallet_transactions_transaction_type_check
  CHECK (transaction_type IN (
    'deposit',
    'booking_debit',
    'admin_credit',
    'admin_debit',
    'agency_credit',
    'agency_debit',
    'refund'
  ));

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
  IF p_transaction_type NOT IN (
    'deposit', 'admin_credit', 'admin_debit',
    'agency_credit', 'agency_debit', 'refund'
  ) THEN
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

REVOKE ALL ON FUNCTION public.wallet_post_adjustment(
  TEXT, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.wallet_post_adjustment(
  TEXT, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB
) TO service_role;
