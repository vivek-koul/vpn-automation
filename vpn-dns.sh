#!/bin/bash
# OpenVPN DNS update script for macOS

SCUTIL=/usr/sbin/scutil

case "$script_type" in
    up)
        declare -a dns_servers
        declare -a dns_domains

        for opt in ${!foreign_option_*}; do
            val="${!opt}"
            case "$val" in
                *DNS\ *)    dns_servers+=("${val##* }") ;;
                *DOMAIN\ *) dns_domains+=("${val##* }") ;;
            esac
        done

        if [ ${#dns_servers[@]} -gt 0 ]; then
            $SCUTIL <<-EOF
				d.init
				d.add ServerAddresses * ${dns_servers[*]}
				d.add SupplementalMatchDomains * ${dns_domains[*]}
				d.add SupplementalMatchDomainsNoSearch # 1
				set State:/Network/Service/openvpn/DNS
			EOF
        fi
        ;;

    down)
        $SCUTIL <<-EOF
			remove State:/Network/Service/openvpn/DNS
		EOF
        ;;
esac
