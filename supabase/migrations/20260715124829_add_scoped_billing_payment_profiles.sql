-- Global Admin payment receivers remain the fallback for candidates without an
-- agency-specific profile. Agency profiles apply only to that agency's users.
ALTER TABLE public.access_billing_settings
  ADD COLUMN bkash_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN bkash_number TEXT,
  ADD COLUMN bkash_instructions TEXT,
  ADD COLUMN nagad_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN nagad_number TEXT,
  ADD COLUMN nagad_instructions TEXT;

CREATE TABLE public.agency_billing_settings (
  agency_id TEXT PRIMARY KEY REFERENCES public.accounts(id) ON DELETE CASCADE,
  booking_credit_cost NUMERIC(12,2) NOT NULL DEFAULT 1
    CHECK (booking_credit_cost >= 0 AND booking_credit_cost <= 1000000),
  bkash_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  bkash_number TEXT,
  bkash_instructions TEXT,
  nagad_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  nagad_number TEXT,
  nagad_instructions TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.deposit_requests
  ADD COLUMN receiver_account TEXT,
  ADD COLUMN billing_owner_id TEXT REFERENCES public.accounts(id) ON DELETE SET NULL;

CREATE INDEX idx_deposit_requests_billing_owner_created
  ON public.deposit_requests(billing_owner_id, created_at DESC);

ALTER TABLE public.agency_billing_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.agency_billing_settings FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.agency_billing_settings TO service_role;
