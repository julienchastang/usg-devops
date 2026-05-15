# TODO
# - [ ] Change file name from 01-create-cluster.nu to 01-magnum-cluster.nu
# - [ ] Make this script take arguments, and/or use sub-commands
# - [ ] Move cluster creation logic (everything currently in here) to a "create"
#       command
# - [ ] Create a "delete" command for cluster deletion
# - [ ] Create a "show" command for showing cluster

source ./env.nu

let cluster = $env.jupyterhub.cluster

print $"[ INFO ] Creating cluster: ($cluster.name)"

(openstack coe cluster create
    --cluster-template $cluster.template
    --master-count $cluster.master.count
    --node-count $cluster.worker.count
    --master-flavor $cluster.master.flavor
    --flavor $cluster.worker.flavor
    --labels $"auto_scaling_enabled=($cluster.autoscaling)"
    --labels min_node_count=1
    --labels max_node_count=1
    --fixed-network auto_allocated_network
    $cluster.name
)

# Wait for cluster API address, or error on timeout
let timeout = 20min
let start = date now
let check_status = {|| openstack coe cluster show $cluster.name -c status -f value | complete }
let check_api_address = {|| openstack coe cluster show $cluster.name -c api_address -f value | complete }
mut ready = false
mut status = null
mut api_address = ""

print $"[ INFO ] Waiting for cluster API address with timeout ($timeout)"

while not $ready and ((date now) - $start) < $timeout {
  let status_result = do $check_status
  if $status_result.exit_code == 0 {
    $status = ($status_result.stdout | str trim)

    if $status == "CREATE_FAILED" {
      print "[ ERROR ] Cluster creation failed!"
      exit 1
    }
  } else {
    print "[ WARNING ] Failed to check cluster status"
  }

  let api_address_result = do $check_api_address
  if $api_address_result.exit_code == 0 {
    $api_address = ($api_address_result.stdout | str trim)
    $ready = not ($api_address | is-empty)
  } else {
    print "[ WARNING ] Failed to check cluster API address"
  }

  print $"[ INFO ] Time elapsed ((date now) - $start)"
  sleep 30sec
}

if not $ready {
  print $"[ ERROR ] Failed to get cluster API address in ($timeout)"
  exit 1
}
