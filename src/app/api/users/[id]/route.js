import { NextResponse } from 'next/server';
import { getDb, verifyPassword, hashPassword, logAudit } from '@/lib/db';
import { sessionManager } from '@/lib/session-manager';

export async function GET(request, { params }) {
  try {
    const { id } = params;
    const db = getDb();
    const user = db.prepare('SELECT id, username, role, status, created_at FROM users WHERE id = ?').get(id);
    
    if (!user) {
      return NextResponse.json({ success: false, error: 'User not found' }, { status: 404 });
    }
    
    return NextResponse.json({ success: true, data: user });
  } catch (e) {
    console.error('Get user error:', e);
    return NextResponse.json({ success: false, error: 'Failed to get user' }, { status: 500 });
  }
}

export async function PATCH(request, { params }) {
  try {
    const { id } = params;
    const body = await request.json();
    const { username, password, role, status } = body;
    
    const db = getDb();
    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(id);
    
    if (!user) {
      return NextResponse.json({ success: false, error: 'User not found' }, { status: 404 });
    }
    
    const updates = [];
    const values = [];
    
    if (username && username !== user.username) {
      updates.push('username = ?');
      values.push(username);
    }
    
    if (password) {
      updates.push('password_hash = ?');
      values.push(hashPassword(password));
    }
    
    if (role && ['admin', 'staff'].includes(role)) {
      updates.push('role = ?');
      values.push(role);
    }
    
    if (status && ['active', 'inactive'].includes(status)) {
      updates.push('status = ?');
      values.push(status);
    }
    
    if (updates.length > 0) {
      updates.push("updated_at = datetime('now')");
      values.push(id);
      
      db.prepare(`UPDATE users SET ${updates.join(', ')} WHERE id = ?`).run(...values);
      
      if (status === 'inactive') {
        await sessionManager.invalidateUser(parseInt(id));
      }
      
      logAudit(request.user?.id, 'user_updated', { targetUserId: id, changes: body });
    }
    
    const updated = db.prepare('SELECT id, username, role, status, created_at FROM users WHERE id = ?').get(id);
    return NextResponse.json({ success: true, data: updated });
  } catch (e) {
    console.error('Update user error:', e);
    return NextResponse.json({ success: false, error: 'Failed to update user' }, { status: 500 });
  }
}

export async function DELETE(request, { params }) {
  try {
    const { id } = params;
    const db = getDb();
    
    const user = db.prepare('SELECT id, username FROM users WHERE id = ?').get(id);
    if (!user) {
      return NextResponse.json({ success: false, error: 'User not found' }, { status: 404 });
    }
    
    await sessionManager.invalidateUser(parseInt(id));
    db.prepare('DELETE FROM users WHERE id = ?').run(id);
    
    logAudit(request.user?.id, 'user_deleted', { targetUserId: id, username: user.username });
    
    return NextResponse.json({ success: true });
  } catch (e) {
    console.error('Delete user error:', e);
    return NextResponse.json({ success: false, error: 'Failed to delete user' }, { status: 500 });
  }
}
