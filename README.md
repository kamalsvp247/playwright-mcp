This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://github.com/vercel/next.js/tree/canary/packages/create-next-app).

## Getting Started

First, run the development server:

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
# or
bun dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

You can start editing the page by modifying `app/page.js`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.
## Deployed Preview

This app is deployed at: https://playwright-mcp-chi.vercel.app/

### Endform setup

1. Authenticate with Endform:
```bash
npx endform@latest login
```

2. Run tests against the deployed preview:

Windows:
```bash
set "VERCEL_URL=playwright-mcp-chi.vercel.app" && npx endform@latest test
```

macOS/Linux:
```bash
VERCEL_URL=playwright-mcp-chi.vercel.app npx endform@latest test
```

The Playwright config now reads `process.env.VERCEL_URL` and falls back to `process.env.BASE_URL` or `https://playwright-mcp-chi.vercel.app/`.

> Note: `endform` CLI does not support native Windows `win32` in some environments, so use WSL, Linux, or macOS if needed.

## SVP Automated Login

`POST /api/auth/login` now supports fully automated login. It launches a browser, fills in the SVP login form, and captures the Bearer token automatically — no manual VNC interaction is required when the credentials are available.

Credentials are resolved in this order: **request body → environment variables**.

Supported env vars (set them in Railway/Vercel):

| Env var | Purpose |
|---------|---------|
| `SVP_EMAIL` | SVP account email (or phone number for phone-based flows) |
| `SVP_PASSWORD` | SVP account password |
| `SVP_OTP` | One-time verification code (only needed if the account/flow requires an OTP step) |
| `SVP_RECAPTCHA_TOKEN` | Pre-solved reCAPTCHA token from a solver service (only needed if the `skip_recaptcha_step` feature flag is **not** enabled for the SVP tenant) |

Optional JSON body (overrides env vars):

```bash
curl -X POST https://<your-host>/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"secret","otp":"123456","recaptchaToken":"..."}'
```

With no body, the endpoint falls back to `SVP_EMAIL`/`SVP_PASSWORD` (etc.) from the environment. The request still blocks for up to **5 minutes** while the browser completes the flow, so always call it with a client timeout ≥ 320s (e.g. `Invoke-WebRequest -TimeoutSec 320`).

What the automation does internally:

1. Opens the SVP login page (headed browser, visible via noVNC on port 6080).
2. Fills the email/phone field and clicks **Continue / Sign in**.
3. Fills the password field and submits.
4. If a reCAPTCHA widget appears and `SVP_RECAPTCHA_TOKEN` is set, injects the token; otherwise it logs a warning and keeps waiting.
5. If an OTP/verification-code step appears and `SVP_OTP` is set, fills and submits it.
6. Polls for the Bearer token (network interceptor + localStorage) and persists it to `.svp-token.json`, exactly like the manual flow.

If any step is blocked by a CAPTCHA or an OTP the bot doesn't have, the browser stays open and you can still finish the login manually in the VNC viewer (`http://<host>:6080/vnc.html`) — the token-capture loop keeps running for the full 5 minutes.

> SVP branding is masked in the VNC browser ("Exam Center Manager"), so it is not visually identifiable as SVP.
