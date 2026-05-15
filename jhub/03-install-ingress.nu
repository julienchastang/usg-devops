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

let timeout = 10min
let start = date now
mut ready = false
mut ingress_ip = ""

print $"[ INFO ] Waiting for load balancer IP with timeout ($timeout)"

while not $ready and ((date now) - $start) < $timeout {
  let ingress_result = kubectl get svc -n ingress-traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' | complete

  if $ingress_result.exit_code == 0 {
    $ingress_ip = ($ingress_result.stdout | str trim)
    $ready = (not ($ingress_ip | is-empty)) and $ingress_ip != "<pending>"
  } else {
    print "[ WARNING ] Failed to check load balancer IP"
  }

  if not $ready {
    print $"[ INFO ] Time elapsed ((date now) - $start)"
    sleep 30sec
  }
}

if not $ready {
  print $"[ ERROR ] Failed to get load balancer IP in ($timeout)"
  exit 1
}

print $"[ INFO ] Load balancer created with IP ($ingress_ip)"
