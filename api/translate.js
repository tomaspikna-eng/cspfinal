const PROJECT_ID = 'connectsportpro';
const PROJECT_NUMBER = '36251906942';
const POOL_ID = 'vercel';
const PROVIDER_ID = 'vercel';
const SERVICE_ACCOUNT = 'csp-translation@connectsportpro.iam.gserviceaccount.com';
const CLOUD_SCOPE = 'https://www.googleapis.com/auth/cloud-platform';

const ALLOWED_LANGS = new Set(['sk', 'cs', 'en', 'de', 'pl']);

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

  const stsResponse = await fetch('https://sts.googleapis.com/v1/token', {
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

  const impersonationResponse = await fetch(impersonationUrl, {
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
    const oidcToken = getOidcToken(req);
    if (!oidcToken) {
      return sendJson(res, 500, { error: 'Vercel OIDC token is not available' });
    }

    const body =
      typeof req.body === 'string'
        ? JSON.parse(req.body || '{}')
        : (req.body || {});

    const texts = Array.isArray(body.texts) ? body.texts : [];
    const target = String(body.target || '').toLowerCase();
    const source = String(body.source || 'sk').toLowerCase();

    if (!ALLOWED_LANGS.has(target) || !ALLOWED_LANGS.has(source)) {
      return sendJson(res, 400, { error: 'Unsupported language' });
    }

    if (!texts.length || texts.length > 100) {
      return sendJson(res, 400, { error: 'texts must contain 1 to 100 items' });
    }

    const normalized = texts.map(v => String(v ?? '').trim());
    if (normalized.some(v => !v || v.length > 5000)) {
      return sendJson(res, 400, { error: 'Invalid text payload' });
    }

    if (target === source) {
      return sendJson(res, 200, { translations: normalized });
    }

    const accessToken = await getGoogleAccessToken(oidcToken);

    const translationUrl =
      `https://translation.googleapis.com/v3/projects/${PROJECT_ID}` +
      `/locations/global:translateText`;

    const response = await fetch(translationUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
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
    return sendJson(res, 500, {
      error: error instanceof Error ? error.message : 'Translation failed',
    });
  }
}
