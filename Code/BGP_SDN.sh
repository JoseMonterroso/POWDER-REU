#!/bin/bash
# SDN Script - 
# Gets Advertised BGP prefix, and Large community attribute, 
# and Associates a SRH with each BGP prefix that has a large
# community attribute  

# Get to VTYSH Shell
cd /etc/frr

# Gets the Large Community Attribute of a Prefix
GET_LC(){
        while IFS=' ' read -ra line; do
                for LCA in "${line[@]}"; do
                        if [[ $LCA =~ ^[0-9]+\:[0-9]+\:[0-9]+ ]]; then
                                echo "$LCA"
                                break 2
                        fi
                done
        done < <(vtysh -c "show bgp $1")
}


# Push Segment Routing Rule
# NODE 10 SDN
GET_SRH(){
    if [[ "$1" == "2:1:1" ]]; then
         sudo ip -6 route add 2001:db8:a0b:12f0::62 dev eth4 encap seg6 mode inline segs 2620:7c:d000:ffff::21,2620:7c:d000:ffff::1e
         echo "7,cb"
    elif [[ "$1" == "2:1:3" ]]; then
         sudo ip -6 route add 2001:db8:a0b:12f0::4d dev eth2 encap seg6 mode inline segs 2620:7c:d000:ffff::29,2620:7c:d000:ffff::26
         echo "8,cb"
    elif [[ "$1" == "3:4:4" ]]; then
         sudo ip -6 route add 3000:63b:3ff:fdd2::8a dev eth1 encap seg6 mode inline segs 2620:7c:d000:ffff::2
        echo "cb"
    elif [[ "$1" == "3:1:1" ]]; then
sudo ip -6 route add 3000:63b:3ff:fdd2::8e dev eth4 encap seg6 mode encap segs 2620:7c:d000:ffff::21,2620:7c:d000:ffff::e,2620:7c:d000:ffff::26,2620:7c:d000:ffff::59
        echo "7,8,cb"
     else
             echo " "
    fi
}

# Table Header
printf '%s\n' "___________________________________________"
printf '%s\n' "|           Prefix          |  LCA  | SRH |"
printf '%s\n' "-------------------------------------------"

# Gets all advertised Prefixes and outputs table
while IFS=' ' read -r line; do
        if [[ $line =~ ^i[0-9]+ ]]; then
                PRE=$(echo $line | sed -r 's/^.{1}//')
                LCA=$(GET_LC "$PRE")
                if [[ "$LCA" == "::" ]]; then
                        temp=2 # Place Holder   
                else
                        SRH=$(GET_SRH $LCA)
                        if [[ "$SRH" != " " ]]; then
                                printf '| %-10s | %s | %s |\n' "$PRE" "$LCA" "$(GET_SRH $LCA)"
                        fi
                fi
        fi
done < <(vtysh -c "show bgp")
printf '%s\n' "-------------------------------------------"