source ./env.nu

let gpu = $env.jupyterhub.gpu

if not $gpu.enabled {
  print "[ INFO ] GPU support disabled; skipping GPU stack validation"
  exit 0
}

let gpu_nodegroup = $gpu.nodegroup.name
let gpu_label = $"capi.stackhpc.com/node-group=($gpu_nodegroup)"
let smoke_test_manifest = "gpu-test-pod.yaml"
let smoke_test_pod = "gpu-nvidia-smi-test"

print $"[ INFO ] Validating GPU nodes in nodegroup ($gpu_nodegroup)"

let wait_timeout = 20min
let poll_interval = 30sec
let start = date now
mut advertises_gpu = false
mut gpu_nodes_found = false
mut gpu_node_status = []

print $"[ INFO ] Waiting up to ($wait_timeout) for GPU resource advertisement"

while not $advertises_gpu and ((date now) - $start) < $wait_timeout {
  let gpu_operator_namespace = kubectl get namespace gpu-operator --ignore-not-found -o name
  | str trim

  if ($gpu_operator_namespace | is-empty) {
    print "[ WARN ] Namespace gpu-operator was not found"
  } else {
    print "[ INFO ] GPU Operator pod status"
    kubectl -n gpu-operator get pods -o wide
  }

  let gpu_nodes = kubectl get nodes -l $gpu_label -o json
  | from json
  | get items

  $gpu_nodes_found = not ($gpu_nodes | is-empty)

  $gpu_node_status = ($gpu_nodes
  | each {|node|
      {
        name: $node.metadata.name,
        allocatable_gpu: ($node.status.allocatable | get -o "nvidia.com/gpu" | default "0")
      }
    })

  if $gpu_nodes_found {
    print "[ INFO ] GPU node allocatable resources"
    print ($gpu_node_status | sort-by name)
  } else {
    print $"[ WARN ] No nodes found for GPU nodegroup ($gpu_nodegroup)"
  }

  $advertises_gpu = ($gpu_node_status
  | any {|node| ($node.allocatable_gpu | into int) > 0 })

  if not $advertises_gpu {
    print $"[ INFO ] GPU resources not advertised yet; sleeping ($poll_interval)"
    sleep $poll_interval
  }
}

if not $gpu_nodes_found {
  print $"[ ERROR ] No nodes found for GPU nodegroup ($gpu_nodegroup) after ($wait_timeout)"
  exit 1
}

if not $advertises_gpu {
  print $"[ ERROR ] No GPU node advertises allocatable nvidia.com/gpu after ($wait_timeout)"
  print "[ ERROR ] Verify the NVIDIA driver/runtime/toolkit and GPU Operator stack before running GPU pods"
  exit 1
}

print "[ INFO ] At least one GPU node advertises allocatable nvidia.com/gpu"
print $"[ INFO ] Running GPU smoke test from ($smoke_test_manifest)"

kubectl delete -f $smoke_test_manifest --ignore-not-found --wait=true
kubectl apply -f $smoke_test_manifest

if $env.LAST_EXIT_CODE != 0 {
  print $"[ ERROR ] Failed to create GPU smoke test pod ($smoke_test_pod)"
  exit 1
}

kubectl wait $"pod/($smoke_test_pod)" --for="jsonpath={.status.phase}=Succeeded" --timeout=5m
let wait_exit = $env.LAST_EXIT_CODE

print "[ INFO ] GPU smoke test logs"
kubectl logs $smoke_test_pod

if $wait_exit != 0 {
  print $"[ ERROR ] GPU smoke test pod ($smoke_test_pod) did not complete successfully"
  kubectl describe pod $smoke_test_pod
  kubectl delete pod $smoke_test_pod --ignore-not-found --wait=false
  exit 1
}

kubectl delete pod $smoke_test_pod --ignore-not-found --wait=false
print "[ INFO ] GPU stack validation succeeded"
