# Usage

## Packages

Replacing your current base image with the Docker Alpine Linux image usually requires updating the package names to the corresponding ones in the [Alpine Linux package index](https://pkgs.alpinelinux.org).
We use the `apk` command to manage packages.
It works similarly to `apt` and `yum`.

For example, installing the `nginx` package would be done by running `apk add --no-cache nginx`.
The `--no-cache` argument prevents `apk` from caching the package index - something that would normally take up precious space, as well as go stale quickly.

### Example

This is an example of a complete Dockerfile for `nginx`:

```dockerfile
FROM broadsage/alpine

RUN apk --no-cache add nginx

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### Virtual Packages

Another great `apk` feature is the concept of user-defined virtual packages.
Packages added under a virtual package name can later be removed as one group.
An example use-case would be removing all build dependencies at once, as in this example:

```dockerfile
FROM broadsage/alpine

WORKDIR /myapp
COPY . /myapp

RUN apk add --no-cache python py-pip openssl ca-certificates
RUN apk add --no-cache --virtual build-dependencies python-dev build-base wget \
  && pip install -r requirements.txt \
  && python setup.py install \
  && apk del build-dependencies

CMD ["myapp", "start"]
```

### Further Details

For further details on `apk` and how it's used, you can look at [Alpine's User Documentation](https://docs.alpinelinux.org/user-handbook/0.1a/Working/apk.html) for it.

## Advanced Package Management

### Searching for Packages

```bash
# Search for a package
apk search <package-name>

# Search with wildcards
apk search 'postgres*'

# Show package description
apk search -v -d <package-name>
```

### Package Information

```bash
# Show package details
apk info <package-name>

# List package contents
apk info -L <package-name>

# Show package size
apk info -s <package-name>

# List all installed packages
apk info
```

### Upgrading Packages

```bash
# Update package index
apk update

# Upgrade all installed packages
apk upgrade

# Upgrade specific package
apk upgrade <package-name>

# Upgrade with automatic yes
apk upgrade --no-cache
```

## Production-Ready Examples

### Cron Jobs

```dockerfile
FROM broadsage/alpine:3.22

# Install cron and required packages
RUN apk add --no-cache dcron

# Copy crontab file
COPY crontab /etc/crontabs/root

# Make sure cron log directory exists
RUN mkdir -p /var/log/cron

# Start cron in foreground
CMD ["crond", "-f", "-l", "2"]
```

Example crontab:

```cron
# Run every hour
0 * * * * /scripts/backup.sh >> /var/log/cron/backup.log 2>&1

# Run daily at 2 AM
0 2 * * * /scripts/cleanup.sh >> /var/log/cron/cleanup.log 2>&1
```

### Database Client Tools

```dockerfile
FROM broadsage/alpine:3.22

# Install PostgreSQL client
RUN apk add --no-cache postgresql-client

# Or MySQL client
RUN apk add --no-cache mysql-client

# Or Redis client
RUN apk add --no-cache redis

# Example usage
CMD ["psql", "--version"]
```

### SSL/TLS Applications

```dockerfile
FROM broadsage/alpine:3.22

# Install CA certificates for HTTPS
RUN apk add --no-cache ca-certificates

# Update certificates
RUN update-ca-certificates

# Your application
COPY app /app
CMD ["/app"]
```

### Init Systems (supervisord)

```dockerfile
FROM broadsage/alpine:3.22

# Install supervisord
RUN apk add --no-cache supervisor

# Copy supervisor config
COPY supervisord.conf /etc/supervisord.conf

# Create log directory
RUN mkdir -p /var/log/supervisor

EXPOSE 80 443

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
```

Example supervisord.conf:

```ini
[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/nginx-stdout.log
stderr_logfile=/var/log/supervisor/nginx-stderr.log

[program:app]
command=/app/server
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/app-stdout.log
stderr_logfile=/var/log/supervisor/app-stderr.log
```

## Security Hardening

### Non-Root User

```dockerfile
FROM broadsage/alpine:3.22

# Create non-root user
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

# Install application
COPY app /app
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

CMD ["/app"]
```

### Minimal Attack Surface

```dockerfile
FROM broadsage/alpine:3.22

# Install only required packages
RUN apk add --no-cache \
    ca-certificates \
    tzdata

# Remove package manager (advanced hardening)
# RUN apk del apk-tools

# Remove shell (if not needed)
# RUN rm /bin/sh

COPY app /app
CMD ["/app"]
```

### Read-Only Root Filesystem

```dockerfile
FROM broadsage/alpine:3.22

# Create writable directories
RUN mkdir -p /tmp /var/run /var/log && \
    chmod 1777 /tmp

# Application
COPY app /app

# Run with read-only root filesystem
# docker run --read-only --tmpfs /tmp --tmpfs /var/run image:tag
CMD ["/app"]
```

## Performance Optimization

### Layer Caching

```dockerfile
# ✅ Good: Dependencies change less frequently
FROM broadsage/alpine:3.22
COPY requirements.txt .
RUN apk add --no-cache python3 py3-pip && \
    pip3 install -r requirements.txt
COPY . .

# ❌ Bad: Every code change invalidates all layers
FROM broadsage/alpine:3.22
COPY . .
RUN apk add --no-cache python3 py3-pip && \
    pip3 install -r requirements.txt
```

### Multi-Stage Build Optimization

```dockerfile
# Stage 1: Build dependencies
FROM broadsage/alpine:3.22 AS base
RUN apk add --no-cache ca-certificates tzdata

# Stage 2: Build application
FROM base AS builder
RUN apk add --no-cache build-base
COPY . /src
RUN cd /src && make build

# Stage 3: Runtime
FROM base
COPY --from=builder /src/output /app
CMD ["/app"]
```

### Minimize Image Size

```dockerfile
FROM broadsage/alpine:3.22

# Combine RUN commands
RUN apk add --no-cache python3 py3-pip && \
    pip3 install --no-cache-dir requests && \
    rm -rf /root/.cache

# Use --no-cache-dir with pip
RUN pip3 install --no-cache-dir package-name

# Remove unnecessary files
RUN apk add --no-cache build-base && \
    # ... build steps ... && \
    apk del build-base && \
    rm -rf /tmp/* /var/cache/apk/*
```

## Testing and Debugging

### Interactive Debugging

```bash
# Run container with shell
docker run -it broadsage/alpine:3.22 /bin/sh

# Exec into running container
docker exec -it <container-id> /bin/sh

# Check installed packages
docker run broadsage/alpine:3.22 apk info

# Verify package installation
docker run broadsage/alpine:3.22 which nginx
```

### Build Troubleshooting

```bash
# Build with no cache
docker build --no-cache -t myapp .

# Build with progress output
docker build --progress=plain -t myapp .

# Inspect image layers
docker history myapp

# Check image size
docker images myapp
```

### Common Commands Cheat Sheet

```bash
# Package Management
apk add --no-cache <package>     # Install package
apk del <package>                # Remove package
apk search <package>             # Search for package
apk info                         # List installed packages
apk update                       # Update package index
apk upgrade                      # Upgrade all packages

# System Info
cat /etc/alpine-release          # Alpine version
cat /etc/os-release              # OS information
uname -a                         # Kernel information

# File Operations
find / -name <filename>          # Find file
ls -lh /path                     # List files with sizes
du -sh /path                     # Directory size
df -h                            # Disk space
```
