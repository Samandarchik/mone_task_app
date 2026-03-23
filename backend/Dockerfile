# Build stage
FROM golang:1.24 AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=1 go build -o server .

# Runtime stage
FROM debian:bookworm

WORKDIR /app

# Install runtime dependencies including FFmpeg
RUN apt-get update && apt-get install -y \
    sqlite3 \
    ca-certificates \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /app/db /app/videos

# Copy binary from builder
COPY --from=builder /app/server /app/server

# Expose port
EXPOSE 8000

# Run the application
CMD ["/app/server"]
