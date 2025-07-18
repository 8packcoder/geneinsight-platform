# Optimized Railway Deployment - GeneInsight Platform with LangChain
FROM node:18-alpine AS frontend-builder

# Build frontend
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build

# Python ML Service with LangChain
FROM python:3.9-slim AS ml-service

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy ML service requirements
COPY ml_service/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Install LangChain dependencies
RUN pip install --no-cache-dir transformers torch langchain-community

# Copy ML service code
COPY ml_service/ ./

# Create model cache directory
RUN mkdir -p /tmp/transformers_cache
ENV TRANSFORMERS_CACHE=/tmp/transformers_cache

# Expose port
EXPOSE 5000

# Start ML service
CMD ["python", "app.py"]

# Final stage - combine frontend and ML service
FROM python:3.9-slim

# Install Node.js for frontend
RUN apt-get update && apt-get install -y \
    curl \
    gcc \
    g++ \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy built frontend
COPY --from=frontend-builder /app/.next ./.next
COPY --from=frontend-builder /app/public ./public
COPY --from=frontend-builder /app/package*.json ./
COPY --from=frontend-builder /app/node_modules ./node_modules

# Copy ML service
COPY ml_service/ ./ml_service/

# Install Python dependencies
COPY ml_service/requirements.txt ./ml_service/
RUN pip install --no-cache-dir -r ml_service/requirements.txt
RUN pip install --no-cache-dir transformers torch langchain-community

# Create model cache directory
RUN mkdir -p /tmp/transformers_cache
ENV TRANSFORMERS_CACHE=/tmp/transformers_cache

# Environment variables
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000

# Create startup script
RUN echo '#!/bin/bash\n\
# Start ML service in background\n\
cd /app/ml_service && python app.py &\n\
\n\
# Wait for ML service to start\n\
sleep 10\n\
\n\
# Start frontend\n\
cd /app && npm start\n\
' > /app/start.sh && chmod +x /app/start.sh

# Expose ports
EXPOSE 3000 5000

# Start both services
CMD ["/app/start.sh"]
