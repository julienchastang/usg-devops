source ./env.nu

let gpu = $env.jupyterhub.gpu

if not $gpu.enabled {
  print "[ INFO ] GPU support disabled; skipping NVIDIA device plugin install"
  exit 0
}

let daemonset = "nvidia-device-plugin-daemonset"

print "[ INFO ] Installing NVIDIA Kubernetes device plugin"
kubectl apply -f $gpu.device_plugin_manifest

let daemonsets = kubectl -n kube-system get daemonset $daemonset --ignore-not-found
| detect columns

if ($daemonsets | is-empty) {
  print $"[ ERROR ] NVIDIA device plugin DaemonSet ($daemonset) was not found in kube-system"
  exit 1
}

print $"[ INFO ] Waiting for NVIDIA device plugin DaemonSet ($daemonset)"
kubectl -n kube-system rollout status $"daemonset/($daemonset)" --timeout=5m

print "[ INFO ] NVIDIA device plugin pod status"
kubectl -n kube-system get pods -l name=nvidia-device-plugin-ds -o wide

print "[ INFO ] Optional GPU smoke test: kubectl apply -f gpu-test-pod.yaml"
