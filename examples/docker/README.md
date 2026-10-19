# Docker Compose

1. Replace `REPLACE_WITH_AUTH_ENV_COMMIT` in `compose.yaml` with a published image
   tag that supports `ADMIN_USERNAME` and `ADMIN_PASSWORD`.
2. Copy `.env.example` to `.env` and set your username and password. Keep passwords
   in single quotes if they contain `$` to prevent Compose interpolation.

   ```sh
   cp examples/docker/.env.example examples/docker/.env
   ```

3. Start the service from the repository root:

   ```sh
   docker compose --env-file examples/docker/.env \
     -f examples/docker/compose.yaml up -d
   ```

Open http://localhost:8088 on the Docker host and sign in. Compose rejects missing
or empty credentials. The `.env` file is ignored by Git and should remain private.
Restart the container with `up -d` after changing credentials. The data volume is
preserved when recreating the container.

The admin port is bound to loopback. For remote access, use HTTPS or a private
tunnel; Basic Auth does not encrypt credentials.
