source ./env.nu

let gpu = $env.jupyterhub.gpu

if not $gpu.enabled {
  print "[ INFO ] GPU support disabled; skipping GPU node taints"
  exit 0
}

let gpu_nodegroup = $gpu.nodegroup.name
let taint = $gpu.taint
let taint_spec = $"($taint.key)=($taint.value):($taint.effect)"

print $"[ INFO ] Tainting GPU nodes in nodegroup ($gpu_nodegroup) with ($taint_spec)"

let gpu_nodes = kubectl get nodes -l $"capi.stackhpc.com/node-group=($gpu_nodegroup)"
| detect columns
| get NAME
| sort

if ($gpu_nodes | is-empty) {
  print $"[ ERROR ] No nodes found for GPU nodegroup ($gpu_nodegroup)"
  exit 1
}

$gpu_nodes
| each {|node| kubectl taint node $node $taint_spec --overwrite }

print ($gpu_nodes | wrap "GPU Nodes")
print "[ INFO ] GPU nodes tainted"
