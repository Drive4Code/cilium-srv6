# cilium-srv6-lab part2

## Install and Configure Cilium Enterprise CNI on control plane nodes

cd into the k8s-cluster00/cilium directory
```
cd k8s-cluster00/cilium
```

1. Install Cilium Enterprise via this Helm chart: [cilium-enterprise.yaml](k8s-cluster00/cilium/cilium-enterprise.yaml)
```
helm install cilium isovalent/cilium --version 1.16.8  --namespace kube-system -f cilium-enterprise.yaml 
```
  Note: some key lines in the yaml where we specify SRv6 attributes under *enterprise*. We're also enabling Cilium BGP from the outset:

  ```
  ipv6:
    enabled: true
  enterprise:
    srv6:
      enabled: true
      encapMode: reduced
      locatorPoolEnabled: true
  bgpControlPlane:
    enabled: true
  ```

  The install command output should look something like:

  ```
  cisco@k8s-cp-node00:~/cilium-srv6/cilium$ helm install cilium isovalent/cilium --version 1.15.6  --namespace kube-system -f helm-cilium-enterprise.yaml 
  NAME: cilium
  LAST DEPLOYED: Sun Aug 18 12:06:50 2024
  NAMESPACE: kube-system
  STATUS: deployed
  REVISION: 1
  TEST SUITE: None
  NOTES:
  You have successfully installed Cilium.

  Your release version is 1.15.6.

  For any further help, visit https://docs.cilium.io/en/v1.15/gettinghelp
  ```

5. Run a couple commands to verify the Cilium Installation

  Display Cilium daemonset status:
  ```
  kubectl get ds -n kube-system cilium
  ```

  The output should show 2 cilium daemonsets (ds) available, example:
  ```
  cisco@k8s-cp-node00:~/cilium-srv6/cilium$ kubectl get ds -n kube-system cilium
  NAME     DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
  cilium   2         2         2       2            2           kubernetes.io/os=linux   62s
  ```

  Note: if the previous output shows '0' under AVAILABLE give it a couple minutes and try again. If its still showing '0' the K8s cluster may need to be reset (rare)

  Helm get values (sort of a 'show run' for the Helm/Cilium install)
  ```
  helm get values cilium -n kube-system
  ```

6. The default behavior for Kubernetes is to not run application pods or containers on the control plane node. This is loosely analogous to networks where route reflectors are usually not deployed inline and carrying transport traffic. However, we're running a small cluster in the lab and we want the ability to deploy pods on the control plane node, so in kube-speak we need to "untaint" it. To untaint the control plane node we run the "kubectl taint nodes ... " command with a "-" sign at the end:

  ```
  kubectl taint nodes --all node-role.kubernetes.io/control-plane-
  ```

  If the command output returns "taint "node-role.kubernetes.io/control-plane" not found" then the node is already untainted

##  Setup Cilium BGP Peering
First a brief explanation of *`Kubernetes Custom Resource Definitions (CRDs)`*. 

Per: https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/

*A custom resource is an extension of the Kubernetes API that is not necessarily available in a default Kubernetes installation. It represents a customization of a particular Kubernetes installation. However, many core Kubernetes functions are now built using custom resources, making Kubernetes more modular.*

Said another way, CRDs enable us to add, update, or delete Kubernetes cluster elements and their configurations. The add/update/delete action might apply to the cluster as a whole, a node in the cluster, an aspect of cluster networking or the CNI (aka, the work we'll do in this lab), or any given element or set of elements within the cluster including pods, services, daemonsets, etc.

A CRD applied to a single element in the K8s cluster would be analogous configuring BGP on a router. A CRD applied to multiple or cluster-wide would be analogous to adding BGP route-reflection to a network as a whole. 

CRDs come in YAML file format and in the next several sections of this lab we'll apply CRDs to the K8s cluster to setup Cilium BGP peering, establish Cilium SRv6 locator ranges, create VRFs, etc.

The initial version of this guide assumes eBGP peering between k8s nodes and *`xrd14`* & *`xrd15`*. For reference an example iBGP CRD/YAML file can be found in the cilium-srv6/cilium directory.

Here is a partial Cilium eBGP CRD (aka eBGP configuration) with notes:
```
apiVersion: "cilium.io/v2alpha1"
kind: CiliumBGPPeeringPolicy
metadata:
  name: k8s-wkr-node01
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/hostname: k8s-wkr-node01    <--- node to which this portion of config belongs
  virtualRouters:
  - localASN: 65015                 <--- worker node's BGP ASN
    exportPodCIDR: true             <--- advertise local PodCIDR prefix
    mapSRv6VRFs: true               <--- SRv6 L3VPN
    srv6LocatorPoolSelector:        
      matchLabels:
        export: "true"              <--- advertise Locator prefix into BGP IPv6 underlay
    neighbors:
    - peerAddress: "10.15.1.1/32"   <--- ipv4 peer address for xrd15
      peerASN: 65010
      families:                     <--- address families for this BGP session
       - afi: ipv4
         safi: unicast
    - peerAddress: "2001:db8:18:15::1/128"   <--- ipv6 peer address for xrd15
      peerASN: 65010
      families:
        - afi: ipv6               <--- address families for this BGP session
          safi: unicast
        - afi: ipv4                
          safi: mpls_vpn          <--- L3VPN AFI/SAFI
          
```

You may review the entire Cilium eBGP policy yaml here: [Cilium BGP](cilium/ebgp-policy.yaml). Note the ebgp-policy.yaml file has BGP configuration/peering parameters for both the control plane node and worker node.

1. Apply the Cilium eBGP policy - On the k8s control plane vm cd into the cilium directory and apply the Cilium BGP CRD
```
cd ~/cilium-srv6/k8s-cluster00/cilium/
kubectl apply -f 01-bgp-cluster.yaml
```

  Note: the upstream XRd peers (xrd09 and xrd10) have already been configured per the Containerlab topology definitions, example: 

  [xrd09.cfg](./xrd-config/xrd09.cfg#L150)
  [xrd10.cfg](./xrd-config/xrd10.cfg#L150)

1. From the control plane node verify Cilium BGP peering with the following cilium CLI:
```
cilium bgp peers
```

We expect to see v4 and v6 sessions active and advertisement and receipt of a number of BGP NLRIs for ipv4, ipv6, and ipv4/mpls_vpn (aka, SRv6 L3VPN). Example:
```
cisco@cluster00-cp:~/cilium-srv6$ cilium bgp peers
Node            Local AS     Peer AS  Peer Address     Session State   Uptime     Family          Received   Advertised
cluster00-cp    4200001000   65010    fc00:0:1000::1   established     9h37m41s   ipv6/unicast    39         2    
                                                                                  ipv4/mpls_vpn   1          1    
cluster00-wkr00 4200001001   65010    fc00:0:1001::1   established     9h37m42s   ipv6/unicast    39         2    
                                                                                  ipv4/mpls_vpn   1          1      
```

2. You can also check individual sessions with the --node flag:
```
cilium bgp peers --node cluster00-wkr00
```

*** The following steps only need to be ran on the respective control planes ***

## Cilium SRv6 Sidmanager and Locators
Per Cilium Enterprise documentation:
*The SID Manager manages a cluster-wide pool of SRv6 locator prefixes. You can define a prefix pool using the IsovalentSRv6LocatorPool resource. The Cilium Operator assigns a locator for each node from this prefix. In this example we'll allocate /48 bit uSID based locators.*

1. Define and apply a Cilium SRv6 locator pool, example: [srv6-locator-pool.yaml](./k8s-cluster00/05-srv6-locator-pool.yaml)

  From the ~/cilium-srv6/cilium/ directory:
  ```
  kubectl apply -f 05-srv6-locator-pool.yaml
  ```

2. Validate locator pool
```
kubectl get sidmanager -o yaml
```
or 
```
kubectl get sidmanager -o custom-columns="NAME:.metadata.name,ALLOCATIONS:.spec.locatorAllocations"
```

  The example output below shows Cilium having allocated locator prefixes as follows:
  #### k8s-cp-node00: fc00:0:15b::/48
  #### k8s-wkr-node01: fc00:0:134::/48

  We'll want to keep track of the allocated locator prefixes as we'll need to redistribute them from BGP into ISIS later in the lab.

  Example output:
  ```
  cisco@k8s-cp-node00:~$ kubectl get sidmanager -o yaml
  apiVersion: v1
  items:
  - apiVersion: isovalent.com/v1alpha1
    kind: IsovalentSRv6SIDManager
    metadata:
      creationTimestamp: "2024-08-18T19:12:50Z"
      generation: 1
      name: k8s-cp-node00
      resourceVersion: "2593"
      uid: 4220c57d-478d-4764-92c9-d050e4a53a9a
    spec:
      locatorAllocations:
      - locators:
        - behaviorType: uSID
          prefix: fc00:0:15b::/48        <---------- Locator for the control plane node
          structure:
            argumentLenBits: 0
            functionLenBits: 16
            locatorBlockLenBits: 32
            locatorNodeLenBits: 16
        poolRef: pool0                   <---- locator pool name/id 
    status:
      sidAllocations: []  <---- no SIDs yet, we'll see SIDs allocated when we create VRFs in the next step
  - apiVersion: isovalent.com/v1alpha1
    kind: IsovalentSRv6SIDManager
    metadata:
      creationTimestamp: "2024-08-18T19:12:50Z"
      generation: 1
      name: k8s-wkr-node01
      resourceVersion: "2594"
      uid: bb01d730-2e9a-44e7-9b17-90f2df7ae553
    spec:
      locatorAllocations:
      - locators:
        - behaviorType: uSID
          prefix: fc00:0:134::/48        <---------- Locator for the worker node
          structure:
            argumentLenBits: 0
            functionLenBits: 16
            locatorBlockLenBits: 32
            locatorNodeLenBits: 16
        poolRef: pool0
    status:
      sidAllocations: []
  kind: List
  metadata:
    resourceVersion: ""

  ```

## Establish Cilium VRFs
1. Add vrf(s) - this example also adds a couple alpine linux container pods to vrf blue:
   [vrf-blue.yaml](./k8s-cluster00/06-vrf-blue.yamll)
```
kubectl apply -f 06-vrf-blue.yaml
```

2. Verify VRF and sid allocation on the control plane node:
```
kubectl get sidmanager k8s-cp-node00 -o yaml
```

  Example output from sidmanager:
  ```
  cisco@k8s-cp-node00:~/cilium-srv6/cilium/cilium$ kubectl get sidmanager k8s-cp-node00 -o yaml
  apiVersion: isovalent.com/v1alpha1
  kind: IsovalentSRv6SIDManager
  metadata:
    creationTimestamp: "2024-08-18T19:12:50Z"
    generation: 1
    name: k8s-cp-node00
    resourceVersion: "27756"
    uid: 4220c57d-478d-4764-92c9-d050e4a53a9a
  spec:
    locatorAllocations:
    - locators:
      - behaviorType: uSID
        prefix: fc00:0:15b::/48    <------- control plane node locator
        structure:
          argumentLenBits: 0
          functionLenBits: 16
          locatorBlockLenBits: 32
          locatorNodeLenBits: 16
      poolRef: pool0
  status:
    sidAllocations:
    - poolRef: pool0
      sids:
      - behavior: uDT4      <----------- uSID L3VPN IPv4 table lookup
        behaviorType: uSID
        metadata: blue
        owner: srv6-manager
        sid:
          addr: 'fc00:0:15b:e46b::'  <---- uSID locator+function entry for control plane node VRF blue
          structure:
            argumentLenBits: 0
            functionLenBits: 16
            locatorBlockLenBits: 32
            locatorNodeLenBits: 16
  ```

3. optional: verify sidmanager status for the k8s worker node (this command should still be run on `k8s-cp-node00`):
```
kubectl get sidmanager k8s-wkr-node01 -o yaml
```

4. optional: create vrf-red:
```
kubectl apply -f vrf-red.yaml
```

5.  Run some kubectl commands to verify pod status, etc.
```
kubectl get pods -A
```

  ```
  kubectl describe pod -n blue bluepod0
  ```
  The kubectl get pods -A command should show a pair of bluepods up and running.

  Example:
  ```
  kubectl get pod -n blue bluepod0 -o=jsonpath="{.status.podIPs}"
  ```
  example output:
  ```
  [{"ip":"10.142.1.25"},{"ip":"2001:db8:142:1::f0cb"}]
  ```

6. Exec into one of the bluepod containers and ping the Cilium CNI gateway:
```
kubectl exec -it -n blue bluepod0 -- sh
ip route
ping <the "default via" address in ip route output>
```

  Output should look something like:
  ```
  cisco@k8s-cp-node00:~/cilium-srv6/cilium$ kubectl exec -it -n blue bluepod0 -- sh
  ip route/ # ip route
  default via 10.200.1.14 dev eth0 
  10.200.1.14 dev eth0 scope link 
  / # ping 10.200.1.14
  PING 10.200.1.14 (10.200.1.14): 56 data bytes
  64 bytes from 10.200.1.14: seq=0 ttl=63 time=1.378 ms
  64 bytes from 10.200.1.14: seq=1 ttl=63 time=0.142 ms
  ^C
  --- 10.200.1.14 ping statistics ---
  2 packets transmitted, 2 packets received, 0% packet loss
  round-trip min/avg/max = 0.142/0.760/1.378 ms
  ```

7. Exit the pod
```
exit
```

* Repeat these steps for VRF Green: `07-vrf-green.yaml`

## Setup Cilium SRv6 Responder

1. Per the previous set of steps, once allocated SIDs appear, we need to annotate the node. This will tell Cilium to program eBPF egress policies: 
```
kubectl annotate --overwrite nodes k8s-cp-node00 cilium.io/bgp-virtual-router.65014="router-id=10.14.1.2,srv6-responder=true"
kubectl annotate --overwrite nodes k8s-wkr-node01 cilium.io/bgp-virtual-router.65015="router-id=10.15.1.2,srv6-responder=true"
```

2. Verify SRv6 Egress Policies:
```
kubectl get IsovalentSRv6EgressPolicy -o yaml
```

  Example of partial output:
  ```
  cisco@k8s-cp-node00:~/cilium-srv6/cilium$ kubectl get IsovalentSRv6EgressPolicy -o yaml
  apiVersion: v1
  items:
  - apiVersion: isovalent.com/v1alpha1
    kind: IsovalentSRv6EgressPolicy
    metadata:
      creationTimestamp: "2024-08-30T21:53:54Z"
      generation: 1
      name: bgp-control-plane-14b02862521b89dbf9af2f4b3bec460131b6c411f940a7138322db4bda004c72
      resourceVersion: "3276"
      uid: f33b55e8-798a-4ebb-9134-1b4473fc86f6
    spec:
      destinationCIDRs:
      - 10.9.0.0/24                      <---- destination prefix in VRF red (vrfID 1000009)
      destinationSID: 'fc00:1:2:e004::'  <---- prefix is reachable via flex-algo to xrd02. Cilium/eBPF will encapsulate traffic using this SID
      vrfID: 1000009

  - apiVersion: isovalent.com/v1alpha1
    kind: IsovalentSRv6EgressPolicy
    metadata:
      creationTimestamp: "2024-08-30T21:53:54Z"
      generation: 1
      name: bgp-control-plane-c0dde75d6edfc035dee7ce80bc27628c89435459e6d8681d3ebfbd5366a736f2
      resourceVersion: "3277"
      uid: badc91bf-7624-42cb-bcc1-99fa1ec187cb
    spec:
      destinationCIDRs:
      - 10.10.1.0/24                       <---- destination prefix in VRF blue (vrfID 1000012)
      destinationSID: 'fc00:0:10:e004::'   <---- prefix is reachable via xrd10. Cilium/eBPF will encapsulate using this SID
      vrfID: 1000012
  kind: List
  metadata:
    resourceVersion: ""
  ```

## Redistribute Cilium Locators into XRd ISIS
*`Figure 4 - reminder of lab topology`*

![DC-fabric-and-k8s-vms](./topology-diagram.png)

xrd14 and xrd15 have been pre-configured with prefix-sets, route-policies, and bgp-to-isis redistribution. However, due to the dynamic nature of Cilium locator allocation we need to update the prefix-sets with the new Cilium locators.

1. From the *`topology-host`* vm ssh to *`xrd14`* and *`xrd15`*, go into *`config t`* mode and update the *`cilium-locs`* prefix-set on each router. This will result in the cilium locators being advertised into the ISIS DC instance:
```
ssh cisco@clab-cilium-srv6-xrd14
ssh cisco@clab-cilium-srv6-xrd15
```

2. show the routers' prefix-set running config
```
show running-config prefix-set cilium-locs
```
Example:
```
RP/0/RP0/CPU0:xrd15#show running-config prefix-set cilium-locs
Mon Aug 19 15:25:07.379 UTC
prefix-set cilium-locs
  fc00:0:12c::/48,
  fc00:0:173::/48
end-set
```

3. update the prefix-set to use Cilium's current locators
```
conf t
```
```
prefix-set cilium-locs
 fc00:0:15b::/48,
 fc00:0:134::/48
end-set
commit
```

4. Exit xrd14 and xrd15 then ssh into upstream *`xrd12`* and verify the cilium locator prefixes appear in its ISIS routing table.
```
ssh cisco@clab-cilium-srv6-xrd12
show route ipv6
or
show isis ipv6 route
```

  Example truncated output:
  ```
  RP/0/RP0/CPU0:xrd12#show route ipv6
  Fri Aug 30 22:16:51.975 UTC

  Codes: C - connected, S - static, R - RIP, B - BGP, (>) - Diversion path
        D - EIGRP, EX - EIGRP external, O - OSPF, IA - OSPF inter area
        N1 - OSPF NSSA external type 1, N2 - OSPF NSSA external type 2
        E1 - OSPF external type 1, E2 - OSPF external type 2, E - EGP
        i - ISIS, L1 - IS-IS level-1, L2 - IS-IS level-2
        ia - IS-IS inter area, su - IS-IS summary null, * - candidate default
        U - per-user static route, o - ODR, L - local, G  - DAGR, l - LISP
        A - access/subscriber, a - Application route
        M - mobile route, r - RPL, t - Traffic Engineering, (!) - FRR Backup path

  Gateway of last resort is not set

  <snip>

  i L2 fc00:0:134::/48 
        [115/1] via fe80::a8c1:abff:fe89:3b69, 00:00:11, GigabitEthernet0/0/0/3
  i L2 fc00:0:15b::/48 
        [115/1] via fe80::a8c1:abff:feb1:78d6, 00:02:30, GigabitEthernet0/0/0/2

  ```

  Note: per the topology diagrams above *`xrd01`* and *`xrd02`* are members of the simulated Core/WAN network. The WAN is running a separate ISIS instance and BGP ASN from the small DC hosting our K8s VMs. In this network we have the ability to extend our K8s/Cilium SRv6 L3VPNs beyond the DC/WAN domain boundary to remote PE nodes in simulation of a multi-domain service provider or large Enterprise. Most of the XRd nodes already have their SRv6 L3VPN / BGP configs in place, however, the appendix section of this lab includes steps to configure a VRF and connected loopback interface on *`xrd08`* and join it to one of the Cilium L3VPN instances.

5. Verify VRF Blue is preconfigured on *`xrd10`* in the local ISIS DC domain, and *`xrd02`* which is in the external WAN domain

  Example on *`xrd10`* (these steps can be repeated on *`xrd02`* while specifying bgp 65000)
  ```
  ssh cisco@clab-cilium-srv6-xrd10

  show run interface Loopback12  
  show run router bgp 65010 vrf blue
  ```

  In the bgp vrf blue output we should see *`redistribute connected`*, which means the router is advertising its loopback12 prefix into the SRv6 L3VPN VRF.

6. ssh into the *`k8s-cp-node00`* and then exec into a bluepod container. Ping *`xrd10's`* vrf-blue interface, then ping *`xrd02's`* vrf-blue interface:
```
kubectl exec -it bluepod0 -n blue -- sh
ping 10.10.1.1 -i .3 -c 4
ping 10.12.0.1 -i .3 -c 4
```

  Expected output:
  ```
  / # ping 10.10.1.1 -i .3 -c 4
  PING 10.10.1.1 (10.10.1.1): 56 data bytes
  64 bytes from 10.10.1.1: seq=0 ttl=253 time=3.889 ms
  64 bytes from 10.10.1.1: seq=1 ttl=253 time=3.989 ms
  64 bytes from 10.10.1.1: seq=2 ttl=253 time=3.792 ms
  64 bytes from 10.10.1.1: seq=3 ttl=253 time=3.767 ms

  --- 10.10.1.1 ping statistics ---
  4 packets transmitted, 4 packets received, 0% packet loss
  round-trip min/avg/max = 3.767/3.859/3.989 ms
  / # ping 10.12.0.1 -i .3 -c 4
  PING 10.12.0.1 (10.12.0.1): 56 data bytes
  64 bytes from 10.12.0.1: seq=0 ttl=253 time=5.140 ms
  64 bytes from 10.12.0.1: seq=1 ttl=253 time=5.897 ms
  64 bytes from 10.12.0.1: seq=2 ttl=253 time=5.556 ms
  64 bytes from 10.12.0.1: seq=3 ttl=253 time=5.342 ms

  --- 10.12.0.1 ping statistics ---
  4 packets transmitted, 4 packets received, 0% packet loss
  round-trip min/avg/max = 5.140/5.483/5.897 ms
  / # 
  ```

### You have completed the Cilium-SRv6 lab, huzzah!

## Appendix 1: other Useful Commands
The following commands can all be run from the k8s-cp-node00:

1. Self explanatory Cilium BGP commands:
```
cilium bgp routes advertised ipv4 mpls_vpn 
cilium bgp routes available ipv4 mpls_vpn
cilium bgp routes available ipv4 unicast
cilium bgp routes available ipv6 unicast
```

2. Isovalent/Cilium/eBPF commands:

  Get VRF info:
  ```
  kubectl get isovalentvrf -o yaml
  ```

  Get SRv6 Egress Policy info (SRv6 L3VPN routing table):
  ```
  kubectl get IsovalentSRv6EgressPolicy
  kubectl get IsovalentSRv6EgressPolicy -o yaml
  ```
  Get detail on a specific entry:
  ```
  kubectl get IsovalentSRv6EgressPolicy bgp-control-plane-16bbd4214d4e691ddf412a6a078265de02d8cff5a3c4aa618712e8a1444477a9 -o yaml
  ```

  Get Cilium eBPF info for SID, VRF, and SRv6 Policy - note: first run kubectl get pods to get the cilium agent pod names:
  ```
  cisco@k8s-cp-node00:~$ kubectl get pods -n kube-system
  NAME                                    READY   STATUS    RESTARTS      AGE
  cilium-97pz8                            1/1     Running   0             20m
  cilium-kxdcd                            1/1     Running   0             20m
  ```

  Then run cilium-dbg ebpf commands:
  The first command outputs the nodes' local SID table
  The second command outputs the nodes' local VRF table
  The third command outputs a summary of the nodes' srv6 l3vpn routing table
  ```
  kubectl exec -n kube-system cilium-97pz8 -- cilium-dbg bpf srv6 sid
  kubectl exec -n kube-system cilium-97pz8 -- cilium-dbg bpf srv6 vrf
  kubectl exec -n kube-system cilium-97pz8 -- cilium-dbg bpf srv6 policy
  ```

  Example output:
  ```
  cisco@k8s-cp-node00:~$ kubectl exec -n kube-system cilium-97pz8 -- cilium-dbg bpf srv6 sid
  Defaulted container "cilium-agent" out of: cilium-agent, config (init), mount-cgroup (init), apply-sysctl-overwrites (init), mount-bpf-fs (init), wait-for-node-init (init), clean-cilium-state (init), install-cni-binaries (init)
  SID                VRF ID
  fc00:0:12d:2f3::   1000012
  cisco@k8s-cp-node00:~$ kubectl exec -n kube-system cilium-kxdcd -- cilium-dbg bpf srv6 sid
  Defaulted container "cilium-agent" out of: cilium-agent, config (init), mount-cgroup (init), apply-sysctl-overwrites (init), mount-bpf-fs (init), wait-for-node-init (init), clean-cilium-state (init), install-cni-binaries (init)
  SID                 VRF ID
  fc00:0:12c:8d1d::   1000012
  cisco@k8s-cp-node00:~$ 
  ```

  Get Cilium global config:
  ```
  kubectl get configmap -n kube-system cilium-config -o yaml
  ```

## Appendix 2: Notes, Other

1.  helm uninstall
```
helm uninstall cilium -n kube-system
```

2.  helm list
```
cisco@k8s-cp-node00:~/cilium$ helm list -n kube-system
NAME  	NAMESPACE  	REVISION	UPDATED                              	STATUS  	CHART        	APP VERSION
cilium	kube-system	1       	2024-08-13 21:30:50.1523314 -0700 PDT	deployed	cilium-1.15.6	1.15.6    
```

#### Changing the locator pool
May cause Cilium's eBPF SRv6 programming to fail (the features are currently beta)

```
cisco@k8s-cp-node00:~/cilium$ kubectl apply -f loc-pool-test.yaml 
isovalentsrv6locatorpool.isovalent.com/pool0 created
cisco@k8s-cp-node00:~/cilium$ kubectl get IsovalentSRv6EgressPolicy -o yaml
apiVersion: v1
items: []
kind: List
metadata:
  resourceVersion: ""
```
The workaround appears to be uninstall then reinstall Cilium

### eBGP host-to-ToR
If locatorLenBits: 48 then
1. On ToR create static route to host locator /48, redistribute into ISIS

If locatorLenBits: 64 then:

2. set functionLenBits to 32
   
3. on ToR create static route to host locator /64 and static route to locator /128, redistribute into ISIS
Example:
```
router static
 address-family ipv6 unicast
  fc00:0:4000::/128 2001:db8:18:44:5054:60ff:fe01:a008
  fc00:0:4000:2b::/64 2001:db8:18:44:5054:60ff:fe01:a008
```

Note: if the ToR/DC domain has an eBGP relationship with other outside domains (WAN, etc.) BGP IPv6 unicast will advertise the /64 locator networks out, but the /128 won't appear in DC BGP without some other redistribution (static /128 into DC BGP?). 

## Appendix 3: configure VRF blue on xrd08
Note: as of August 30, 2024 this section is under construction

1. From *`topology-host`* ssh to *`xrd08`*
```
ssh cisco@clab-cilium-srv6-xrd08
```

2. Go into *`conf t`* mode and apply VRF config:
  ```
  conf t

  vrf blue
  address-family ipv4 unicast
    import route-target
    12:12
    !
    export route-target
    12:12
    !
  !
  address-family ipv6 unicast
    import route-target
    12:12
    !
    export route-target
    12:12
    !
  !
  !
  interface Loopback12
  vrf blue
  ipv4 address 10.12.8.1 255.255.255.0
  !
  router bgp 65000
  vrf blue
    rd auto
    address-family ipv4 unicast
    segment-routing srv6
      alloc mode per-vrf
    !
    redistribute connected

  commit
  ```
