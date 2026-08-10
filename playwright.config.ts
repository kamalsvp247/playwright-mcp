import { defineConfig, devices } from 'playwright/test';
export default defineConfig({
  testDir: './tests', // Update to your test directory
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: process.env.VERCEL_URL
      ? `https://${process.env.VERCEL_URL}`
      : process.env.BASE_URL || 'https://playwright-mcp-chi.vercel.app/',
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },
  ],
  webServer: {
    // Configure if you need to run a dev server
    // command: 'npm run dev',
    // url: 'http://localhost:3000',
    // reuseExistingServer: !process.env.CI,
  },
})
