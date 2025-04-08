# Cilium SRv6 Lab Quick Demo

cluster00
```
cilium bgp peers
cilium bgp peers --node cluster00-wkr00
cilium bgp routes available ipv6 unicast
cilium bgp routes available ipv4 mpls_vpn

kubectl get pods -A
kubectl exec -it -n blue blue0 -- /bin/sh
```

cluster01
```
cilium bgp peers
cilium bgp peers --node cluster01-wkr00
cilium bgp routes available ipv6 unicast
cilium bgp routes available ipv4 mpls_vpn


```

xrd09
```
show bgp vpnv4 uni rd 1001:1 10.100.1.0/24
```

xrd13
```
show bgp vpnv4 uni rd 1002:1 10.200.0.0/24
```

