const PROJECT_ID = 'connectsportpro';
const PROJECT_NUMBER = '36251906942';
const POOL_ID = 'vercel';
const PROVIDER_ID = 'vercel';
const SERVICE_ACCOUNT = 'csp-translation@connectsportpro.iam.gserviceaccount.com';
const CLOUD_SCOPE = 'https://www.googleapis.com/auth/cloud-platform';
const SUPABASE_URL = 'https://lcmoykaqvvfybtobhtqg.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_h3_yK3K_GUahLdz13dDWDg_PzxGE6xR';
const MAX_ITEMS = 60;
const MAX_ITEM_CODE_POINTS = 2000;
const MAX_REQUEST_CODE_POINTS = 28000;
const REQUEST_TIMEOUT_MS = 12000;

const ALLOWED_LANGS = new Set(['sk', 'cs', 'en', 'de', 'pl', 'ru']);

function sendJson(res, status, body) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(body));
}

function getOidcToken(req) {
  const header = req.headers['x-vercel-oidc-token'];
  if (Array.isArray(header)) return header[0] || '';
  return header || process.env.VERCEL_OIDC_TOKEN || '';
}

function getBearerToken(req) {
  const raw = Array.isArray(req.headers.authorization)
    ? req.headers.authorization[0]
    : req.headers.authorization;
  const match = /^Bearer\s+(.+)$/i.exec(String(raw || ''));
  return match ? match[1] : '';
}

async function fetchWithTimeout(url, options = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function requireSupabaseUser(accessToken) {
  if (!accessToken) return null;
  const response = await fetchWithTimeout(`${SUPABASE_URL}/auth/v1/user`, {
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${accessToken}`,
    },
  });
  if (!response.ok) return null;
  const user = await response.json().catch(() => null);
  return user && user.id ? user : null;
}

async function consumeTranslationQuota(accessToken, characterCount) {
  const response = await fetchWithTimeout(
    `${SUPABASE_URL}/rest/v1/rpc/consume_translation_quota`,
    {
      method: 'POST',
      headers: {
        apikey: SUPABASE_PUBLISHABLE_KEY,
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ p_character_count: characterCount }),
    }
  );
  if (!response.ok) return false;
  return (await response.json().catch(() => false)) === true;
}

async function getGoogleAccessToken(vercelOidcToken) {
  const audience =
    `//iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/` +
    `workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}`;

  const stsBody = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:token-exchange',
    audience,
    scope: CLOUD_SCOPE,
    requested_token_type: 'urn:ietf:params:oauth:token-type:access_token',
    subject_token: vercelOidcToken,
    subject_token_type: 'urn:ietf:params:oauth:token-type:jwt',
  });

  const stsResponse = await fetchWithTimeout('https://sts.googleapis.com/v1/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: stsBody,
  });

  const sts = await stsResponse.json();
  if (!stsResponse.ok || !sts.access_token) {
    throw new Error(
      `Google STS failed: ${sts.error_description || sts.error || stsResponse.status}`
    );
  }

  const impersonationUrl =
    `https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/` +
    `${encodeURIComponent(SERVICE_ACCOUNT)}:generateAccessToken`;

  const impersonationResponse = await fetchWithTimeout(impersonationUrl, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${sts.access_token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      scope: [CLOUD_SCOPE],
      lifetime: '3600s',
    }),
  });

  const impersonated = await impersonationResponse.json();
  if (!impersonationResponse.ok || !impersonated.accessToken) {
    throw new Error(
      `Service account impersonation failed: ` +
      `${impersonated.error?.message || impersonationResponse.status}`
    );
  }

  return impersonated.accessToken;
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return sendJson(res, 405, { error: 'Method not allowed' });
  }

  try {
    const accessToken = getBearerToken(req);
    const user = await requireSupabaseUser(accessToken);
    if (!user) {
      return sendJson(res, 401, { error: 'Prihlásenie je potrebné.' });
    }

    const oidcToken = getOidcToken(req);
    if (!oidcToken) {
      return sendJson(res, 503, { error: 'Preklad momentálne nie je dostupný.' });
    }

    let body;
    try {
      body =
        typeof req.body === 'string'
          ? JSON.parse(req.body || '{}')
          : (req.body || {});
    } catch {
      return sendJson(res, 400, { error: 'Neplatný JSON.' });
    }

    const texts = Array.isArray(body.texts) ? body.texts : [];
    const target = String(body.target || '').toLowerCase();
    const source = String(body.source || 'sk').toLowerCase();

    if (!ALLOWED_LANGS.has(target) || !ALLOWED_LANGS.has(source)) {
      return sendJson(res, 400, { error: 'Unsupported language' });
    }

    if (!texts.length || texts.length > MAX_ITEMS) {
      return sendJson(res, 400, { error: `Povolených je 1 až ${MAX_ITEMS} textov.` });
    }

    const normalized = texts.map(v => String(v ?? '').trim());
    const codePointLengths = normalized.map(v => Array.from(v).length);
    const totalCodePoints = codePointLengths.reduce((sum, length) => sum + length, 0);
    if (
      normalized.some((v, index) => !v || codePointLengths[index] > MAX_ITEM_CODE_POINTS) ||
      totalCodePoints > MAX_REQUEST_CODE_POINTS
    ) {
      return sendJson(res, 400, { error: 'Text je príliš dlhý.' });
    }

    if (target === source) {
      return sendJson(res, 200, { translations: normalized });
    }

    const quotaAllowed = await consumeTranslationQuota(accessToken, totalCodePoints);
    if (!quotaAllowed) {
      return sendJson(res, 429, { error: 'Denný limit prekladov bol vyčerpaný.' });
    }

    const googleAccessToken = await getGoogleAccessToken(oidcToken);

    const translationUrl =
      `https://translation.googleapis.com/v3/projects/${PROJECT_ID}` +
      `/locations/global:translateText`;

    const response = await fetchWithTimeout(translationUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${googleAccessToken}`,
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: JSON.stringify({
        contents: normalized,
        sourceLanguageCode: source,
        targetLanguageCode: target,
        mimeType: 'text/plain',
      }),
    });

    const result = await response.json();
    if (!response.ok) {
      throw new Error(
        `Cloud Translation failed: ${result.error?.message || response.status}`
      );
    }

    const translations = (result.translations || []).map(
      item => item.translatedText || ''
    );

    return sendJson(res, 200, { translations });
  } catch (error) {
    console.error('[api/translate]', error);
    return sendJson(res, 500, { error: 'Preklad sa nepodarilo dokončiť.' });
  }
}
