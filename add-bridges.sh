#!/bin/bash

 brctl addbr xrd03-inet
 brctl addbr xrd04-inet
 brctl addbr k8s-cp
 brctl addbr k8s-wkr00
 brctl addbr k8s-wkr01
 brctl addbr k8s-wkr02

 ip link set up xrd03-inet
 ip link set up xrd04-inet
 ip link set up k8s-cp
 ip link set up k8s-wkr00
 ip link set up k8s-wkr01
 ip link set up k8s-wkr02
