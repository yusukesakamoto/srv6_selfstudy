#!/bin/bash

# create each node
ip netns add host1
ip netns add router1
ip netns add router2
ip netns add host2

# create the link between host1 and router1
ip link add eth0 netns host1 type veth peer name e0 netns router1

# create the link between router1 and router2
ip link add e1 netns router1 type veth peer name e0 netns router2

# create the link between router2 and host2
ip link add e1 netns router2 type veth peer name eth0 netns host2

# create vrf10
# - create vrf10
# - create the link between router1 and vrf10
# - create the vlan interface ens33.10 on the physical interface ens33
# - attach ens33.10 and veth0 to vrf10
ip link add dev vrf10 type vrf table 10
ip link add e2 netns router1 type veth peer name veth0
ip link add link ens33 name ens33.10 type vlan id 10
ip link set dev ens33.10 master vrf10
ip link set dev veth0 master vrf10

# create vrf20
# - create vrf20
# - create the link between router2 and vrf20
# - create the vlan interface ens33.20 on the physical interface ens33
# - attach ens33.20 and veth1 to vrf20
ip link add dev vrf20 type vrf table 20
ip link add e2 netns router2 type veth peer name veth1
ip link add link ens33 name ens33.20 type vlan id 20
ip link set dev ens33.20 master vrf20
ip link set dev veth1 master vrf20

# set each interface up (host1, router1, router2, host2)
ip netns exec host1 ip link set lo up
ip netns exec host1 ip link set eth0 up
ip netns exec router1 ip link set e0 up
ip netns exec router1 ip link set e1 up
ip netns exec router1 ip link set e2 up
ip netns exec router2 ip link set e0 up
ip netns exec router2 ip link set e1 up
ip netns exec router2 ip link set e2 up
ip netns exec host2 ip link set lo up
ip netns exec host2 ip link set eth0 up

# set each interface up (vrf10, vrf20)
ip link set dev vrf10 up
ip link set dev vrf20 up
ip link set veth0 up
ip link set veth1 up
ip link set dev ens33.10 up
ip link set dev ens33.20 up

# set the ip addresses for each interface
ip netns exec host1 ip -6 addr add 2001:db8:a::a/48 dev eth0
ip netns exec router1 ip -6 addr add 2001:db8:a::b/48 dev e0
ip netns exec router1 ip -6 addr add 2001:db8:b::c/48 dev e1
ip netns exec router1 ip -6 addr add 2001:db8:3::2/48 dev e2
ip netns exec router2 ip -6 addr add 2001:db8:b::d/48 dev e0
ip netns exec router2 ip -6 addr add 2001:db8:c::e/48 dev e1
ip netns exec router2 ip -6 addr add 2001:db8:4::2/48 dev e2
ip netns exec host2 ip -6 addr add 2001:db8:c::f/48 dev eth0

# allow ip forwarding on router1, router2
ip netns exec router1 sysctl -w net.ipv6.conf.all.forwarding=1
ip netns exec router2 sysctl -w net.ipv6.conf.all.forwarding=1


# set ip addresses for each interfaces
ip -6 addr add dev ens33.10 2001:db8:1::1/48
ip -6 addr add 2001:db8:3::1/48 dev veth0
ip -6 addr add dev ens33.20 2001:db8:2::1/48
ip -6 addr add 2001:db8:4::1/48 dev veth1

# start frr
systemctl start frr
/usr/lib/frr/frrinit.sh start "router1"
/usr/lib/frr/frrinit.sh start "router2"

# wait 30 seconds until completing ospf6 routing table
sleep 30

# allow ip forwarding and SRv6 forwarding on vrf10, vrf20
sysctl -w net.ipv6.conf.all.forwarding=1
sysctl -w net.ipv6.conf.all.seg6_enabled=1

# set default gw to host1, host2
ip netns exec host1 ip -6 route add default via 2001:db8:a::b
ip netns exec host2 ip -6 route add default via 2001:db8:c::e

# set SRv6 routing tables
ip netns exec router1 ip -6 route add 2001:db8:c::/48 encap seg6 mode encap segs 2001:db8:1::1,2001:db8:2::1 dev e2
ip -6 route del local 2001:db8:1::1 dev ens33.10 table 10
ip -6 route del local 2001:db8:2::1 dev ens33.20 table 20
ip -6 route add 2001:db8:1::1 encap seg6local action End dev ens33.10 table 10
ip -6 route add 2001:db8:2::1 encap seg6local action End.DX6 nh6 :: dev ens33.20 table 20
