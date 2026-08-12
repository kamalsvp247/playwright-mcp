import { NextResponse } from 'next/server';
import { getDb, verifyPassword, createSession, getSessionUser, logAudit } from '@/lib/db';

export async function POST(request) {
  try {
    const body = await request.json();
    const { username, password } = body;
    
    if (!username || !password) {
      return NextResponse.json({ success: false, error: 'Username and password are required' }, { status: 400 });
    }
    
    const db = getDb();
    const user = db.prepare('SELECT * FROM users WHERE username = ? AND status = ?').get(username, 'active');
    
    if (!user || !verifyPassword(password, user.password_hash)) {
      logAudit(null, 'login_failed', { username }, request.headers.get('x-forwarded-for') || request.headers.get('x-real-ip'));
      return NextResponse.json({ success: false, error: 'Invalid username or password' }, { status: 401 });
    }
    
    const sessionId = createSession(db, user.id);
    logAudit(user.id, 'login_success');
    
    const response = NextResponse.json({
      success: true,
      data: {
        id: user.id,
        username: user.username,
        role: user.role,
        sessionId
      }
    });
    
    response.cookies.set('session', sessionId, {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax',
      maxAge: 30 * 24 * 60 * 60,
      path: '/'
    });
    
    return response;
  } catch (e) {
    console.error('Login error:', e);
    return NextResponse.json({ success: false, error: 'Login failed' }, { status: 500 });
  }
}

export async function DELETE(request) {
  try {
    const sessionId = request.cookies.get('session')?.value;
    const user = sessionId ? getSessionUser(getDb(), sessionId) : null;
    
    if (user) {
      logAudit(user.id, 'logout');
    }
    
    const response = NextResponse.json({ success: true });
    response.cookies.set('session', '', {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax',
      maxAge: 0,
      path: '/'
    });
    
    return response;
  } catch (e) {
    console.error('Logout error:', e);
    return NextResponse.json({ success: false, error: 'Logout failed' }, { status: 500 });
  }
}
