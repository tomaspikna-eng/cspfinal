CSP ROLE ROUTING FIX — complete GH structure

Files included:
- login/index.html
- profil/index.html
- profil-ul/index.html

Routing:
- player + free -> /profil/
- player + pro -> /profil/
- club -> /profil-ul/
- organization -> /profil-ul/
- admin -> /profil-ul/

Guards:
- /profil/ redirects club, organization and admin to /profil-ul/
- /profil-ul/ redirects ordinary player accounts to /profil/
- password login resolves the destination from public.profiles
- Google OAuth returns through /profil/, whose guard resolves the final role destination
