
-- Create enums for roles and account statuses
CREATE TYPE public.access_role AS ENUM ('ADMIN', 'AGENCY', 'USER');
CREATE TYPE public.account_status AS ENUM ('PENDING', 'ACTIVE', 'BLOCKED');

-- Create accounts table
CREATE TABLE public.accounts (
  id TEXT NOT NULL DEFAULT (gen_random_uuid())::text PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  password TEXT NOT NULL,
  role public.access_role NOT NULL DEFAULT 'USER',
  status public.account_status NOT NULL DEFAULT 'PENDING',
  agency_id TEXT REFERENCES public.accounts(id),
  created_by_id TEXT REFERENCES public.accounts(id),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_accounts_role ON public.accounts(role);
CREATE INDEX idx_accounts_status ON public.accounts(status);
CREATE INDEX idx_accounts_agency_id ON public.accounts(agency_id);

-- Enable RLS
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;

-- RLS: Allow service role full access (edge functions use service role)
-- No public access policies needed since all access goes through edge functions

-- Updated_at trigger
CREATE TRIGGER update_accounts_updated_at
  BEFORE UPDATE ON public.accounts
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
