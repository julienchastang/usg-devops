# TODO
# [x] Storage
#     [-] Standard jupyterhub-home-nfs shared storage
#     [x] Shared drive option
# [ ] startup commands
#     [x] Ensure we can set 0 or multiple gitpuller commands
#     [ ] Ensure that the config created by this even *works*
# [x] github oauth stuff
#     Read from the env, or even a file?
#     * Maybe this can be the only copy-paste-able thing?
# [x] imagePullSecret
#     Read from the env, or even a file?
#     * Maybe this can be the only copy-paste-able thing?
# [x] singleuser.resources
# [x] Move constants and options to env.nu file...

####################
# Constants
####################

let idv_sidecar_name = "docker.io/unidata/cave-idv-sidecar"
let idv_sidecar_tag = "2025Aug14_201214_7e09"
let idv_sidecar = $"($idv_sidecar_name):($idv_sidecar_tag)"

####################
# Load from env.nu file
####################

source env.nu

let zone = $env.jupyterhub.zone

let jhub = $env.jupyterhub.jhub

# Unique to each JHub
let jhub_admins = $jhub.admins
let cluster_name = $env.jupyterhub.cluster.name
let image_name = $jhub.image_name | default $"unidata/($env.jupyterhub.cluster.name)"
let image_tag = $jhub.image_tag
let gpu = $env.jupyterhub.gpu
let git_repos = $jhub.git_repos

let user_placeholders = if ($jhub.user_placeholders | describe) != nothing {
  $jhub.user_placeholders
} else { 0 }

let desired_profiles = $jhub.desired_profiles
let default_profile = $jhub.default_profile

# `Persistent storage per user` is enabled if a home_size value is set
let persistent_storage_enabled = $env.jupyterhub.shared_volume.home_size != null
# `/share` mount is enabled if a data_size value is set
let shared_data_enabled = $env.jupyterhub.shared_volume.data_size != null

####################
# Derived from Options
####################

let domain = $"($cluster_name).($zone | str trim -r -c ".")"

let volumes = if $persistent_storage_enabled or $shared_data_enabled {
  [{
    name: "home-nfs",
    persistentVolumeClaim: {claimName: "home-nfs"},
  }]
} else { [] }

let volume_mounts = []
| if $persistent_storage_enabled {
  $in | append {
    name: "home-nfs",
    mountPath: "/home/jovyan",
    subPath: "{username}"
  }
} else { $in }
| if $shared_data_enabled {
  $in | append {
    name: "home-nfs",
    mountPath: "/share",
    subPath: "_shared"
  } 
} else { $in }

let resources = {
  storage: {
    type: none,
    extraVolumes: $volumes,
    extraVolumeMounts: $volume_mounts
  }
  memory: {guarantee: "13G", limit: "16G"},
  cpu: {guarantee: 3.25, limit: 4}
}

let extraContainers = [{
  name: cave-idv-sidecar
  image: $idv_sidecar
  volume_mounts: $volume_mounts,
  ports: [{containerPort: 6080, name: "novnc" }]
  resources: {
    requests: { cpu: 6, memory: "21G" }
    limits: { cpu: 6, memory: "21G" }
  }
}]

let profileList = ({
  "Low": {
    display_name: "Low Power"
    description: "Up to 1 CPU, 4GiB RAM"
    kubespawner_override: {
      mem_guarantee: 2.875G
      mem_limit: 4G
      cpu_guarantee: .625 
      cpu_limit: 1
      node_selector: { capi.stackhpc.com/node-group: mediums }
    }
  },
  "Standard": {
    display_name: "Standard"
    description: "Up to 2 CPU, 8GiB RAM"
    kubespawner_override: {
      mem_guarantee: 6.25G
      mem_limit: 8G
      cpu_guarantee: 1.5 
      cpu_limit: 2
      node_selector: { capi.stackhpc.com/node-group: mediums }
    }
  },
  "Medium": {
    display_name: "Medium Power"
    description: "Up to 4 CPU, 16GiB RAM"
    kubespawner_override: {
      mem_guarantee: 13G
      mem_limit: 16G
      cpu_guarantee: 3.25
      cpu_limit: 4
      node_selector: { capi.stackhpc.com/node-group: mediums }
    }
  }
  "High": {
    display_name: "High Power"
    description: "Up to 8 CPU, 32GiB RAM"
    kubespawner_override: {
      mem_guarantee: 26.5G
      mem_limit: 32G
      cpu_guarantee: 7 
      cpu_limit: 8
      node_selector: { capi.stackhpc.com/node-group: mediums }
    }
  }
  "IDV": {
    display_name: "Virtual Desktop: Run IDV & CAVE"
    description: "Jupyter: 3 GB of memory; 1 vCPUS, IDV/CAVE: 21 GB of memory; 6 vCPUS"
    kubespawner_override: {
      mem_guarantee: 3G
      mem_limit: 3G
      cpu_guarantee: 1 
      cpu_limit: 1
      node_selector: { capi.stackhpc.com/node-group: mediums }
      extra_containers: $extraContainers
    }
  }
} | if $gpu.enabled {
  let gpu_image_name = $gpu.image_name | default $image_name
  let gpu_image_tag = $gpu.image_tag | default $image_tag

  $in | insert "GPU" {
    display_name: "GPU"
    description: "GPU-enabled Jupyter session"
    kubespawner_override: {
      image: $"($gpu_image_name):($gpu_image_tag)"
      node_selector: {
        capi.stackhpc.com/node-group: $gpu.nodegroup.name
      }
      extra_resource_limits: {
        nvidia.com/gpu: "1"
      }
      tolerations: [
        {
          key: $gpu.taint.key
          operator: "Equal"
          value: $gpu.taint.value
          effect: $gpu.taint.effect
        }
      ]
    }
  }
} else { $in })

let gitpuller = $git_repos
| each {|r|
    let server = if server in $r {$r.server} else {"https://github.com" };
    let branch = if branch in $r {$r.branch} else {"main"};
    let dest_dir = if dest_dir in $r {$r.dest_dir} else {$r.repo};
    $r
    | default "https://github.com" server
    | default "main" branch
    | default $in.repo dest_dir
    | $"gitpuller ($in.server)/($in.user)/($in.repo) ($in.branch) ($in.dest_dir);"
  }

let commands = [
  "bash"
  "-c"
  ([
  # To keep appropriate permissions on ssh keys
  'dir="/home/jovyan/.ssh"; [ -d $dir ] && { chmod 700 $dir && chmod -f 600 $dir/* && chmod -f 644 $dir/*.pub; } || true;'
  # Useful files
  'cp -t /home/jovyan /Acknowledgements.ipynb \'
  '  /update_material.ipynb /additional_kernels.ipynb;'
  # gitpuller
  ...$gitpuller
  # default kernel
  'python /default_kernel.py $DEFAULT_ENV_NAME /home/jovyan;'
  # config files
  '[[ -f $HOME/.bashrc ]] || cp /etc/skel/.bashrc $HOME/;'
  '[[ -f $HOME/.profile ]] || cp /etc/skel/.profile $HOME/;'
  '[[ -f $HOME/.bash_logout ]] || cp /etc/skel/.bash_logout $HOME/;'
  '[[ -f $HOME/.condarc ]] || cp /.condarc $HOME/;'
  # Symlinks
  '[ -d "/share" ] && [ ! -L ~/share ] && ln -s /share ~/share || true;'
  ''
  ] | str join "\n")
]


####################
# Create values.yaml
####################

let hub = {
  config: {
    Authenticator: {
      admin_users: [
        ana-v-espinoza,
	      julienchastang,
	      ...$jhub_admins
      ],
      allowed_users: [
        ana-v-espinoza,
	      julienchastang,
	      ...$jhub_admins
      ],
      allow_existing_users: true
    },
    JupyterHub: {
      authenticator_class: "github"
    }
  }
}

let proxy = {
  service: {
    type: "ClusterIP"
  }
}

let ingress = {
  enabled: true,
  annotations: {
    "kubernetes.io/ingress.class": "traefik",
    "cert-manager.io/cluster-issuer": "letsencrypt",
    "traefik.ingress.kubernetes.io/middlewares.limit.buffering.maxRequestBodyBytes": "500000000"
  },
  hosts: [ $domain ],
  tls: [{
    hosts: [ $domain ],
    secretName: "certmanager-tls-jupyterhub"
  }]
}

let scheduling = {
  corePods: {
    tolerations: [
      { key: "hub.jupyter.org/dedicated"
        operator: "Equal"
        value: "core"
        effect: "NoSchedule"
      }
      {
        key: "hub.jupyter.org_dedicated"
        operator: "Equal"
        value: "core"
        effect: "NoSchedule"
      }
    ],
    nodeAffinity: {
      matchNodePurpose: "require"
    }
  }
  podPriority: { enabled: true }
  userPlaceholder: { replicas: $user_placeholders }
}

let singleuser = {
  nodeSelector: { "capi.stackhpc.com/node-group": mediums },
  extraEnv: {
    "NBGITPULLER_DEPTH": "0"
    "START_VIRTUAL_DESKTOP": "1"
  },
  startTimeout: 600,
  ...$resources,
  defaultUrl: "/lab",
  image: {
    name: $image_name,
    tag: $image_tag
  }
  lifecycleHooks: { postStart: { exec: { command: $commands}}},
  profileList: ($profileList
    | upsert ([$default_profile "default"] | into cell-path) true
    | select ...$desired_profiles
    | transpose name value
    | get value
  )
}

{
  hub: $hub,
  proxy: $proxy
  ingress: $ingress,
  scheduling: $scheduling,
  singleuser: $singleuser
}
| to yaml
| save -f $env.jupyterhub.jhub.values_path


# def "create jhub values" [] {
#   
# }
