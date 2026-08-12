
-- Create users table (matches Prisma User model)
CREATE TABLE public.svp_users (
  id TEXT NOT NULL DEFAULT gen_random_uuid()::text PRIMARY KEY,
  login TEXT NOT NULL UNIQUE,
  svp_user_id INTEGER,
  email TEXT,
  full_name TEXT,
  phone TEXT,
  password_hash TEXT,
  role TEXT NOT NULL DEFAULT 'USER',
  is_approved BOOLEAN NOT NULL DEFAULT false,
  approved_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create sessions table (matches Prisma Session model)
CREATE TABLE public.svp_sessions (
  id TEXT NOT NULL DEFAULT gen_random_uuid()::text PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES public.svp_users(id) ON DELETE CASCADE,
  refresh_token_hash TEXT NOT NULL,
  refresh_expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  revoked_at TIMESTAMP WITH TIME ZONE,
  svp_access_enc TEXT,
  svp_access_exp TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.svp_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.svp_sessions ENABLE ROW LEVEL SECURITY;

-- Edge functions use service_role key so they bypass RLS.
-- No user-facing RLS policies needed since users never query these tables directly.
-- Add a policy for service role operations (edge functions use service key)
CREATE POLICY "Service role full access on svp_users"
  ON public.svp_users FOR ALL
  USING (true) WITH CHECK (true);

CREATE POLICY "Service role full access on svp_sessions"
  ON public.svp_sessions FOR ALL
  USING (true) WITH CHECK (true);

-- Index for session lookups
CREATE INDEX idx_svp_sessions_user_id ON public.svp_sessions(user_id);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE TRIGGER update_svp_sessions_updated_at
  BEFORE UPDATE ON public.svp_sessions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
