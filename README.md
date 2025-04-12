## Cilium SRv6 Lab

This lab is mostly built, however, the lab guide is very much under construction.

The lab consists of a pair of K8s clusters separated by an XRd network as shown here:

![Topology](./topology-diagram.png)

The K8s nodes in the diagrams are Ubuntu VMs (nested VMs if running in dCloud)
The XRd nodes are Dockerized XR routers deployed using Containerlab.

Requirements:

- A linux host or VM with at least 24 vCPU and 64GB of RAM
- KVM and Containerlab are installed
- The lab has been developed/tested using Ubuntu 22.04


Very quick instructions:

1. Build Ubuntu qcow2 images to serve as K8s control plane and worker nodes
2. Define and deploy Ubuntu VMs - see example virsh xml files in the [k8s-cluster00 directory](./k8s-cluster00/hosts/)
3. Install K8s on Ubuntu VMs [Instructions here](./k8s-install.md)
4. Install Cilium Enterprise on K8s control plane nodes [Instructions here](./Lab-Guide-old-part2.md)
5. Launch XRd topology
```
sudo containerlab deploy -t topology.yml
```
