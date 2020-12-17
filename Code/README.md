# Service Specific Routing
This repository contains segment routing capabilities, BGP advertised prefixes with large community
attributes, IPv6 addressing, and OSPF functionality. Everything has been manually scripted, so there
is no need to enable anything, besides running the profile on POWDER/EMULAB. 

#### The Topology
![Topology][topo]

[topo]: figs/3ASFig.png "Title Text"


#### Editing the Topology
Currently the network topology contains 3 ASes, each of which contains 4 routers and 2 hosts. The routers in
each AS can be described as a 'full mesh.' To edit the network topology open the [`ammon.py`](ammon.py) python file.
At about line 141 you will find the nodemap dictionary. The nodemap dictionary is used associate a node
with a physical machine. For example '7':1, tells us that node-7 will be added to vhost1. You will also
need to edit the mgmtmap dictionary. The mgmtmap is used to associate a node name with a node number.
For example 'co':15, means that node-co can be uniquely identified as number 15. Scrolling a bit lower
you will find the prefix variables. If you are looking to add or change current prefix addressing this 
is the section. Next you will find the addrs dictionary, this contains the interface addressing of the 
two respective nodes. For example, note that "node-5-11":0x15, and "node-11-5":0x16 are both on the 
same /126 IPv6 subnet mask, and connect both node-5 and node-11 together. To add a new connection
amoungst nodes you will need to use a /126 IPv6 subnet mask that has not been already used. Finally,
if you are looking to change the AS addressing you will need to update the lines of code around line
361 that mentions "AS Prefix Assignment." Here is where each node is assigned an AS prefix.

#### Editing BGP Configuration
If you updated/changed the network topology and want BGP advertisements to work you will need 
to update the BGP configuration files. Note, that you can create '.conf' files in the '/etc/frr' directory or use the
VTYSH console to configure the routers. I will show you 2 examples to familiarize yourself with BGP 
configuration files. Note that all the routing in this topology is being done through FRR, and further
information can be found [here](http://docs.frrouting.org/en/latest/index.html). Now in the [`setup-frr.sh`](setup-frr.sh) script file, you will find where all the FRR routing configuration is done. Note that at 
about line 22 to line 36 the Zebra daemon is being configured. Then at about line 38 to line 61 OSPF
is being configured. [BGP configuration](http://docs.frrouting.org/en/latest/bgp.html) is specific to whatever your needs are. Starting at line 65 you will
see node-cb (gateway router) BGP configuration, also located below. 
```
router bgp 1
 neighbor 2620:7c:d000:ffff::1 remote-as 1
 neighbor 2620:7c:d000:ffff::1d remote-as 1
 neighbor 2620:7c:d000:ffff::25 remote-as 1
 neighbor 2620:7c:d000:ffff::5a remote-as 2
 !
 address-family ipv6 unicast
  neighbor 2620:7c:d000:ffff::1 activate
  neighbor 2620:7c:d000:ffff::1d activate
  neighbor 2620:7c:d000:ffff::25 activate
  neighbor 2620:7c:d000:ffff::5a activate
 exit-address-family
```
You will notice a few unfamiliar commands. First you will notice the `router bgp 1` command.
This command is used to establish the AS number associated with the router. Because node-cb is located
at AS1 the ASN is 1. However, if the node was located at lets say AS3 then the the number would be 3 instead
of 1. Next the `neighbor 2620:7c:d000:ffff::1 remote-as 1` command tells us that the neighbor at IPv6
address 2620:7c:d000:ffff::1 is located at AS1. Contrast this to the `neighbor 2620:7c:d000:ffff::5a remote-as 2`
which tells us that the neighbor with the IPv6 address 2620:7c:d000:ffff::5a is located at AS2. This helps 
BGP establish an iBGP session if the neighbor is within the AS or a eBGP session if the neighbor is located
outside the AS. In the `address-family ipv6 unicast` section of the BGP configuration file, we are telling BGP
that we would like to activate receiving IPv6 prefix from those neighbors specified in that section. Below you will find the BGP configuration file for node-11 located at AS2.
```
route-map SSR permit 10
 set large-community 2:1:3
!
router bgp 2
 neighbor 2001:db8:a0b:12f0::15 remote-as 2
 neighbor 2001:db8:a0b:12f0::2e remote-as 2
 neighbor 2001:db8:a0b:12f0::3a remote-as 2
 !
 address-family ipv6 unicast
  network 2001:db8:a0b:12f0::4c/126
  neighbor 2001:db8:a0b:12f0::15 activate
  neighbor 2001:db8:a0b:12f0::15 route-map SSR out
  neighbor 2001:db8:a0b:12f0::2e activate
  neighbor 2001:db8:a0b:12f0::2e route-map SSR out
  neighbor 2001:db8:a0b:12f0::3a activate
  neighbor 2001:db8:a0b:12f0::3a route-map SSR out
 exit-address-family
```
We can see some significant differences
from the first example. The biggest difference is that at node-11 we are advertising a prefix. But first notice the
`route-map SSR permit 10` section. In this section we are creating a route map called SSR with sequence number 10, 
for our purposes the permit number is not important but the `set large-community 2:1:3` command is. In this command
we are setting the [large community attribute](https://tools.ietf.org/html/rfc8092) for this router to advertise along side a prefix. We are now familiar with the `router bgp 2` command but notice that the ASN is different. This is because we are now in AS2. In the `address-family ipv6 unicast` section you will notice two new commands. The `network 2001:db8:a0b:12f0::4c/126` is the IPv6 prefix that we would like to advertise. While the `neighbor 2001:db8:a0b:12f0::15 route-map SSR out` command is telling BGP that we would like to advertise our prefix as well as the large community attribute to our neighbor at IPv6 address 2001:db8:a0b:12f0::15. The remaining BGP configuration files you will find in the [`setup-frr.sh`](setup-frr.sh) are very similar to the two above, the differences relate to IPv6 neighbors, large community attributes, and the prefix we would like to advertise. 

#### Using VTYSH and Navigating FRR
The [VTYSH](http://docs.frrouting.org/projects/dev-guide/en/latest/vtysh.html) is a shell for FRR daemons. I will provide a few commands that I found usefully for using VTYSH and navigating the FRR directory. First, after you create an experiment from this profile, or have create a different experiment with FRR installed I recommend running the command below. This command gives you super user capabilities. 
```
sudo -s
```  
Next, navigate to the FRR directory. Here you will find all things FRR. Most importantly you will find the daemon configuration files, and the daemon file.
```
cd /etc/frr
```
In the FRR directory, running the command below gives you access to turning on and turning off routing daemons. [Vim](https://www.keycdn.com/blog/vim-commands) is a commandline editor that allows you to view and change files.
```
vim daemons
```
In my profile you should see the bgpd.conf, zebra.conf, and ospf6d.conf files. Using the commands below will gain you access to viewing the respective .conf files. Notice that these files are the files created in the [`setup-frr.sh`](setup-frr.sh) script.
```
vim bgpd.conf
vim zebra.conf
vim ospf6d.conf
```
Now lets say you decided to change the OSPF configuration file, you will now need restart frr. Once you restart, everything should be running smoothly depending on what you decided to change...
```
systemctl restart frr
```
By default FRR is enabled. But if you need the command here it is.
```
systemctl enable frr
```

Now, a quick introduction to VTYSH.
I founded it easier to run configuration commands using the VTYSH then copying the BGP commands to the script. To get started on the VTYSH in the '/etc/frr' directory run this command.
```
vtysh
```
The shell will come up and now you are using the VTYSH. You can run the command below to view the current FRR configuration that is configured on the router. You will get output that is a combination of the zebra, bgpd, and ospf6d.conf files all together. 
```
show running-config
```
If you would like to configure the router using the VTYSH run the command below. Now you're in configuration mode and depending on what you would like to do, you can now configure accordingly. 
```
config
```
Note: to configure using the VTYSH just like in the example below, you need to remove the bgpd.conf file, and restart FRR. Now lets say you are in node-cb and after running the `vtysh` command, you run the `config` command above. To configure BGP just like in the script you can simply copy and paste the script BGP configuration into the vtysh and you are done. But if you would like to do it by [hand](https://www.cisco.com/c/en/us/td/docs/ios-xml/ios/ipv6/command/ipv6-cr-book/ipv6-r1.html) you can simply type the commands in line by line. The configuration commands for the VTYSH are identical to the .conf files. 

To view the IPv6 BGP content of the prefixes acquired from the neighbors you can run the commands below in the VTYSH. 
```
show bgp sum
show bgp
show bgp <prefix advertised>
```
If you are done with the VTYSH you can type the command below until you return to the '/etc/frr' directory. 
```
exit
```

#### Segment Routing Commands
These commands can simply be run in the commandline of whichever node you SSH into.

Adding Routing Rule
```
sudo ip -6 route add <DST> dev <INTERFACE> encap seg6 mode inline segs <SG1,...,SGN> 
EX:
sudo ip -6 route add 2620:7c:d000:ffff::4d dev eth2 encap seg6 mode inline segs 2620:7c:d000:ffff::2
```
Deleting Routing Rule
```
sudo ip -6 route del <DST> dev <INTERFACE> encap seg6 mode inline segs <SG1,...,SGN>
EX:
sudo ip -6 route del 2620:7c:d000:ffff::4d dev eth2 encap seg6 mode inline segs 2620:7c:d000:ffff::2
```

#### Helpful Commands
TCPDUMP Command for inline viewing of packets
```
sudo tcpdump -i <INTERFACE> -v
EX:
sudo tcpdump -i eth2 -v
```
TCPDUMP Capture Command to save packets to a file for Wireshark viewing 
```
sudo tcpdump -i <INTERFACE> -v -w <FILEPATH>
EX:
sudo tcpdump -i eth2 -v -w /tmp/foo.pcap
```

Copy Wireshark file to PC for (fast/easy) Wireshark viewing. This command is run on your own PC.
```
scp -o Port=<PORT#> <SSH LOCATION>:<FILEPATH> .
EX: 
scp -o Port=27602 Jmon@pc827.emulab.net:/tmp/foo.pcap .
```

Showing IPv6 Routing Table
```
ip -6 route show
```
Showing IPv6 Routing Table with Filtration. Here the KEYWORD in the grep example can be `seg6` to quickly find segmentation routing routes. Or in the 'get' example the KEYWORD can be an IPv6 destination like `2620:7c:d000:ffff::2` to find all IPv6 routing rules associated with that IPv6 address.
```
ip -6 route | grep <KEYWORD>
Ip -6 route get <KEYWORD>
EX:
ip -6 route | grep seg6
ip -6 route get 2620:7c:d000:ffff::2
```

IPv6 Ping Command
```
ping6 -c <# OF PKTS> <DST>
EX:
ping6 -c 1 node-11se-11
```

Find Topology Hosts (Great For DST Lookup). Here the PATTERN can be anything you are trying to search for.
```
less /etc/hosts
Searching Forward:
/<PATTERN>
Searching Backward:
?<PATTERN>
```

Troubles with Virtual Machines loading you can check the log file. Can be run from any VM
```
/root/setup/setup.log
```

Connectivity Test. Checks the status of the whole topology. Can be run from any VM
```
/local/repository/linktest.pl
```