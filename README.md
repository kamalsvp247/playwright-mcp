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

With no body, the endpoint falls back to `SVP_EMAIL`/`SVP_PASSWORD` (etc.) from the environment.

The endpoint is **non-blocking**: it starts the browser login in the background and returns immediately — `HTTP 202` with `{ "success": true, "status": "started" }` (or `200` with `"Already logged in."` if a token is already cached). No client-side timeout is ever needed, so you will never hit an HTTP `499` from a long-held request again. Poll `GET /api/auth/status` to follow progress — `data.login.status` moves through `running` → `success` / `error` / `timeout`, and `data.loggedIn` flips to `true` the moment the Bearer token is captured.

```bash
# 1. Kick off login — returns in < 1s
curl -s -X POST https://<your-host>/api/auth/login
# → {"success":true,"status":"started",...}

# 2. Poll until it finishes (here: every 4s)
while true; do
  curl -s https://<your-host>/api/auth/status
  echo
  sleep 4
done
```

PowerShell (use a Chrome UA so SVP does not flag the request; no `-TimeoutSec` needed):

```powershell
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$session.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36"

$r = Invoke-RestMethod -Uri "https://<your-host>/api/auth/login" -Method Post -WebSession $session
$r | ConvertTo-Json   # {"success":true,"status":"started",...}

do {
  Start-Sleep -Seconds 4
  $s = Invoke-RestMethod -Uri "https://<your-host>/api/auth/status" -WebSession $session
  $st = $s.data.login.status
} until ($s.data.loggedIn -or $st -in @("success","error","timeout"))

if ($s.data.loggedIn -or $st -eq "success") { "LOGIN OK" } else { $s.data.login.message }
```

> The kick-off + poll design assumes a long-running server host (the Railway Docker runtime) so the background Playwright flow keeps running after the request returns.

What the automation does internally:

1. Opens the SVP login page (headed browser, visible via noVNC on port 6080).
2. Fills the email/phone field and clicks **Continue / Sign in**.
3. Fills the password field and submits.
4. If a reCAPTCHA widget appears and `SVP_RECAPTCHA_TOKEN` is set, injects the token; otherwise it logs a warning and keeps waiting.
5. If an OTP/verification-code step appears and `SVP_OTP` is set, fills and submits it.
6. Polls for the Bearer token (network interceptor + localStorage) and persists it to `.svp-token.json`, exactly like the manual flow.

If any step is blocked by a CAPTCHA or an OTP the bot doesn't have, the browser stays open and you can still finish the login manually in the VNC viewer (`http://<host>:6080/vnc.html`) — the token-capture loop keeps running for the full 5 minutes.

> SVP branding is masked in the VNC browser ("Exam Center Manager"), so it is not visually identifiable as SVP.
