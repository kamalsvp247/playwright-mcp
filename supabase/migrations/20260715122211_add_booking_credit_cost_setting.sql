-- Admin-controlled credit charge applied to each successfully created reservation.
-- The setting is private to service-role Edge Functions; browser roles cannot access it.
CREATE TABLE public.access_billing_settings (
  singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
  booking_credit_cost NUMERIC(12,2) NOT NULL DEFAULT 1
    CHECK (booking_credit_cost >= 0 AND booking_credit_cost <= 1000000),
  updated_by TEXT REFERENCES public.accounts(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.access_billing_settings(singleton, booking_credit_cost)
VALUES (TRUE, 1)
ON CONFLICT (singleton) DO NOTHING;

ALTER TABLE public.access_billing_settings ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.access_billing_settings FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.access_billing_settings TO service_role;
