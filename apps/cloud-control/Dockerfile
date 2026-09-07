FROM node:22.20.0-bookworm-slim@sha256:b21fe589dfbe5cc39365d0544b9be3f1f33f55f3c86c87a76ff65a02f8f5848e AS build

WORKDIR /workspace

COPY package.json package-lock.json tsconfig.base.json ./
COPY apps/cloud-control/package.json apps/cloud-control/package.json
RUN npm ci

COPY apps/cloud-control/tsconfig.json apps/cloud-control/tsconfig.json
COPY apps/cloud-control/src apps/cloud-control/src
RUN npm run build --workspace @cloud/cloud-control

FROM node:22.20.0-bookworm-slim@sha256:b21fe589dfbe5cc39365d0544b9be3f1f33f55f3c86c87a76ff65a02f8f5848e

ENV NODE_ENV=production
WORKDIR /app

COPY --from=build --chown=node:node /workspace/apps/cloud-control/dist/src ./dist/src

USER node
EXPOSE 3000
CMD ["node", "dist/src/index.js"]
