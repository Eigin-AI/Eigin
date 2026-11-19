# Build the adapter-node bundle with `just test contributor` before packaging.
FROM node:24-bookworm-slim
WORKDIR /app
COPY package.json package-lock.json ./
COPY design/web/package.json design/web/
COPY src/eigin_sdk/web/package.json src/eigin_sdk/web/
COPY src/eigin_web/package.json src/eigin_web/
COPY src/eigin_website/package.json src/eigin_website/
COPY src/eigin_contributors/package.json src/eigin_contributors/
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund --workspace @eigin/contributors && npm cache clean --force
WORKDIR /app/src/eigin_contributors
COPY src/eigin_contributors/build ./build
COPY src/eigin_contributors/migrations ./migrations
COPY src/eigin_contributors/scripts/migrate.ts src/eigin_contributors/scripts/prune-oauth-attempts.ts ./scripts/
COPY src/eigin_contributors/src/lib/server/database.ts ./src/lib/server/
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8080
USER node
EXPOSE 8080
CMD ["node", "build/index.js"]
