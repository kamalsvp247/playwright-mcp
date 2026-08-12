import { NextResponse } from 'next/server';
import { getDb, getSessionUser } from '@/lib/db';
import { isLoggedIn, getToken, getLoginStatus } from '@/lib/svp-playwright';

export const dynamic = 'force-dynamic';

export async function GET(request) {
  try {
    const sessionId = request.cookies.get('session')?.value;
    const user = sessionId ? getSessionUser(getDb(), sessionId) : null;
    
    const loggedIn = isLoggedIn();
    const token = getToken();

    let tokenInfo = null;
    if (token) {
      try {
        const payload = JSON.parse(Buffer.from(token.split('.')[1], 'base64').toString());
        tokenInfo = {
          expires: payload.exp ? new Date(payload.exp * 1000).toISOString() : null,
          issuer: payload.iss || null,
          subject: payload.sub || null
        };
      } catch {}
    }

    return NextResponse.json({
      success: true,
      data: {
        user: user ? { id: user.id, username: user.username, role: user.role } : null,
        loggedIn,
        tokenInfo,
        login: getLoginStatus()
      }
    });
  } catch (error) {
    console.error('[auth/status] Error:', error.message);
    return NextResponse.json(
      { success: false, error: error.message },
      { status: 500 }
    );
  }
}
