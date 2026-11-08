FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY --chown=node:node tools/railway-dispatch/dispatch.js ./dispatch.js
USER node
CMD ["node", "dispatch.js"]
