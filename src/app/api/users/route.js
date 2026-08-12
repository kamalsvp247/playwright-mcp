import { NextResponse } from 'next/server';
import { getDb, hashPassword, logAudit } from '@/lib/db';

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
    
    const passwordHash = hashPassword(password);
    
    const { data: user, error } = await getDb()
      .from('app_users')
      .insert({ username, password_hash: passwordHash, role: userRole, status: 'active' })
      .select('id, username, role, status, created_at')
      .single();
    
    if (error) {
      if (error.code === '23505' || (error.message || '').includes('unique') || (error.message || '').includes('duplicate')) {
        return NextResponse.json({ success: false, error: 'Username already exists' }, { status: 409 });
      }
      console.error('Create user error:', error.message);
      return NextResponse.json({ success: false, error: 'Failed to create user' }, { status: 500 });
    }
    
    logAudit(request.user?.id, 'user_created', { targetUserId: user.id, username: user.username });
    
    return NextResponse.json({ success: true, data: user });
  } catch (e) {
    console.error('Create user error:', e);
    return NextResponse.json({ success: false, error: 'Failed to create user' }, { status: 500 });
  }
}
