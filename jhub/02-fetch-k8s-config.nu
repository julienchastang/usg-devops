# TODO
# - [ ] Move this to a main function, although this isn't strictly necessary
# - [ ] If I really wanted to, make a "backup" sub-command

source ./env.nu

let cluster_name = $env.jupyterhub.cluster.name

let timeout = 10min
let start = date now
mut ready = false
mut api_address = ""

print $"[ INFO ] Waiting for Kubernetes API healthz with timeout ($timeout)"

while not $ready and ((date now) - $start) < $timeout {
  let api_address_result = openstack coe cluster show $cluster_name -c api_address -f value | complete

  if $api_address_result.exit_code == 0 {
    $api_address = ($api_address_result.stdout | str trim)

    if not ($api_address | is-empty) {
      let healthz_result = curl -ksS --max-time 10 $"($api_address)/healthz" | complete

      if $healthz_result.exit_code == 0 {
        $ready = ($healthz_result.stdout | str trim) == "ok"
      }
    }
  } else {
    print "[ WARNING ] Failed to check cluster API address"
  }

  if not $ready {
    print $"[ INFO ] Time elapsed ((date now) - $start)"
    sleep 30sec
  }
}

if not $ready {
  print $"[ ERROR ] Kubernetes API healthz did not return ok in ($timeout)"
  exit 1
}

print "[ INFO ] Fetching kubectl config file"

cd /tmp/
openstack coe cluster config $cluster_name --force
| complete

# Make sure the file created correctly
if not ("/tmp/config" | path exists) {
  print "[ ERROR ] Failed to create kube config file"
  exit 1
}

chmod 600 config
mkdir ~/.kube

if ("~/.kube/config" | path exists) {
  let backup = $"~/.kube/config-(date now | format date "%F")" | path expand
  print $"[ WARNING ] ~/.kube/config already exists. Creating a backup at ($backup)"
  mv ~/.kube/config $backup
}

mv config ~/.kube/config

print "[ INFO ] Running `kubectl get nodes` to verify ~/.kube/config"

kubectl get nodes
| complete
| if $in.exit_code == 0 {
      print "[ INFO ] OK!"
      print $in.stdout
    } else {
      print "[ ERROR ] See stderr below..."
      print $in
      exit 1
  }
