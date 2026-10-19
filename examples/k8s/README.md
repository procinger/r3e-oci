# Kubernetes examples

Choose either `r3e-loadbalancer.yaml` or `r3e-host-network.yaml`. Both examples
read `ADMIN_USERNAME` and `ADMIN_PASSWORD` from the `raceroom-admin-auth` Secret.

1. Set `ADMIN_USERNAME` and a nonempty `ADMIN_PASSWORD` in the Secret's
   `stringData` section at the top of your chosen manifest. The password is empty
   by default, so the container will refuse to start until you set it. Keep real
   credentials out of version control.
2. Apply your chosen example; it includes the Secret and the deployment:

   ```sh
   kubectl apply -f examples/k8s/r3e-host-network.yaml
   # Or: 
   kubectl apply -f examples/k8s/r3e-loadbalancer.yaml
   ```

3. Restart the deployment after updating the Secret so the new environment variables take effect:

```sh
kubectl rollout restart deployment/raceroom
```

For local access, forward the admin service and open http://localhost:8088:

```sh
kubectl port-forward service/raceroom-admin 8088:8088
```

