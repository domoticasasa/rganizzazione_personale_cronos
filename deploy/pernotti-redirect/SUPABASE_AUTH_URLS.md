# Auth URL — dominio Gestopro

**Site URL:** `https://gestopro360.it`

Redirect URLs (uno per riga in Dashboard → Authentication → URL Configuration):

```
https://gestopro360.it
https://gestopro360.it/**
https://gestopro360.it/login
https://www.gestopro360.it
https://www.gestopro360.it/**
https://www.gestopro360.it/login
https://gestopro.pages.dev
https://gestopro.pages.dev/**
https://gestopro.pages.dev/login
https://pernotti.pages.dev
https://pernotti.pages.dev/**
https://pernotti.pages.dev/login
myapp://auth-callback
http://localhost:*/**
http://127.0.0.1:*/**
```

Allineato in [`supabase/config.toml`](../../supabase/config.toml). Push remoto:

```bash
supabase config push
```
