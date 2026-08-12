import { NextResponse } from 'next/server';
import { getDb, hashPassword, verifyPassword, createSession, logAudit } from '@/lib/db';

export async function POST(request) {
  try {
    const body = await request.json();
    const { username, password, role = 'staff' } = body;
    
    if (!username || !password) {
      return NextResponse.json({ success: false, error: 'Username and password are required' }, { status: 400 });
    }
    
    if (username.length < 3 || password.length < 6) {
      return NextResponse.json({ success: false, error: 'Username must be at least 3 characters, password at least 6' }, { status: 400 });
    }
    
    const allowedRoles = ['admin', 'staff'];
    const userRole = allowedRoles.includes(role) ? role : 'staff';
    
    const db = getDb();
    const passwordHash = hashPassword(password);
    
    try {
      const result = db.prepare(
        'INSERT INTO users (username, password_hash, role, status) VALUES (?, ?, ?, ?)'
      ).run(username, passwordHash, userRole, 'active');
      
      const user = db.prepare('SELECT id, username, role, status, created_at FROM users WHERE id = ?').get(result.lastInsertRowid);
      
      logAudit(request.user?.id, 'user_created', { targetUserId: user.id, username: user.username });
      
      return NextResponse.json({ success: true, data: user });
    } catch (e) {
      if (e.message.includes('UNIQUE constraint failed')) {
        return NextResponse.json({ success: false, error: 'Username already exists' }, { status: 409 });
      }
      throw e;
    }
  } catch (e) {
    console.error('Create user error:', e);
    return NextResponse.json({ success: false, error: 'Failed to create user' }, { status: 500 });
  }
}
