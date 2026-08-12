import { getDb, deleteUserSessions } from './db.js';

function safeParse(json) {
  try {
    return JSON.parse(json);
  } catch {
    return null;
  }
}

// ── app_svp_sessions persistence (Postgres via Supabase) ──
// Mirrors the old local-sqlite helpers but targets the live project's
// app_svp_sessions table.

const SVP_LOGIN_URL = 'https://svp-international.pacc.sa/auth/login?role=labor';
const SVP_BASE = 'https://svp-international.pacc.sa';

class UserSession {
  constructor(userId) {
    this.userId = userId;
    this.token = null;
    this.tokenExpiry = null;
    this.storageState = null;
    this.browserContext = null;
    this.browser = null;
    this.loginPromise = null;
    this.lastUsed = Date.now();
  }

  isExpired() {
    return this.tokenExpiry && new Date() >= this.tokenExpiry;
  }

  touch() {
    this.lastUsed = Date.now();
  }
}

class SessionManager {
  constructor() {
    this.sessions = new Map();
    this.mutex = new Map();
  }

  async getOrCreateUserSession(userId) {
    let userSession = this.sessions.get(userId);
    if (!userSession || userSession.isExpired()) {
      userSession = new UserSession(userId);
      this.sessions.set(userId, userSession);
      await this.loadSessionFromDb(userSession);
    }
    userSession.touch();
    return userSession;
  }

  async loadSessionFromDb(userSession) {
    try {
      const { data: row } = await getDb()
        .from('app_svp_sessions')
        .select('token, token_expiry, storage_json')
        .eq('user_id', userSession.userId)
        .maybeSingle();
      if (row) {
        userSession.token = row.token;
        userSession.tokenExpiry = row.token_expiry ? new Date(row.token_expiry) : null;
        userSession.storageState = row.storage_json ? safeParse(row.storage_json) : null;
        
        if (userSession.tokenExpiry && new Date() >= userSession.tokenExpiry) {
          userSession.token = null;
          userSession.tokenExpiry = null;
          userSession.storageState = null;
        }
      }
    } catch (e) {
      console.error(`[SessionManager] Failed to load session for user ${userSession.userId}:`, e.message);
    }
  }

  async saveSessionToDb(userSession) {
    try {
      const { error } = await getDb()
        .from('app_svp_sessions')
        .upsert({
          user_id: userSession.userId,
          token: userSession.token,
          token_expiry: userSession.tokenExpiry ? userSession.tokenExpiry.toISOString() : null,
          storage_json: userSession.storageState ? JSON.stringify(userSession.storageState) : null,
          updated_at: new Date().toISOString()
        }, { onConflict: 'user_id' });
      if (error) throw error;
    } catch (e) {
      console.error(`[SessionManager] Failed to save session for user ${userSession.userId}:`, e.message);
    }
  }

  async clearSession(userId) {
    const userSession = this.sessions.get(userId);
    if (userSession) {
      await this.closeBrowser(userSession);
      userSession.token = null;
      userSession.tokenExpiry = null;
      userSession.storageState = null;
    }
    
    try {
      await getDb().from('app_svp_sessions').delete().eq('user_id', userId);
      await deleteUserSessions(userId);
    } catch (e) {
      console.error(`[SessionManager] Failed to clear session for user ${userId}:`, e.message);
    }
  }

  async withSession(userId, fn) {
    const userSession = await this.getOrCreateUserSession(userId);
    const mutexKey = `user:${userId}`;
    
    if (!this.mutex.has(mutexKey)) {
      this.mutex.set(mutexKey, []);
    }
    const queue = this.mutex.get(mutexKey);
    
    const release = () => {
      const idx = queue.indexOf(resolve);
      if (idx >= 0) queue.splice(idx, 1);
    };
    
    const result = await new Promise((resolve) => {
      queue.push(resolve);
      if (queue.length === 1) {
        resolve();
      }
    });
    
    try {
      return await fn(userSession);
    } finally {
      release();
      if (queue.length > 0) {
        queue.shift()();
      }
    }
  }

  async closeBrowser(userSession) {
    if (userSession.browserContext) {
      try { await userSession.browserContext.close(); } catch {}
      userSession.browserContext = null;
    }
    if (userSession.browser) {
      try { await userSession.browser.close(); } catch {}
      userSession.browser = null;
    }
  }

  async getBrowserContext(userSession) {
    if (userSession.browserContext && userSession.browser && userSession.browser.isConnected()) {
      return userSession.browserContext;
    }
    
    await this.closeBrowser(userSession);
    
    const { chromium } = await import('playwright');
    const browser = await chromium.launch({
      headless: process.env.HEADLESS !== 'false',
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-blink-features=AutomationControlled',
        '--window-size=480,650',
        '--window-position=400,100'
      ]
    });
    
    const context = await browser.newContext({
      viewport: { width: 480, height: 650 },
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
    });
    
    userSession.browser = browser;
    userSession.browserContext = context;
    
    if (userSession.storageState) {
      try {
        await context.addCookies(userSession.storageState.cookies || []);
      } catch {}
    }
    
    return context;
  }

  async updateToken(userSession, token, expiryDate) {
    userSession.token = token;
    userSession.tokenExpiry = expiryDate;
    await this.saveSessionToDb(userSession);
  }

  async updateStorageState(userSession, storageState) {
    userSession.storageState = storageState;
    await this.saveSessionToDb(userSession);
  }

  async invalidateUser(userId) {
    await this.clearSession(userId);
  }
}

export const sessionManager = new SessionManager();
