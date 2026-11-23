# DECIDE MVP

A Korean choice-voting community built with Next.js, Supabase and PostgreSQL.

## Included
- New / Hot feed and category filtering
- Two or three image-based options
- Guest voting through Supabase Anonymous Auth
- One vote per authenticated identity per post (database unique constraint)
- Vote distribution and participant count
- Automatic next-post progression with a manual next button
- Skip already-voted posts (requires guest identity persistence)
- Member post creation and public image storage
- SQL schema, RLS policies and vote RPC

## Local setup
1. Install Node.js 20.9+.
2. Create a Supabase project.
3. In Supabase Authentication > Providers, enable **Anonymous Sign-Ins**.
4. Configure a permanent member sign-in provider (Google OAuth is used by the app's intended member flow; enable Google and configure its redirect URLs in Supabase).
5. Run `supabase/schema.sql` in Supabase SQL Editor.
6. Copy `.env.example` to `.env.local` and set the Supabase project URL and publishable/anon key.
7. Run:
   ```bash
   npm install
   npm run dev
   ```
8. Open http://localhost:3000.

## Deploy to Vercel
1. Push this project to a private GitHub repository.
2. Import the repository into Vercel.
3. Add `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` in Vercel project environment variables.
4. Deploy. Add the production domain to Supabase Authentication URL Configuration and the Google OAuth redirect allowlist.

## Important production hardening before public launch
- Add CAPTCHA / rate limiting to anonymous voting and sign-up endpoints.
- Add image moderation, abuse reporting, terms, privacy policy and deletion workflow.
- Configure email/Google identity linking so guest vote history can be retained after account creation.
- Add server-side feed pagination and efficient per-user vote exclusion for large traffic.
- Add stronger view deduplication (the sample UI increments once per post per browser session; production analytics should deduplicate by user/session and time window).
- Add moderation/admin role and audit log; never expose Supabase service-role keys in the browser.
- Validate uploaded image dimensions and file size on the server/storage policy.
- The included demo posts are local preview data, not production database records.

## Current limitations
The UI falls back to sample content when Supabase environment variables are missing. The live data path and database schema are included, but a live server cannot be activated until a Supabase project and Vercel deployment are connected. OAuth provider credentials and domain ownership must be supplied by the project owner.
