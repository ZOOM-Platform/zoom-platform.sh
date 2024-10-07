# zoom-platform.sh website
Deno server only required if you want to be able to serve specific versions of the script.

## Deploying
1. Clone this repo
2. `./dist.sh`
3. `./start-www.sh` (saves latest stable script to www/dist)
4. `deno task start` (optional)
5. Serve `www/dist`

We can't use GitHub/CF Pages cause they force SSL. Server is running Nginx with a simple config:
```nginx
server {
        listen 80;
        listen [::]:80;

        root PATH_TO_PUBLIC_DIR;
        index index.html;
        server_name zoom-platform.sh;

        location / {
                try_files $uri $uri/ @proxy;
        }

        location @proxy {
                proxy_pass http://0.0.0.0:23412;
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

~~all this cause i don't want an `-L` in the command~~