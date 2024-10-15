# syntax=docker/dockerfile:1
FROM node:20-alpine AS base

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

RUN apk update && apk add --no-cache git go gcc musl-dev supervisor
COPY supervisord.conf /etc/supervisord.conf

# Set GOBIN to install Go binaries into /usr/local/bin
ENV GOBIN=/usr/local/bin

# Install xcaddy
RUN go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

# Build Caddy with the cache plugin
RUN xcaddy build \
    --with github.com/caddyserver/cache-handler \
    --with github.com/caddyserver/caddy/v2/modules/caddyhttp/reverseproxy

# Move Caddy binary to /usr/bin
RUN mv ./caddy /usr/bin/caddy

# Continue with the rest of your Dockerfile
WORKDIR /app
COPY package.json .
COPY pnpm-lock.yaml .

FROM base AS prod-deps
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --prod --frozen-lockfile

FROM base AS build
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
COPY tsconfig.json .
COPY src ./src
RUN pnpm build

FROM base AS main

# Setup user
RUN addgroup -S nsite && adduser -S nsite -G nsite
RUN chown -R nsite:nsite /app

# Setup Caddy
COPY Caddyfile /etc/caddy/Caddyfile

# setup nsite
COPY --from=prod-deps /app/node_modules /app/node_modules
COPY --from=build ./app/build ./build

COPY ./public ./public
COPY tor-and-i2p.pac proxy.pac

EXPOSE 80 443 3000
ENV NSITE_PORT="3000"
ENV ENABLE_SCREENSHOTS="false"
ENV DOMAIN="yourdomain.com" 
ENV EMAIL="your-email@example.com" 

COPY docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
