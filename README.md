# RaceRoom Dedicated Server

This repository provides a Linux/amd64 container image for the Windows RaceRoom
Dedicated Server (Steam app **354060**). It combines SteamCMD, Proton's Wine
runtime, Microsoft .NET Framework 4.8, and Xvfb to run the server without a desktop.
A built-in Nginx proxy exposes the web administration interface.

## Build the image and run locally

```sh
docker build --platform linux/amd64 -t raceroom:latest .
docker volume create raceroom-data
docker run --rm -t --name raceroom \
  -e ADMIN_USERNAME=admin -e ADMIN_PASSWORD=admin \
  -p 127.0.0.1:8088:8080 \
  -p 60000:60000/udp -p 60001:60001/tcp -p 60002:60002/udp \
  -v raceroom-data:/data raceroom:latest
```

Once startup is complete, open http://localhost:8088 on the Docker host to configure
and start a race server. The example exposes the first instance's game ports;
additional instances require additional port mappings.

## Deployment examples

The [examples](examples/) directory contains configurations for Docker and Kubernetes:

- [Docker Compose](examples/docker/compose.yaml)
- [Kubernetes with a LoadBalancer](examples/k8s/r3e-loadbalancer.yaml)
- [Kubernetes with host networking](examples/k8s/r3e-host-network.yaml)


Basic Auth is enabled when both `ADMIN_USERNAME` and `ADMIN_PASSWORD` are set.
If neither is set, authentication is disabled; incomplete or empty credentials
prevent startup.
