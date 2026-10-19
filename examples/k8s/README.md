# Kubernetes examples

Choose either `r3e-loadbalancer.yaml` or `r3e-host-network.yaml`. Both examples
read `ADMIN_USERNAME` and `ADMIN_PASSWORD` from the `raceroom-admin-auth` Secret.

1. Build and publish the updated image, then replace
   `REPLACE_WITH_AUTH_ENV_COMMIT` in your manifest with its tag. Older images do
   not support these environment variables.
2. Set `ADMIN_USERNAME` and a nonempty `ADMIN_PASSWORD` in the Secret's
   `stringData` section at the top of your chosen manifest. The password is empty
   by default, so the container will refuse to start until you set it. Keep real
   credentials out of version control.
3. Apply your chosen example; it includes the Secret and the deployment:

   ```sh
   kubectl apply -f examples/k8s/r3e-host-network.yaml
   # Or: kubectl apply -f examples/k8s/r3e-loadbalancer.yaml
   ```

The entrypoint generates a temporary password hash for Nginx. No htpasswd utility
or password-file mount is required. Both credentials must be nonempty; incomplete
credentials prevent startup. Usernames may contain letters, digits, `_`, `.`,
`@`, and `-`. Passwords must not contain line breaks. Restart the deployment after
updating the Secret so the new environment variables take effect:

```sh
kubectl rollout restart deployment/raceroom
```

For local access, forward the admin service and open http://localhost:8088:

```sh
kubectl port-forward service/raceroom-admin 8088:8088
```

With host networking, the Nginx proxy on port 8080 requires Basic Auth for all
dashboard and API requests. The Windows backend on port 8088 remains loopback-only
and must not be exposed separately. For internet access, use an HTTPS reverse
proxy and restrict direct access to port 8080 to that proxy. Basic Auth alone does
not encrypt credentials.
