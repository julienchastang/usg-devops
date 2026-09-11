# Docker/Calico CIDR overlap — Fall 2026

## Summary

TL;DR: Docker was unnecessarily installed and running in the Magnum/CAPI node image, and its default networking conflicted with Kubernetes/Calico networking, causing intermittent JupyterHub connection and spawn failures.

All Fall 2026 Magnum CAPI clusters were built from images that contain Docker in addition to the `containerd` runtime used by Kubernetes.

Docker creates the default bridge network:

```text
172.17.0.0/16
```

The Calico pod CIDR is:

```text
172.16.0.0/13
```

These networks overlap.

Docker installs a MASQUERADE rule for `172.17.0.0/16`. Kubernetes pods assigned `172.17.x.x` addresses therefore match this Docker rule even though they are not Docker containers.

Calico is the Kubernetes networking system that connects pods across nodes and enforces network security policies between them. This overlap can cause Docker to rewrite the source address of inter-node pod traffic and break Calico NetworkPolicy matching.

## Symptoms

JupyterHub single-user servers may start, but the Hub cannot connect to them on port `8888`. Spawns eventually time out with errors such as:

```text
Spawn failed: Server at http://172.20.16.8:8888/user/user123/api didn't respond in 120 seconds
```

The problem only affects certain pod/node placements, which makes the failure appear intermittent.

## Demonstration

On Hubs where you are seeing JupyterHub spawn failures when starting a single-user server, first confirm that the Hub pod and single-user pod are on different nodes:

```bash
kubectl -n jhub get pod \
  -l component=hub \
  -o custom-columns='POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP'

kubectl -n jhub get pod jupyter-user123 \
  -o custom-columns='POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP'
```

Example:

```text
hub-6d75dd6b5-l8nt4   ...default-worker...   172.17.119.208
jupyter-user123       ...mediums...          172.23.130.27
```

In one terminal, start a privileged `netshoot` debug container on the Hub node:

```bash
HUBNODE=$(kubectl -n jhub get pod -l component=hub \
  -o jsonpath='{.items[0].spec.nodeName}')

kubectl debug node/"$HUBNODE" -it \
  --image=nicolaka/netshoot:v0.14 \
  --profile=sysadmin
```

[`nicolaka/netshoot`](https://github.com/nicolaka/netshoot) is a container image equipped with common Linux networking and troubleshooting tools such as `tcpdump`, `curl`, `ip`, `dig`, and `iptables`.

Inside that container, capture SYN packets destined for the single-user pod. A SYN packet is the first packet sent when one network endpoint tries to establish a new TCP connection to another IP address and port.

```bash
# Capture up to 10 TCP SYN packets on any interface that are destined for
# the single-user pod (172.23.130.27) on port 8888.
#
# -nn     Do not resolve hostnames or service names; show raw IPs and ports.
# -l      Line-buffer output so packets appear immediately.
# -i any  Listen on all network interfaces, including Calico and vxlan.calico.
# -c 10   Stop automatically after capturing 10 matching packets.
#
# The filter limits output to traffic going to the user pod on TCP/8888
# and only packets with the SYN flag set, i.e. connection attempts.
tcpdump -nn -l -i any -c 10 \
  'dst host 172.23.130.27 and tcp dst port 8888 and tcp[tcpflags] & tcp-syn != 0'
```

In a second terminal, trigger the connection from the Hub:

```bash
PODIP=$(kubectl -n jhub get pod jupyter-user123 \
  -o jsonpath='{.status.podIP}')

kubectl -n jhub exec deploy/hub -- \
  curl -v --connect-timeout 5 \
  "http://${PODIP}:8888/user/user123/api"
```

In the broken state, `tcpdump` shows the source IP changing as the packet crosses the Hub worker:

```text
cali... In       IP 172.17.119.208.54470 > 172.23.130.27.8888: Flags [S]
vxlan.calico Out IP 172.17.119.192.54470 > 172.23.130.27.8888: Flags [S]
```

`172.17.119.208` is the Hub pod IP. The source is rewritten to `172.17.119.192` before the packet leaves through `vxlan.calico`. The connection then times out because the remote NetworkPolicy no longer sees the traffic as originating from the Hub pod.

In the normal case, the source IP remains unchanged:

```text
cali... In       IP 172.17.119.208.54470 > 172.23.130.27.8888: Flags [S]
vxlan.calico Out IP 172.17.119.208.54470 > 172.23.130.27.8888: Flags [S]
```

## Root Cause

The Magnum node image has Docker installed and running even though Kubernetes uses `containerd`. Docker creates its default bridge network on `172.17.0.0/16`, which overlaps the Calico pod CIDR `172.16.0.0/13`.

Docker also installs this NAT rule:

```bash
-s 172.17.0.0/16 ! -o docker0 -j MASQUERADE
```

As a result, Kubernetes pods assigned `172.17.x.x` addresses can be mistaken for Docker traffic. When that traffic leaves a node through Calico, Docker rewrites the source IP to the node address. This destroys the original pod identity and can cause Calico NetworkPolicy to drop the traffic, leading to JupyterHub spawn timeouts.

## Fall 2026 Mitigation

A privileged DaemonSet removes exactly the conflicting Docker MASQUERADE rule and continues checking for its reappearance.

See `daemonset.yaml`.

## Permanent Fix

Do not carry this mitigation forward into future cluster generations.

Fix the CAPI node image by removing or disabling Docker if it is unnecessary.

## Removal

After all Fall 2026 clusters have been retired or rebuilt from corrected images, delete this mitigation.

## AI Usage for This Investigation

This document was developed iteratively through human investigation and AI-assisted analysis. All technical conclusions were checked against the observed cluster behavior before being included here.
