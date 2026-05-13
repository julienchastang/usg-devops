# Do everything, with the exception of install-jhub.nu, as this takes some
# human intervention for the final install

nu 00-configure-env.nu;
nu 01-create-cluster.nu;
nu 02-fetch-k8s-config.nu;
nu 03-install-ingress.nu;
nu 04-create-arecord.nu;
nu 05-cert-manager.nu;
nu 06-create-nodegroup.nu;
nu 06b-install-gpu-support.nu;
nu 06c-taint-gpu-nodes.nu;
nu 07-set-jhub-core-node.nu;
nu 08-shared-user-volume.nu;
nu 09-configure-helm-jhub.nu;
nu 10-create-jhub-values.nu;
nu 11-create-secrets.nu;

source env.nu
let jhub_values = $env.jupyterhub.jhub.values_path
let authentication = $env.jupyterhub.authentication

print $"[ INFO ] Review ($jhub_values), configure OAuth at ($authentication), then run `nu 12-install-jhub.nu`"
print "[ INFO ] See you next time!"
