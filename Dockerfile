FROM caddy:2-alpine

WORKDIR /app
COPY . /app

EXPOSE 8080

CMD ["caddy", "run", "--config", "/app/Caddyfile", "--adapter", "caddyfile"]
