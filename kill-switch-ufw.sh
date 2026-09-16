#!/usr/bin/env bash
# shellcheck disable=2059

if [[ $EUID -ne 0 ]]; then
   printf "%s\n" "This script must be run as root"
    exit 1
fi

#----------------------------------------------------------------------#
BASE_DIR="$( dirname "$( realpath "${BASH_SOURCE[0]}" )" )"
SERVICE="kill-switch-ufw-reset.service"
readonly BASE_DIR SERVICE

DEBUG="OFF"
DEBUG_TOUT="OFF"
DEBUG_FILE="$(xdg-user-dir DESKTOP)/ksufw-debug.log"
readonly DEBUG DEBUG_TOUT DEBUG_FILE

readonly GREEN="\033[38;5;46m"
readonly RED="\033[38;5;160m"
readonly CYAN="\033[38;5;43m"
readonly YELLOW="\033[38;5;184m"
readonly NC='\033[0m'


COLS="$(tput cols)"
readonly COLS
readonly HPA_A=$(( COLS / 20 ))
readonly STEP=$((  COLS / 3 ))
readonly HPA_B=$((  HPA_A + STEP ))
readonly HPA_C=$(( HPA_A + 2 * STEP ))

#----------------------------------------------------------------------#
Debug(){
	[[ "$DEBUG" == "ON" ]] || return 0 # redundant 
	declare -F "${BASH_COMMAND%% *}" > /dev/null || return 0
	
	printf "Funktion: %s | PID: %s\n" "${FUNCNAME[*]:-main}" "$BASHPID" > "$DEBUG_FILE"
	
	if [[ "$DEBUG_TOUT" == "ON" ]]; then
		printf "\n%s\n" "Funktion: ${FUNCNAME[*]}"
		printf "%s\n" "PID: $BASHPID"
	fi
}

DebugTrapFilter(){
	[[ "${BASH_COMMAND%% *}" == *=* ]] && return 1
	declare -F -- "${BASH_COMMAND%% *}" >/dev/null
	}
	
#-----------------------------------------------------------------------
GetSysLang(){
	local lang
	lang="${LANG%%_*}"
	printf "%s\n" "${lang,,}"
}

SetLang(){
	local lang
	lang="$(GetSysLang)"
	if [[ "$(locale charmap 2>/dev/null)" == "UTF-8" ]]; then
		case "$lang" in
			de*) lang="de" ;;
			en*) lang="en" ;;
			fr*) lang="fr" ;;
			es*) lang="es" ;;
			it*) lang="it" ;;
			pl*) lang="pl" ;;
			zh*) lang="zh" ;;
			ru*) lang="ru" ;;
			hi*) lang="hi" ;;
			*)   lang="en" ;;
		esac
	else
		lang="en"
	fi
	printf "%s\n" "$lang"
	
}

VarsEnv(){
	compgen -A variable | LC_ALL=C sort -u | paste -sd '|'
}

LoadConfig() {
    local file="$1"
    local line
    local key
    local value
	local sysv
	
	sysv="$( VarsEnv )"
    while IFS= read -r line || [[ -n "$line" ]]; do
        
        # skip comments and empty lines
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
		
		
        #force key = value
        if [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*) ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            
            #Prevent overriding env vars
			if [[ "$sysv" =~ \|$key\| ]]; then
				Wuff "CRITICAL:" "$YELLOW"
				Wuff "Config file $file trys to override envoironment variable: $key" "$RED"
				exit 1
			fi
            
			#delete quotes from values
            value="${value%\"}"
            value="${value#\"}"
			
			printf -v "$key" "%s" "$value"
        else
            Wuff "Invalid config line: $line" "$YELLOW"
            exit 1
        fi 
    done < "$file"
  }
  
  DepCheck(){
	local dep="$1"
	if ! command -v "$dep" > /dev/null; then
		return 1
	fi
}

RequiredSystemd(){
	command -v systemctl &> /dev/null
	}


#----------------------------------------------------------------------#

Woof(){
	local char="$1"
	local color="$2"
	local nc=""
	
	[[ -z "$output_fd" ]] && exec {output_fd}>&1 
	
	printf "%s$color" "" >&"$output_fd"
	printf "${char}%.0s" $(seq 1 "$( tput cols )" ) >&"$output_fd"
	[[ -n "$color" ]] && nc="$NC" 
	
	printf "%s${nc}\n\n" "" >& "$output_fd"
}

Wuff(){
	local text="$1"
	shift
	local -a pos=("$@")
	local format color nc arf fold
		
	format='%b%b%b\n'
	nc=""
	
	WoofWoof(){
		local wau="$1"
		if [[ "$wau" =~ ^-a ]]; then
			format="${wau/-a/}${format}"
		elif [[ "$wau" =~ ^-e ]]; then
			format="${format/\\n/}${wau/-e/}"
		elif [[ "$wau" =~ ^[0-9]{1,3}$ ]]; then
			tput hpa "$wau"
		elif [[ "$wau" =~ ^\\033 ]]; then
			color="$wau"
			nc="$NC"
		fi
	}
		
	for arf in "${pos[@]}"; do
		WoofWoof "$arf"
	done
	
	if [[ -z "$output_fd" ]]; then
		{ exec {output_fd}>/dev/tty; } 2>/dev/null ||
		exec {output_fd}>/dev/null
	fi
	printf "$format" "$color" "$text" "$nc" >&"$output_fd" 
}

RelHpa(){
	local txt="$1"
	local rel="$2"
	local hpa="$3"
	txt="${#txt}"
	rel="${#rel}"
	
	#(( txt > 3 )) || txt=1
	
	if (( txt < rel )); then
		hpa="$(( hpa + (rel - txt)/2  ))"
	elif (( txt > rel )); then
		hpa="$(( hpa - (txt - rel)/2 ))"
	fi

	printf "%s\n" "$hpa"
}
  
#----------------------------------------------------------------------#  

EndpointIPsec(){
	DepCheck "swanctl" || return 0
	swanctl --list-sas --pretty | awk '
		$1 == "remote-host" { ip = $3 }
		$1 == "remote-port" {
			if (ip ~ /:/) ip = "[" ip "]"
			print ip ":" $3
		}
	'
}
		
EndpointOpenVpn(){
	
    local intf="$1"
    local pid

    while read -r pid; do
        grep -qFx -- $'iff:\t'"$intf" \
            /proc/"$pid"/fdinfo/* 2>/dev/null || continue

        ss -Htunp | awk -v pid="$pid" '
            index($0, "\"openvpn\",pid=" pid ",") {
                print $6
            }
        '
        return
    done < <(pgrep -x openvpn)
}

EndpointWg(){
	local intf="$1"
	DepCheck "wg" || return 0
	wg show "$intf" endpoints 2> /dev/null | awk '{print $2}'
}
	
Endpoint(){
	local intf="$1"
	local mode="$2"
	local ip_port 
	
	mode="${mode:-ip}"
	
	ip_port="$( EndpointWg "$intf" )"
	[[ -z "$ip_port" ]] && ip_port="$(EndpointOpenVpn "$intf")"
	[[ -z "$ip_port" ]] && ip_port="$(EndpointIPsec)"

	if [[ -z "$ip_port" ]]; then
		Wuff "$TXT_NO_ENDP: $intf" "$RED"
		return 1
	fi
	
	
	case "$mode" in
		ip) printf "%s\n" "${ip_port%:*}";;
		port) printf "%s\n" "${ip_port#*:}";;
	esac
} 

#----------------------------------------------------------------------#

RulesGetAll(){
	local line
	local -a output=()
		while IFS= read -r line; do
			output+=("$line")
		done < <( ufw status numbered | grep "kill-switch-ufw")
		printf "%s\n" "${output[@]}"
	}


RulesDelete(){
	local intf="$1"
		RulesGetNumbers "$intf" | 	
		while IFS= read -r rule_number; do
			ufw --force delete "$rule_number" > /dev/null
		done
}

RulesGetNumbers(){
	local pattern="$1"
	pattern="kill-switch-ufw-$pattern"
	
	ufw status numbered |
		awk -F'[][]' -v comment="$pattern" '
			$0 ~ comment ".*$" {
			gsub(/[[:space:]]/, "", $2)
			print $2
		}' |
		sort -rn
	}

RulesDeleteAll(){
	local rule_number
	
	while IFS= read -r rule_number; do
		ufw --force delete "$rule_number" > /dev/null
	done < <( RulesGetNumbers )
}

RulesEndpointException(){
	local intf_vpn
	
	for intf_vpn in $( IntfFind "vpn" ); do
		endp_ip="$( Endpoint "$intf_vpn" "ip" )"
		endp_port="$( Endpoint "$intf_vpn" "port" )"
		
		[[ -n "$endp_ip" && -n "$endp_port" ]] || return 1
		
		ufw allow out on "$intf" to "$endp_ip" port "$endp_port" comment "kill-switch-ufw-$intf-$intf_vpn" >/dev/null
	done
}

#Deny all except Endpoint
RulesParanoid(){
	local intf="$1"
	RulesEndpointException "$intf"
	ufw deny out on "$intf" comment "kill-switch-ufw-${intf}" >/dev/null
}

#Allow Endpoint, Deny DNS, Allow private addresses, Deny All 
RulesStandard(){
	local intf="$1"
	local -a intfs
	
		RulesEndpointException "$intf"
			
		#dns leak prevention (e.g router over private ip )
		ufw deny out on "$intf" to any port 53 comment "kill-switch-ufw-$intf" > /dev/null
		
		ufw allow out on "$intf" to 10.0.0.0/8 comment "kill-switch-ufw-$intf" > /dev/null #private > /dev/null
		ufw allow out on "$intf" to 169.254.0.0/16 comment "kill-switch-ufw-$intf" > /dev/null #apipa
		ufw allow out on "$intf" to 172.16.0.0/12 comment "kill-switch-ufw-$intf" > /dev/null #private/u
		ufw allow out on "$intf" to 192.168.0.0/16 comment "kill-switch-ufw-$intf" > /dev/null #private
		
		ufw deny out on "$intf" comment "kill-switch-ufw-$intf" >/dev/null
}

RulesAdd(){
		local intf="$1"
		local mode="$2"
		 
		case "$mode" in
			standard) RulesStandard "$intf" ;;
			paranoid) RulesParanoid "$intf" ;; 
		esac
	}

#----------------------------------------------------------------------#

#Delivers search patterns for Intf [ethernet,wlan,wwan]
IntfPatterns(){
	local intf="$1"
	case "$intf" in
		eth)  printf '%s\n' '^(eth[0-9]|en(P[0-9]+|[osxpd][0-9a-f]))(?=.*ethernet)';;
		wlan) printf '%s\n' '^(wlan[0-9]|wl(P[0-9]+|[osxpd][0-9a-f]))(?=.*wifi)';; 
		wwan) printf '%s\n' '^(wwan[0-9]|ww(P[0-9]+|[osxpd][0-9a-f]))(?=.*gsm)';;
		vpn)  printf '%s\n' '^(pia[0-9]?|proton[0-9]?|tun[0-9]|nordlynx[0-9]?|wg[0-9](-mullvad[0-9]?)?|tun[xX][0-9]?|vpn[0-9]?)';;
		*) printf "%s\n" "^$intf((?=.*ethernet)|(?=.*gsm)|(?=.*wifi))";;
	esac
}

IntfFind(){
	local intf="$1"
	local mode="$2"
	local -a intfs

	mode="${mode:-name}"
	while read -r line; do
		intfs+=("${line%%:*}")
	done < <( nmcli -t -f DEVICE,TYPE device status | grep -P  "$(  IntfPatterns "$intf" )" ) 

	
	case "$mode" in
		name) printf "%s\n" "${intfs[@]}";;
		count) printf "%s\n" "${#intfs[@]}";; 
	esac	
}

#----------------------------------------------------------------------#

Toggle(){
	local intf="$1"
	local mode="$2"
	local i=0
	local status
	local antidau
	mode="${mode:-standard}"
	
	antidau="$( IntfPatterns "vpn" )"
	[[ "$intf" =~ $antidau ]] && return 1
	
	for intf in $( IntfFind "$intf" ); do
		status="$( Status "$intf" )"
		case "$status" in
			0) RulesAdd "$intf" "$mode";;
			1) RulesDelete "$intf";;
			2) RulesDelete "$intf";;
		esac
	done
}

ToggleService(){
	local status
	
	RequiredSystemd || return 0
	
	status="$( StatusService )"
	
	case "$status" in
		disabled) systemctl enable "$SERVICE" &> /dev/null;;
		enabled) systemctl disable "$SERVICE"&> /dev/null;;
	esac
	
	} 
#----------------------------------------------------------------------#

StatusService(){
	local status
	RequiredSystemd || return 0
	
	status="$( systemctl is-enabled "$SERVICE" )"
	printf "%s\n" "$status"

	if [[ "$status" = "not-found" || -z "$status" ]]; then
		return 1
	fi
}

StatusFirewall(){
	local status
	status="$( env LC_ALL=C LANGUAGE=C ufw status | awk 'NR == 1 { print $2 }' )"
	if [[ "$status" != "active" ]]; then
		Wuff "$( ufw --force enable )" "$YELLOW"
	fi
}

StatusAnyOn(){
	local intf
	
	for intf in "eth" "wlan" "wwan"; do
		intf="$( IntfFind "$intf" )"
		intf="$( Status "$intf" )"
		
		(( intf == 1 )) && return 0
	done
	
	return 1
}
		

StatusIpv6(){
	local ipv
	ipv="$( grep -- "IPV6=" /etc/default/ufw >/dev/null) "
	ipv="${ipv#*=}"
	[[ "${ipv,,}" != no ]]
}

Status(){
	local intf="$1"
	local c_rules
	local pattern
	local para
	local stan
	
	pattern="kill[-]switch[-]ufw[-]$intf\$"
	c_rules="$( ufw status | grep -c -P "$pattern" )"
	
	stan=8
	para=2

	if ! StatusIpv6; then
		stan=6
		para=1
	fi
	
	case "$c_rules" in 
		0) printf "%s\n" "0";; #NO ufw rules are set 
		"$stan") printf "%s\n" "1";; #ufw rules are set ( !- EndpointExceptions)
		"$para") printf "%s\n" "1";; #ufw rules  are set ( !- EndpointExceptions)
		*) printf "%s\n" "2";; #ufw rules are set but some are missing
	esac
	
}

#----------------------------------------------------------------------#

DisplayRules(){
	local rules
	local color
	local line
	local i=0
	Woof "#"
	
	mapfile -t rules < <(RulesGetAll)
	
	for line in "${rules[@]}" ; do
		(( i++ ))
		color=""
		
		(( i % 2 == 0 )) && color="$CYAN"
		Wuff "$line" "$color" 
	done

	[[ -z "$line" ]] && Wuff "$TXT_NO_RULES" "$CYAN" ""
}

DisplayService(){
	local status
	local color
	
	RequiredSystemd || return 0
	
	status="$( StatusService )"
	[[ "$status" == "not-found" ]] && return 0
	
	case "$status" in
		enabled) status="$TXT_OFF"; color="$RED" ;;
		disabled) status="$TXT_ON"; color="$GREEN";;
	esac
	
	if ! StatusAnyOn; then
		color="$RED"
		status="$TXT_OFF"
	fi
	
	Wuff "$TXT_AFTER_REBOOT" \
	"$( RelHpa "${TXT_INTERFACE} $status" "$TXT_STATUS" "$HPA_B")" "-e"
	
	Wuff " $status" "$color"
		
}

DisplayStatusNoIntf(){
		Wuff "--" "$CYAN" \
		"$(RelHpa "--" "$TXT_INTERFACE" "$HPA_B")" "-e"
		
		Wuff "$TXT_NO_INTERFACE_FOUND" "$YELLOW" \
		"$( RelHpa "$TXT_NO_INTERFACE_FOUND" "$TXT_STATUS" "$HPA_C")"
	}

DisplayStatus(){
	local status="$1"
	local intf="$2"
	
	Wuff "$intf" "$CYAN" \
	"$( RelHpa "$intf" "$TXT_INTERFACE" "$HPA_B")" "-e"
	
	if  (( status == 0 )); then
		Wuff "$TXT_OFF" "$RED" \
		"$( RelHpa "$TXT_OFF" "$TXT_STATUS" "$HPA_C")" 
	elif  (( status == 1 )); then
		Wuff "$TXT_ON" "$GREEN" \
		"$( RelHpa "$TXT_ON" "$TXT_STATUS" "$HPA_C" )"  
	elif  (( status == 2 )); then
		Wuff "$TXT_RULES_INCOMPLETE" "$RED" \
		"$( RelHpa "$TXT_RULES_INCOMPLETE" "$TXT_STATUS" "$HPA_C" )"\
		| 
		RulesDelete "$intf"
	elif  (( status == 3 )); then
		Wuff "$TXT_NO_INTERFACE_FOUND" "$YELLOW" \
		"$( RelHpa "$TXT_NO_INTERFACE_FOUND" "$TXT_STATUS" "$HPA_C" )" 
	fi
}

DisplayTypeFromShorcut(){
	local intf="$1"
	case "$intf" in
		eth*|en*) printf "%s\n" "$TXT_ETHERNET";;
		wlan*|wl*) printf "%s\n" "$TXT_WLAN";;
		wwan*|ww*) printf "%s\n" "$TXT_WWAN";;
		*) printf "%s\n" "$intf"
	esac
}

DisplayStatusType(){
		local intf="$1"
		
		Wuff "$( DisplayTypeFromShorcut "$intf" )" "$HPA_A" "-e"
		Wuff "$TXT_INTERFACE" "$HPA_B" "-e"
		Wuff "$TXT_STATUS" "$HPA_C"
	}

DisplayStatusLoop(){
	local intf="$1"
	local status
	
	DisplayStatusType "$intf"
	
	for intf in $( IntfFind "$intf" ); do	
		status="$(Status "$intf")"
		DisplayStatus "$status" "$intf"
	done
	
	if [[ -z "$status" ]]; then
		DisplayStatusNoIntf
	fi
	Wuff
}

DisplayStatusAll(){
	local intf
	
	Wuff; Woof "#" 
	for intf in "eth" "wlan" "wwan"; do
		DisplayStatusLoop "$intf"
	done
	Woof "#"
}

#----------------------------------------------------------------------#

Help(){
	if command -v glow > /dev/null; then
		glow "${DIR_L}/help_${LANGUAGE}.md"
	else
		Woof "#"
		Wuff "KILL-SWITCH-UFW" "$HPA_B"
		cat "${DIR_L}/help_${LANGUAGE}.txt" 
		Woof "#" 
	fi
	exit 0
}

Usage(){
	Wuff "$TXT_USAGE" "$YELLOW"
	exit 0
}

CommandLineOptions(){
	local cli_options=("$@")
	local seen
	
	(( "${#cli_options[@]}" == 0 )) && Usage
	[[ ! "${cli_options[*]}" =~ [-] ]] && Usage
	
	options=$( getopt -o hsa:b:ewvpqxyrz \
	--long help,status,standard:,paranoid:,ethernet,wlan,wwan,paranoid-eth,\
paranoid-wlan,paranoid-wwan,reboot-onoff,rules,delete-rules -- \
	"${cli_options[@]}")
	
	# shellcheck disable=SC2181
	[[ $? == 0 ]] || Usage
	eval set -- "$options"

	while true; do 
		
		if [[ "$1" != "--" ]] && [[ "$seen" =~ .*$1.* ]]; then
			shift
			continue
		fi
		seen="${seen}$1"
		
		case "$1" in
			-h|--help) Help;;
			-s|--status) break;;
			-a|--standard) Toggle "$2"; shift 2;;
			-b|--paranoid) Toggle "$2" "paranoid"; shift 2;;
			-e|--ethernet) Toggle "eth"; shift;;
			-w|--wlan) Toggle "wlan"; shift;;
			-v|--wwan) Toggle "wwan"; shift;;
			-p|--paranoid-eth) Toggle "eth" "paranoid"; shift;;
			-q|--paranoid-wlan) Toggle "wlan" "paranoid"; shift;;
			-x|--paranoid-wwan) Toggle "wwan" "paranoid"; shift;;
			-y|--reboot-onoff) ToggleService; shift;;
			-r|--rules) DisplayRules; shift;;
			-z|--delete-rules) RulesDeleteAll; exit 0 ;;
			--) break;
		esac
	done
}

#----------------------------------------------------------------------#


main(){
	local -a opt=("$@")
	
	#--- find text dir | load text ---#
	readonly LANGUAGE="$( SetLang )"
	[[ "$BASE_DIR" == "/usr/local/bin" ]] && readonly DIR_L="/usr/local/share/kill-switch-ufw/lang"
	[[ "$BASE_DIR" == "/usr/local/bin" ]] || readonly DIR_L="${BASE_DIR}/lang"
	LoadConfig "${DIR_L}/text_$LANGUAGE.conf"
	#-------------------------#
	
	StatusFirewall	
	CommandLineOptions "${opt[@]}"
	
	DisplayStatusAll
	DisplayService
}



if [[ "$DEBUG" == ON ]]; then
	set -T
	trap 'DebugTrapFilter && Debug' DEBUG
fi

main "$@"

