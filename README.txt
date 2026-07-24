CSP translation fix

1. Copy:
   api/translate.js
   assets/csp-i18n.js

2. Add this line before </body> on pages that contain the language selector:
   <script src="/assets/csp-i18n.js"></script>

3. Vercel project must have Secure Backend Access / OIDC enabled.

4. Google setup used by the backend:
   Project ID: connectsportpro
   Project number: 36251906942
   Workload Identity Pool: vercel
   Provider: vercel
   Service account: csp-translation@connectsportpro.iam.gserviceaccount.com

5. Supported UI languages:
   SK -> sk
   CZ -> cs
   EN -> en
   DE -> de
   PL -> pl

No Google API key or service-account private key is stored in the frontend.
