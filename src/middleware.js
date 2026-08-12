import { NextResponse } from 'next/server';
import { getDb, getSessionUser, logAudit } from '@/lib/db';

export function withAuth(handler) {
  return async (request, ...args) => {
    const sessionId = request.cookies.get('session')?.value;
    const user = sessionId ? getSessionUser(getDb(), sessionId) : null;
    
    if (!user) {
      return NextResponse.json({ success: false, error: 'Unauthorized' }, { status: 401 });
    }
    
    request.user = user;
    return handler(request, ...args);
  };
}

export function withAdmin(handler) {
  return withAuth(async (request, ...args) => {
    if (request.user.role !== 'admin') {
      return NextResponse.json({ success: false, error: 'Forbidden' }, { status: 403 });
    }
    return handler(request, ...args);
  });
}

export function withAnyRole(allowedRoles) {
  return withAuth(async (request, ...args) => {
    if (!allowedRoles.includes(request.user.role)) {
      return NextResponse.json({ success: false, error: 'Forbidden' }, { status: 403 });
    }
    return handler(request, ...args);
  });
}

export function logRequest(action) {
  return (request, ...args) => {
    const result = handler(request, ...args);
    const userId = request.user?.id || null;
    const ip = request.headers.get('x-forwarded-for') || request.headers.get('x-real-ip') || null;
    logAudit(userId, action, { method: request.method, url: request.url }, ip);
    return result;
  };
}
