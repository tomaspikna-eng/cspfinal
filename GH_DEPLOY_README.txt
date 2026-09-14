CSP GitHub deployment package — 2026-09-14

Base: main @ 1761fdea44a79c692e20eb5f5b8985d23e3a2438
Contains P0–P4 fixes plus repository cleanup required by quality checks.

Manual GitHub deployment:
1. Replace the repository contents with the CONTENTS of this folder (not the outer ZIP folder itself).
2. Preserve the same relative paths, including .github/workflows/quality.yml and supabase/migrations/.
3. Commit to main.
4. GitHub Actions workflow "CSP quality" should run npm test.
5. Vercel will deploy main automatically.

Important:
- Supabase P0–P4 database changes are already live in production; the SQL files in supabase/migrations record that state in GitHub.
- Do not re-run the migrations manually against production just because they are in this ZIP.
- Root legacy SQL files were moved to docs/legacy-sql so they are not served as public site files.
