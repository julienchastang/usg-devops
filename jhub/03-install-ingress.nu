# TODO
# - [ ] Move current logic to a main function, I guess

source ./env.nu

print "[ INFO ] Adding traefik repo"

helm repo add traefik https://traefik.github.io/charts;
helm repo update

print "[ INFO ] Installing traefik"

(
helm upgrade --install traefik traefik/traefik
  --namespace ingress-traefik --create-namespace
  --set 'api.dashboard=false'
  --set 'providers.kubernetesCRD.enabled=false'
  --set 'logs.access.enabled=true'
  --set 'nodeSelector.capi\.stackhpc\.com/node-group=default-worker'
  --wait
)
| complete
| if $in.exit_code != 0 {
  print "[ ERROR ] See stderr below..."
  print $in
  exit 1
}

let ingress_ip = kubectl get svc -n ingress-traefik
| detect columns
| get 0.EXTERNAL-IP

print $"[ INFO ] Load balancer created with IP ($ingress_ip)"
