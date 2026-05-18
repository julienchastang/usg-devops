# TODO
# - [ ] Move current logic to a "create" command
# - [ ] Have a "delete" command
# - [ ] Have a "show" command
# - [ ] Change file name from 04-create-arecord.nu to 04-arecord.nu

# This script must be run after a successful `install_ingress.nu`, as we must
# have a load balancer IP to create an A-record for to begin with :)

source ./env.nu

print "[ INFO ] Creating A-record"

let zone = $env.jupyterhub.zone
let cluster_name = $env.jupyterhub.cluster.name

# Trim the trailing "." from the zone
let dns = $"($cluster_name).($zone | str trim -r -c ".")"

let ip = kubectl get svc -n ingress-traefik
| detect columns
| get 0.EXTERNAL-IP

(openstack recordset create $zone $cluster_name
  --type A
  --record $ip
  --ttl 3600
)

# TODO
# Ingress nginx should be running but tell us that nothing is currently being
# served. Look at this later to figure out an appropriate "success" condition.
# http get $dns
