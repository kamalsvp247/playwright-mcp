import { NextResponse } from 'next/server';
import { startLogin } from '@/lib/svp-playwright';

export const dynamic = 'force-dynamic';

// Non-blocking browser-assisted SVP login. The caller polls /api/auth/status
// while the managed browser opens the official SVP sign-in page.
export async function POST(request) {
  let body = {};
  try {
    body = await request.json();
  } catch {
    // Empty request: use the configured/manual browser-assisted flow.
  }

  const { email, password, otp, recaptchaToken } = body || {};
  try {
    const result = startLogin({ email, password, otp, recaptchaToken });
    const status = (result.status === 'started' || result.status === 'running') ? 202 : 200;
    return NextResponse.json(result, { status });
  } catch (error) {
    console.error('[auth/svp-login] Error:', error.message);
    return NextResponse.json(
      { success: false, error: error.message },
      { status: 500 }
    );
  }
}
