import { NextResponse } from 'next/server';
import { login } from '@/lib/svp-playwright';

export const dynamic = 'force-dynamic';

export async function POST(request) {
  let body = {};
  try {
    body = await request.json();
  } catch {
    // No JSON body (e.g. curl without -H/-d) — fall back to env credentials.
  }
  const { email, password, otp, recaptchaToken } = body || {};
  try {
    const result = await login({ email, password, otp, recaptchaToken });
    return NextResponse.json(result);
  } catch (error) {
    console.error('[auth/login] Error:', error.message);
    return NextResponse.json(
      { success: false, error: error.message },
      { status: 500 }
    );
  }
}
