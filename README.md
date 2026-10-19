# Closer Estimates

Estimate app for solo tradespeople. Installable web app (PWA) with accounts, automatic backup, customer approval links, AI support assistant and Stripe subscriptions, powered by Supabase.

- `index.html` – landing page (returning users and email sign-in links skip straight to the app)
- `app.html` – the app
- `approve.html` – the page customers see when you text them an approval link
- `support.html`, `privacy.html` – help (with AI assistant) and privacy policy
- `img/` – screenshots used on the landing page
- `setup.sql` – database setup, run in Supabase > SQL Editor
- `manifest.webmanifest`, `sw.js`, `icons/` – install and offline support

Not uploaded to GitHub (they live in Supabase Edge Functions): `support-chat.ts`, `stripe-webhook.ts`.

Bump `VERSION` in `sw.js` whenever you upload changed files.
