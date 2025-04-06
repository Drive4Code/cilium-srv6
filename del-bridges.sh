#!/bin/bash

 ip link set down xrd03-inet
 ip link set down xrd04-inet
 ip link set down k8s-cp
 ip link set down k8s-wkr00
 ip link set down k8s-wkr01
 ip link set down k8s-wkr02

 brctl delbr xrd03-inet
 brctl delbr xrd04-inet
 brctl delbr k8s-cp
 brctl delbr k8s-wkr00
 brctl delbr k8s-wkr01
 brctl delbr k8s-wkr02
