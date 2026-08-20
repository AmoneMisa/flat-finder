FROM node:22-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:22-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=4000

COPY --from=deps /app/node_modules ./node_modules
COPY package.json package-lock.json ./
COPY src ./src

EXPOSE 4000
# bootstrap.js is the entrypoint, not server.js: it patches
# express.application.listen to install the /api/translation routes before
# the app binds, then imports server.js. Running server.js directly starts a
# server that 404s every translation request.
CMD ["node", "src/bootstrap.js"]
