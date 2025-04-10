# Cilium SRv6 Lab Quick Demo

cluster00
```
cilium bgp peers
cilium bgp peers --node cluster00-wkr00
cilium bgp routes available ipv6 unicast
cilium bgp routes available ipv4 mpls_vpn

kubectl get pods -A
kubectl exec -it -n blue blue0 -- /bin/sh
ip a
ping 10.200.1.253
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
show bgp vpnv4 uni rd 1001:0 10.100.1.0/24
```

xrd13
```
show bgp vpnv4 uni rd 1002:0 10.200.0.0/24
```

### Cilium commands:
```
cilium bgp peers
cilium bgp peers --node cluster01-wkr00
cilium bgp routes available ipv6 unicast
cilium bgp routes available ipv4 mpls_vpn

kubectl get sidmanager cluster01-cp -o yaml
kubectl get sidmanager cluster01-wkr00 -o yaml

kubectl get pod -n blue bluepod0 -o=jsonpath="{.status.podIPs}"

kubectl get IsovalentSRv6EgressPolicy -o yaml
kubectl get isovalentvrf -o yaml

kubectl get pods -n kube-system | grep cilium

kubectl exec -n kube-system cilium-svscc -- cilium-dbg bpf srv6 sid -o yaml
kubectl exec -n kube-system cilium-svscc -- cilium-dbg bpf srv6 policy -o yaml

```