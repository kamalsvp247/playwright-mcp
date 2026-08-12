import Database from 'better-sqlite3';
import { join } from 'path';

const DB_PATH = join(process.cwd(), 'data', 'app.db');

let db = null;

export function getDb() {
  if (!db) {
    const fs = require('fs');
    const dir = join(process.cwd(), 'data');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    
    db = new Database(DB_PATH);
    db.pragma('journal_mode = WAL');
    db.pragma('foreign_keys = ON');
    
    db.exec(`
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'staff',
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        expires_at TEXT NOT NULL
      );
      
      CREATE TABLE IF NOT EXISTS svp_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        token TEXT,
        token_expiry TEXT,
        storage_json TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(user_id)
      );
      
      CREATE TABLE IF NOT EXISTS audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
        action TEXT NOT NULL,
        details TEXT,
        ip TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      
      CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
      CREATE INDEX IF NOT EXISTS idx_svp_sessions_user_id ON svp_sessions(user_id);
      CREATE INDEX IF NOT EXISTS idx_audit_log_user_id ON audit_log(user_id);
    `);
  }
  return db;
}

export function hashPassword(password) {
  const crypto = require('crypto');
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.pbkdf2Sync(password, salt, 10000, 64, 'sha512').toString('hex');
  return `sha512$${salt}$${hash}`;
}

export function verifyPassword(password, hash) {
  const crypto = require('crypto');
  const [, salt, storedHash] = hash.split('$');
  const testHash = crypto.pbkdf2Sync(password, salt, 10000, 64, 'sha512').toString('hex');
  return storedHash === testHash;
}

export function createSession(db, userId, maxAge = 30 * 24 * 60 * 60 * 1000) {
  const sessionId = require('crypto').randomBytes(32).toString('hex');
  const expiresAt = new Date(Date.now() + maxAge).toISOString();
  db.prepare('INSERT INTO sessions (id, user_id, expires_at) VALUES (?, ?, ?)').run(sessionId, userId, expiresAt);
  return sessionId;
}

export function getSessionUser(db, sessionId) {
  if (!sessionId) return null;
  const session = db.prepare(`
    SELECT u.id, u.username, u.role, u.status 
    FROM sessions s 
    JOIN users u ON s.user_id = u.id 
    WHERE s.id = ? AND s.expires_at > datetime('now') AND u.status = 'active'
  `).get(sessionId);
  return session || null;
}

export function deleteSession(sessionId) {
  if (!sessionId) return;
  try {
    getDb().prepare('DELETE FROM sessions WHERE id = ?').run(sessionId);
  } catch {}
}

export function deleteUserSessions(userId) {
  try {
    getDb().prepare('DELETE FROM sessions WHERE user_id = ?').run(userId);
  } catch {}
}

export function logAudit(userId, action, details = null, ip = null) {
  try {
    getDb().prepare('INSERT INTO audit_log (user_id, action, details, ip) VALUES (?, ?, ?, ?)').run(userId, action, details, ip);
  } catch {}
}

export function initializeAdmin() {
  const db = getDb();
  const count = db.prepare('SELECT COUNT(*) as cnt FROM users').get().cnt;
  if (count === 0) {
    const passwordHash = hashPassword('admin@12333');
    db.prepare("INSERT INTO users (username, password_hash, role, status) VALUES (?, ?, 'admin', 'active')").run('admin@gmail.com', passwordHash);
    console.log('[DB] Initialized admin user: admin@gmail.com');
  }
}
