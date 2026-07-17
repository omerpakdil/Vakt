# Vakt Legal Web

Static legal/support site for Vakt.

## Pages

- `/` - legal landing
- `/privacy` - privacy policy
- `/terms` - terms of use
- `/support` - support page

## Local preview

```sh
cd legal-web
python3 -m http.server 4173
```

Open `http://localhost:4173`.

## Vercel

Create a new Vercel project with `legal-web` as the project root.

Recommended settings:

- Framework Preset: `Other`
- Build Command: leave empty or use `npm run build`
- Output Directory: `.`
- Install Command: leave empty

Production URLs:

- `https://vakt-app.vercel.app/privacy`
- `https://vakt-app.vercel.app/terms`
- `https://vakt-app.vercel.app/support`

Current support email: `callousity@gmail.com`.
