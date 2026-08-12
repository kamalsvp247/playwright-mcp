import { NextResponse } from 'next/server';
import { getDb, getSessionUser } from '@/lib/db';

export async function GET(request) {
  try {
    const sessionId = request.cookies.get('session')?.value;
    const user = sessionId ? await getSessionUser(getDb(), sessionId) : null;
    
    if (!user) {
      return NextResponse.json({ success: false, error: 'Unauthorized' }, { status: 401 });
    }
    
    return NextResponse.json({
      success: true,
      data: { id: user.id, username: user.username, role: user.role }
    });
  } catch (e) {
    console.error('[auth/me] Error:', e);
    return NextResponse.json({ success: false, error: 'Failed to get user' }, { status: 500 });
  }
}
