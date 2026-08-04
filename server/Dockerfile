# Crownspire Nakama image with TypeScript runtime — LOCAL DEVELOPMENT ONLY
FROM node:20-alpine AS node-builder
WORKDIR /backend
COPY package.json package-lock.json* ./
RUN npm install
COPY tsconfig.json ./
COPY src ./src
RUN npx tsc

FROM registry.heroiclabs.com/heroiclabs/nakama:3.40.0
COPY --from=node-builder /backend/build/index.js /nakama/data/modules/build/index.js
COPY local.yml /nakama/data/local.yml
