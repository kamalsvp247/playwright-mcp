// ─────────────────────────────────────────────────────────────
// Supabase-backed data layer (replaces the local better-sqlite3 file DB).
//
// All app state now lives in the live Supabase Postgres project so it
// persists across serverless invocations. The exported function names are
// intentionally kept identical to the old sqlite API so existing call sites
// (auth routes, session-manager, middleware) keep working unchanged.
// ─────────────────────────────────────────────────────────────

import { createClient } from '@supabase/supabase-js';
import crypto from 'crypto';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_KEY;

let _client = null;

// Returns a shared Supabase client using the service-role key (bypasses RLS).
export function getDb() {
  if (!_client) {
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      throw new Error(
        'Supabase is not configured. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY ' +
          '(see .env.example).'
      );
    }
    _client = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }
  return _client;
}

// ── password hashing (kept identical to the old sqlite implementation) ──

export function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.pbkdf2Sync(password, salt, 10000, 64, 'sha512').toString('hex');
  return `sha512$${salt}$${hash}`;
}

export function verifyPassword(password, hash) {
  const [, salt, storedHash] = hash.split('$');
  if (!salt || !storedHash) return false;
  const testHash = crypto.pbkdf2Sync(password, salt, 10000, 64, 'sha512').toString('hex');
  return storedHash === testHash;
}

// ── sessions (the `db` argument is accepted for API compatibility only) ──

export async function createSession(db, userId, maxAge = 30 * 24 * 60 * 60 * 1000) {
  const sessionId = crypto.randomBytes(32).toString('hex');
  const expiresAt = new Date(Date.now() + maxAge).toISOString();
  const { error } = await getDb()
    .from('app_sessions')
    .insert({ id: sessionId, user_id: userId, expires_at: expiresAt });
  if (error) throw error;
  return sessionId;
}

export async function getSessionUser(db, sessionId) {
  if (!sessionId) return null;
  const { data, error } = await getDb()
    .from('app_sessions')
    .select('user_id, expires_at')
    .eq('id', sessionId)
    .gt('expires_at', new Date().toISOString())
    .maybeSingle();
  if (error || !data) return null;

  const { data: user, error: userErr } = await getDb()
    .from('app_users')
    .select('id, username, role, status')
    .eq('id', data.user_id)
    .eq('status', 'active')
    .maybeSingle();
  if (userErr || !user) return null;
  return user;
}

export async function deleteSession(sessionId) {
  if (!sessionId) return;
  try {
    await getDb().from('app_sessions').delete().eq('id', sessionId);
  } catch {}
}

export async function deleteUserSessions(userId) {
  try {
    await getDb().from('app_sessions').delete().eq('user_id', userId);
  } catch {}
}

export function logAudit(userId, action, details = null, ip = null) {
  try {
    getDb()
      .from('app_audit_log')
      .insert({ user_id: userId ?? null, action, details, ip })
      .then(() => {}, () => {});
  } catch {}
}

// ── one-time admin bootstrap ──

export async function initializeAdmin() {
  const { data: existing } = await getDb()
    .from('app_users')
    .select('id')
    .limit(1);
  if (existing && existing.length > 0) return;

  const passwordHash = hashPassword('admin@12333');
  const { error } = await getDb()
    .from('app_users')
    .insert({ username: 'admin@gmail.com', password_hash: passwordHash, role: 'admin', status: 'active' });
  if (error) {
    console.error('[DB] Failed to initialize admin user:', error.message);
    return;
  }
  console.log('[DB] Initialized admin user: admin@gmail.com');
}

