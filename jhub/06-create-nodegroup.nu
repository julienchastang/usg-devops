# TODO
# - [ ] Rename this file to 06-nodegroup.nu
# - [ ] Move this logic to a "create" sub-command; Maybe add an argument to feed
#       the command an "arbitrary" nodegroup definition in case we want more
#       than 1
# - [ ] Create a "delete" sub-command

source ./env.nu

let cluster_name = $env.jupyterhub.cluster.name
let nodegroup = $env.jupyterhub.nodegroup

print $"[ INFO ] Creating nodegroup ($nodegroup.name)"

(openstack coe nodegroup create $cluster_name $nodegroup.name
  --node-count 1
  --flavor $nodegroup.flavor
  --labels $"auto_scaling_enabled=($nodegroup.autoscaling)"
  --min-nodes 1
  --max-nodes $nodegroup.max_nodes
)

# Wait for nodegroup creation, or error on timeout
let timeout = 10min
let gpu_timeout = 30min
let start = date now
let check_status = {|| (openstack coe nodegroup show $cluster_name $nodegroup.name -f yaml | from yaml).status }
mut ready = false
mut status = null

print $"[ INFO ] Wait for nodegroup creation with timeout ($timeout)"

while not $ready and ((date now) - $start) < $timeout {
  $status = do $check_status
  $ready = $status == "CREATE_COMPLETE"
  if $status == "CREATE_FAILED" {
    print "[ ERROR ] Nodegroup creation failed!";
    break
  }
  print $"[ INFO ] Time elapsed: ((date now) - $start)"
  sleep 30sec
}

if not $ready {
  print $"[ [ ERROR ] Failed to create healthy nodegroup in ($timeout)"
  exit 1
}

let gpu = $env.jupyterhub.gpu

if $gpu.enabled {
  let gpu_nodegroup = $gpu.nodegroup

  if $gpu_nodegroup.flavor == null {
    print "[ ERROR ] GPU nodegroup flavor must be set when GPU support is enabled"
    exit 1
  }

  if $gpu_nodegroup.max_nodes == null {
    print "[ ERROR ] GPU nodegroup max_nodes must be set when GPU support is enabled"
    exit 1
  }

  print $"[ INFO ] Creating GPU nodegroup ($gpu_nodegroup.name)"

  (openstack coe nodegroup create $cluster_name $gpu_nodegroup.name
    --node-count $gpu_nodegroup.min_nodes
    --flavor $gpu_nodegroup.flavor
    --labels $"auto_scaling_enabled=($gpu_nodegroup.autoscaling)"
    --min-nodes $gpu_nodegroup.min_nodes
    --max-nodes $gpu_nodegroup.max_nodes
    --docker-volume-size $gpu_nodegroup.docker_volume_size
  )

  let start = date now
  let check_status = {|| (openstack coe nodegroup show $cluster_name $gpu_nodegroup.name -f yaml | from yaml).status }
  mut ready = false
  mut status = null

  print $"[ INFO ] Wait for GPU nodegroup creation with timeout ($gpu_timeout)"

  while not $ready and ((date now) - $start) < $gpu_timeout {
    $status = do $check_status
    $ready = $status == "CREATE_COMPLETE"
    if $status == "CREATE_FAILED" {
      print "[ ERROR ] GPU nodegroup creation failed!";
      break
    }
    print $"[ INFO ] Time elapsed: ((date now) - $start)"
    sleep 30sec
  }

  if not $ready {
    print $"[ [ ERROR ] Failed to create healthy GPU nodegroup in ($gpu_timeout)"
    exit 1
  }
}
