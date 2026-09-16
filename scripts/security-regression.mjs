import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const errors = [];
const warnings = [];
const fail = message => errors.push(message);
const warn = message => warnings.push(message);

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    if (['.git', 'node_modules'].includes(entry.name)) return [];
    const full = path.join(dir, entry.name);
    return entry.isDirectory() ? walk(full) : [full];
  });
}

const files = walk(root);
const textFiles = files.filter(file => /\.(?:html|js|mjs|json|md|txt|yml|yaml)$/i.test(file));
const publicCodeFiles = files.filter(file => /\.(?:html|js|mjs|json)$/i.test(file));

for (const file of files.filter(file => /\.env(?:\.|$)/i.test(path.basename(file)))) {
  fail(`Tracked environment file: ${path.relative(root, file)}`);
}

for (const file of publicCodeFiles) {
  const text = fs.readFileSync(file, 'utf8');
  if (/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(text)) {
    fail(`Private key material in ${path.relative(root, file)}`);
  }
  if (/SUPABASE_SERVICE_ROLE_KEY|GOOGLE_APPLICATION_CREDENTIALS\s*=/.test(text)) {
    fail(`Server secret identifier in browser/static code: ${path.relative(root, file)}`);
  }

  for (const match of text.matchAll(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g)) {
    try {
      const payload = JSON.parse(Buffer.from(match[0].split('.')[1], 'base64url').toString('utf8'));
      if (payload?.role === 'service_role') {
        fail(`Supabase service_role JWT in ${path.relative(root, file)}`);
      }
    } catch {
      // Not every JWT-looking string is decodable JSON; ignore false positives.
    }
  }
}

const authPath = path.join(root, 'assets/csp-auth.js');
if (!fs.existsSync(authPath)) fail('Missing assets/csp-auth.js');
else {
  const auth = fs.readFileSync(authPath, 'utf8');
  if (!auth.includes("rpc('get_my_profile_private')")) fail('Private profile RPC is not used by csp-auth.js');
  if (!auth.includes('PUBLIC_PROFILE_COLUMNS')) fail('Profile wildcard compatibility guard is missing');
}

const migrationName = '20260916081500_security_audit_hardening.sql';
const migrationPath = path.join(root, 'supabase/migrations', migrationName);
if (!fs.existsSync(migrationPath)) fail(`Missing security migration ${migrationName}`);
else {
  const sql = fs.readFileSync(migrationPath, 'utf8');
  for (const needle of [
    "a.attname <> 'public_token'",
    "a.attname <> 'device_token'",
    'new := old;',
    'get_my_profile_private',
    "new.role = 'admin'::public.profile_role",
    "where id = 'avatars'",
    "where id = 'article-covers'"
  ]) {
    if (!sql.includes(needle)) fail(`Security migration is missing guard: ${needle}`);
  }
}

const vercelPath = path.join(root, 'vercel.json');
if (!fs.existsSync(vercelPath)) fail('Missing vercel.json');
else {
  const vercel = fs.readFileSync(vercelPath, 'utf8');
  for (const header of ['Content-Security-Policy', 'X-Content-Type-Options', 'Referrer-Policy', 'Permissions-Policy']) {
    if (!vercel.includes(header)) fail(`Missing security header: ${header}`);
  }
  if (vercel.includes("default-src *")) fail('CSP contains wildcard default-src');
  if (vercel.includes("object-src *")) fail('CSP contains wildcard object-src');
  if (vercel.includes("'unsafe-eval'")) fail("CSP enables 'unsafe-eval'");
  if (vercel.includes("'unsafe-inline'")) warn("Legacy CSP still permits 'unsafe-inline'; do not add new inline scripts while migration to external scripts is pending.");
}

for (const file of files.filter(file => file.endsWith('.js') || file.endsWith('.mjs'))) {
  const run = spawnSync(process.execPath, ['--check', file], { encoding: 'utf8' });
  if (run.status !== 0) fail(`JavaScript syntax: ${path.relative(root, file)} — ${run.stderr.trim()}`);
}

for (const file of files.filter(file => file.endsWith('.html'))) {
  const html = fs.readFileSync(file, 'utf8');
  for (const match of html.matchAll(/<script[^>]+src=["']https:\/\/(?:cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com)\/[^"']+["'][^>]*>/gi)) {
    if (!/\bintegrity=["']sha384-[^"']+["']/i.test(match[0])) {
      fail(`CDN script missing SHA-384 SRI: ${path.relative(root, file)}`);
    }
    if (!/\bcrossorigin=["']anonymous["']/i.test(match[0])) {
      fail(`CDN script missing crossorigin=anonymous: ${path.relative(root, file)}`);
    }
  }

  if (/\.select\s*\(\s*["'`][^"'`]*(?:public_token|device_token)[^"'`]*["'`]\s*\)/i.test(html)) {
    fail(`Browser code directly selects a capability token: ${path.relative(root, file)}`);
  }
}

for (const warning of [...new Set(warnings)]) console.warn(`WARN: ${warning}`);
if (errors.length) {
  for (const error of errors) console.error(`ERROR: ${error}`);
  console.error(`\nSecurity regression audit failed: ${errors.length} issue(s).`);
  process.exit(1);
}

console.log(`OK: security regression audit passed across ${textFiles.length} text files.`);
