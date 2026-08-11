import { NextResponse } from 'next/server';
import { startLogin } from '@/lib/svp-playwright';

export const dynamic = 'force-dynamic';

// Non-blocking login: kicks off the Playwright flow in the background and
// returns immediately (202 + status:"started"). Clients poll
// GET /api/auth/status (data.login) until it finishes. This avoids long-held
// HTTP requests that clients/proxies drop with HTTP 499 after ~45-60s.
export async function POST(request) {
  let body = {};
  try {
    body = await request.json();
  } catch {
    // No JSON body (e.g. curl without -H/-d) — fall back to env credentials.
  }
  const { email, password, otp, recaptchaToken } = body || {};
  try {
    const result = startLogin({ email, password, otp, recaptchaToken });
    const status = (result.status === 'started' || result.status === 'running') ? 202 : 200;
    return NextResponse.json(result, { status });
  } catch (error) {
    console.error('[auth/login] Error:', error.message);
    return NextResponse.json(
      { success: false, error: error.message },
      { status: 500 }
    );
  }
}
