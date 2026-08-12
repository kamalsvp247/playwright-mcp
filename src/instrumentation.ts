// Next.js instrumentation: runs once when the server boots. Used to seed the
// initial admin account in the live Supabase project if none exists yet.
export async function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    try {
      const { initializeAdmin } = await import('@/lib/db');
      await initializeAdmin();
    } catch (err) {
      // Supabase may not be configured in every environment (e.g. build step).
      // Fail soft so the build/other commands are not blocked.
      console.warn('[instrumentation] Admin bootstrap skipped:', err.message);
    }
  }
}
