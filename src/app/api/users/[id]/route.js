import { NextResponse } from 'next/server';
import { getDb, hashPassword, logAudit } from '@/lib/db';
import { sessionManager } from '@/lib/session-manager';

export async function GET(request, { params }) {
  try {
    const { id } = params;
    const { data: user, error } = await getDb()
      .from('app_users')
      .select('id, username, role, status, created_at')
      .eq('id', id)
      .maybeSingle();
    
    if (error || !user) {
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
    
    const { data: user, error: lookupErr } = await getDb()
      .from('app_users')
      .select('id, username')
      .eq('id', id)
      .maybeSingle();
    
    if (lookupErr || !user) {
      return NextResponse.json({ success: false, error: 'User not found' }, { status: 404 });
    }
    
    const updates = {};
    
    if (username && username !== user.username) {
      updates.username = username;
    }
    if (password) {
      updates.password_hash = hashPassword(password);
    }
    if (role && ['admin', 'staff'].includes(role)) {
      updates.role = role;
    }
    if (status && ['active', 'inactive'].includes(status)) {
      updates.status = status;
    }
    
    if (Object.keys(updates).length > 0) {
      updates.updated_at = new Date().toISOString();
      
      const { error } = await getDb().from('app_users').update(updates).eq('id', id);
      if (error) throw error;
      
      if (status === 'inactive') {
        await sessionManager.invalidateUser(parseInt(id));
      }
      
      logAudit(request.user?.id, 'user_updated', { targetUserId: id, changes: body });
    }
    
    const { data: updated } = await getDb()
      .from('app_users')
      .select('id, username, role, status, created_at')
      .eq('id', id)
      .maybeSingle();
    return NextResponse.json({ success: true, data: updated });
  } catch (e) {
    console.error('Update user error:', e);
    return NextResponse.json({ success: false, error: 'Failed to update user' }, { status: 500 });
  }
}

export async function DELETE(request, { params }) {
  try {
    const { id } = params;
    const numericId = parseInt(id);
    
    const { data: user, error: lookupErr } = await getDb()
      .from('app_users')
      .select('id, username')
      .eq('id', numericId)
      .maybeSingle();
    if (lookupErr || !user) {
      return NextResponse.json({ success: false, error: 'User not found' }, { status: 404 });
    }
    
    await sessionManager.invalidateUser(numericId);
    const { error } = await getDb().from('app_users').delete().eq('id', numericId);
    if (error) throw error;
    
    logAudit(request.user?.id, 'user_deleted', { targetUserId: numericId, username: user.username });
    
    return NextResponse.json({ success: true });
  } catch (e) {
    console.error('Delete user error:', e);
    return NextResponse.json({ success: false, error: 'Failed to delete user' }, { status: 500 });
  }
}
