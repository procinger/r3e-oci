# Docker Compose

1. Copy `.env.example` to `.env` and set your username and password. Keep passwords
   in single quotes if they contain `$` to prevent Compose interpolation.

   ```sh
   cp examples/docker/.env.example examples/docker/.env
   ```

2. Start the service from the repository root:

   ```sh
   docker compose --env-file examples/docker/.env \
     -f examples/docker/compose.yaml up -d
   ```

Open http://localhost:8088 on the Docker host and sign in. Compose rejects missing
or empty credentials.
