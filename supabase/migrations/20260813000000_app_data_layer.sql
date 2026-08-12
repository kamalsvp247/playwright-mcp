-- App data layer for the Next.js SVP scraper (kamalsvp247-urban-waddle).
-- Replaces the local better-sqlite3 file DB with Supabase Postgres so app
-- state persists across serverless invocations and shares the live project.
-- Table names are prefixed with `app_` to avoid colliding with the SVP
-- multi-user schema that already exists on this project (e.g. svp_sessions).

create table if not exists public.app_users (
  id            bigint generated always as identity primary key,
  username      text unique not null,
  password_hash text not null,
  role          text not null default 'staff',
  status        text not null default 'active',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table if not exists public.app_sessions (
  id          text primary key,
  user_id     bigint not null references public.app_users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null
);

create table if not exists public.app_svp_sessions (
  id            bigint generated always as identity primary key,
  user_id       bigint unique not null references public.app_users(id) on delete cascade,
  token         text,
  token_expiry  timestamptz,
  storage_json  text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table if not exists public.app_audit_log (
  id          bigint generated always as identity primary key,
  user_id     bigint references public.app_users(id) on delete set null,
  action      text not null,
  details     jsonb,
  ip          text,
  created_at  timestamptz not null default now()
);

create index if not exists idx_app_sessions_user_id      on public.app_sessions(user_id);
create index if not exists idx_app_svp_sessions_user_id  on public.app_svp_sessions(user_id);
create index if not exists idx_app_audit_log_user_id     on public.app_audit_log(user_id);

-- RLS: the app uses the service_role key (which bypasses RLS). These enable
-- flags are here so anonymous/authenticated Supabase roles cannot read app
-- data if the anon key is ever exposed.
alter table public.app_users          enable row level security;
alter table public.app_sessions       enable row level security;
alter table public.app_svp_sessions   enable row level security;
alter table public.app_audit_log      enable row level security;
