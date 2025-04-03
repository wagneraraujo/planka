# Build stage for server dependencies
FROM node:20-alpine AS server-deps

# Add build essentials
RUN apk add --no-cache build-base python3 git

# Set working directory
WORKDIR /app

# Copy package files
COPY server/package*.json ./

# Install dependencies with pnpm
RUN npm install -g pnpm@latest \
    && pnpm install --prod --frozen-lockfile

# Build stage for client
FROM node:20-alpine AS client-builder

WORKDIR /app

# Copy client source
COPY client/package*.json ./
COPY client .

# Install dependencies and build
RUN npm install -g pnpm@latest \
    && pnpm install --frozen-lockfile \
    && DISABLE_ESLINT_PLUGIN=true pnpm run build

# Production stage
FROM node:20-alpine AS production

# Add necessary runtime dependencies
RUN apk add --no-cache bash curl

# Create non-root user
RUN addgroup -S planka && adduser -S planka -G planka

# Set working directory
WORKDIR /app

# Copy application files
COPY --chown=planka:planka server .
COPY --chown=planka:planka start.sh healthcheck.js ./
RUN chmod +x start.sh

# Copy built assets from previous stages
COPY --from=server-deps --chown=planka:planka /app/node_modules ./node_modules
COPY --from=client-builder --chown=planka:planka /app/build ./public
COPY --from=client-builder --chown=planka:planka /app/build/index.html ./views/index.ejs

# Create necessary directories with proper permissions
RUN mkdir -p \
    /app/public/user-avatars \
    /app/public/project-background-images \
    /app/private/attachments \
    && chown -R planka:planka \
    /app/public \
    /app/private

# Setup volumes
VOLUME ["/app/public/user-avatars", "/app/public/project-background-images", "/app/private/attachments"]

# Switch to non-root user
USER planka

# Expose port
EXPOSE 1337

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:1337/health || exit 1

# Set environment variables
ENV NODE_ENV=production \
    NODE_OPTIONS="--max-old-space-size=4096"

# Start the application
CMD ["./start.sh"]
