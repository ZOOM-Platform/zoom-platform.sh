# zoom-platform.sh website

## Building
1. Clone this repo
2. `cd www && build.sh`
3. Serve `www/out/`

We can't use GitHub/CF Pages cause they force SSL. Server is running Nginx with a simple config:
```nginx
server {
        listen 80;
        listen [::]:80;

        root PATH_TO_OUT_DIR;
        index index.html;
        server_name zoom-platform.sh;

        location / {
                try_files $uri $uri/ $uri.html /index.html;
        }
}
```

Cloudflare is set up to:
- Rewrite to `/zoom-platform.sh` if a non-browser User-Agent.
  ```
  (not starts_with(http.user_agent, "Mozilla/5.0"))
  ```
- Only redirect browsers to HTTPS.
  ```
  (not ssl and starts_with(http.user_agent, "Mozilla/5.0"))
  ```
- Automatic HTTPS Rewrites, integrity checks, challenges, etc are all disabled for non-browser UAs.

~~all this cause i don't an `-L` in the command~~