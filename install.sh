#!/usr/bin/env bash

if [[ $EUID -ne 0 ]]; then
    printf "%s\n" "This script must be run as root"
    exit 1
fi

BASE_DIR="$( dirname "$( realpath "${BASH_SOURCE[0]}" )" )"
readonly BASE_DIR

readonly SRC_MAIN="${BASE_DIR}/kill-switch-ufw.sh"
readonly SUM_MAIN="16b1e0358cea09fbc9034c009d178246bfa38d7fa5e7b9ff92454b29d4e40f9c"
readonly DST_MAIN="/usr/local/bin/kill-switch-ufw"

readonly SRC_LANG="${BASE_DIR}/lang/lang.tar.xz"
readonly SUM_LANG="cd4c533436f3efdcea9b9f0dba03a6b7690645da1befa313c0523e5cda432c60"
readonly DST_LANG="/usr/local/share/kill-switch-ufw/"

readonly DST_SERVICE_FILE="/etc/systemd/system/kill-switch-ufw-reset.service"

readonly GREEN='\033[38;5;46m'
readonly RED='\033[38;5;160m'
readonly BLUE='\033[38;5;23m'
readonly PURPLE='\033[38;5;53m'
readonly CYAN='\033[38;5;43m'
readonly YELLOW='\033[38;5;184m'
readonly NC='\033[0m'

readonly TXT_YN="[y/N]"
COLS="$(tput cols)"
readonly COLS
readonly HPA_A=10
readonly DELAY=1

#----------------------------------------------------------------------
GetSysLang(){
	local lang
	lang="${LANG%%_*}"
	printf "%s" "${lang,,}"
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
	printf "%s" "$lang"
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
				printf "${YELLOW}%s " "CRITICAL:"  >&2
				printf "${RED}%s\n" "Config file $file trys to override envoironment variable: $key"  >&2
				exit 1
			fi
            
			#delete quotes from values
            value="${value%\"}"
            value="${value#\"}"
			
			printf -v "$key" "%s" "$value"
        else
            printf "%s\n" "Invalid config line: $line" >&2
            exit 1
        fi 
    done < "$file"
  }
  
DepCheck(){
	local dep="$1"
	command -v "$dep" > /dev/null;
	}

SumCheck(){
	local file="$1"
	local sum="$2"
	
	file="$( sha256sum "$file" ))"
	
	[[ "${file%% *}" == "$sum" ]] || return 1
	}
	
SyntaxCheck(){
	local file="$1"
	bash -n "$file"
	}

RequiredSystemd(){
	systemctl status &> /dev/null
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
	
	printf "%s${nc}\n" "" >& "$output_fd"
	}

Wuff(){
	local text="$1"
	shift
	local -a pos=("$@")
	local format color nc arf
		
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
	
	#shellcheck disable=SC2059
	printf "$format" "$color" "$text" "$nc" | fold -s -w "$COLS" >&"$output_fd" 
	}

#----------------------------------------------------------------------#

Norm(){
	local v="$1"
	v="${v% }"
	printf "%s\n" "${v,,}"
	}

YesOrNo(){
	local v
	while true; do
		Wuff "$TXT_YN" "$YELLOW" "-e"
		read -r -p " >>> " v
		v="$( Norm "$v" )"
		case "$v" in
			y|ye|yes) return 0;;
			n|no) return 1 ;;
			*) Woof "#"
			   Wuff "$TXT_YN" "$YELLOW" "-e " "$HPA_A"
			   Wuff "$TXT_YN" "$BLUE" "-e "
			   Wuff "$TXT_YN" "$RED" "-e "
			   Wuff "$TXT_YN" "$GREEN" "-e "
			   Wuff "$TXT_YN" "$PURPLE" "-e "
			   Wuff "$TXT_YN" "-e "
			   Wuff "$TXT_YN" "$CYAN"
			   Woof "#"
			 ;;
		esac
	done
	}

#----------------------------------------------------------------------#


Install(){
	local app="$1"
	
	if DepCheck "nala"; then
		nala install "$app" -y
	elif DepCheck apt; then
		apt install "$app" -y
	elif DepCheck dnf; then
		dnf install "$app" -y
	elif DepCheck "pacman"; then
		pacman -S "$app" --noconfirm
	elif DepCheck "$apk"; then
		if ! apk add "$app" --noconfirm 2> /dev/null; then
			printf "%s\n" "$app $TXT_INSTALLER_COM"
			YesOrNo || return 0
		
			apk add --noconfirm --no-cache "$app" \
			--repository=https://dl-cdn.alpinelinux.org/alpine/latest-stable/community
		fi
	fi
	}

UnInstall(){
	local app="$1"
	
	if DepCheck "nala"; then
		nala remove "$app" -y
	elif DepCheck apt; then
		apt remove "$app" -y
	elif DepCheck dnf; then
		dnf remove "app" -y
	elif DepCheck "pacman"; then
		pacman -R "$app" --noconfirm
	elif DepCheck "apk"; then
		apk del "app" --noconfirm
	fi
	}

#----------------------------------------------------------------------#

InstallMain(){
	install -d -m 755 "$DST_LANG" && \
	
	tar -xf "$SRC_LANG" -C "$DST_LANG" \
	lang/help_${LANGUAGE}.md \
	lang/help_${LANGUAGE}.txt \
	lang/text_${LANGUAGE}.conf && \
	chmod -R 755 "${DST_LANG}/lang" && \
	install -T -m 755 "$SRC_MAIN" "$DST_MAIN";
	}


UninstallMain(){
	kill-switch-ufw -z
	rm -dr "$DST_LANG" && \
	rm "$DST_MAIN"
	}

#----------------------------------------------------------------------#
ServiceCheck(){
		systemctl list-unit-files | grep -- "kill-switch-ufw-reset" &> \
		/dev/null
	}
	
InstallServiceReset(){
	
	cat > "$DST_SERVICE_FILE" <<"EOF"
[Unit]
Description=kill-switch-ufw-reset

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/kill-switch-ufw -z
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target

EOF

	chmod +x "$DST_SERVICE_FILE" 
	systemctl daemon-reload  > /dev/null && \
	sleep 0.5 && \
	systemctl enable --now "${DST_SERVICE_FILE##*/}" > /dev/null && \
	sleep 0.5 &&\
	systemctl restart --now "${DST_SERVICE_FILE##*/}" > /dev/null && \
	sleep "$DELAY" || return 1
	}

UninstallServiceReset(){
	systemctl disable --now "${DST_SERVICE_FILE##*/}" > /dev/null && \
	rm "${DST_SERVICE_FILE}" > /dev/null && \
	systemctl daemon-reload > /dev/null && \
	sleep "$DELAY" || return 1
	}

#----------------------------------------------------------------------#

#M
MenuHeader(){
	clear
	Woof "#"
	Wuff "$TXT_M_KWU" "$YELLOW" 
	Woof "#"
	Wuff ""
}

#MI
MenuUninstallMain(){
	MenuHeader
	
	Wuff "$TXT_MI_UNINSTALL_MAIN" "$CYAN" "-e\n\n"
	Wuff "$TXT_MI_UNINSTALL_INFO" "-e\n\n" 
	Woof "#"
	
	YesOrNo || exit 0
	if UninstallMain; then
		Wuff "$TXT_MI_UNINSTALL_OK" "$GREEN" "-a\n"
	else
		Wuff "$TXT_MI_UNINSTALL_ERR" "$RED" "-a\n"
	fi
		}

#MH
MenuUninstallService(){
	RequiredSystemd || return 0
	ServiceCheck || return 0
	
	MenuHeader
	Wuff "$TXT_MH_UNINSTALL_SERVICE" "$CYAN" "-e\n\n"
	Woof "#"
	
	YesOrNo || return 0
	if UninstallServiceReset; then
		Wuff "$TXT_MH_UNINSTALL_OK" "$GREEN"
	else
		Wuff "$TXT_MH_UNINSTALL_ERR" "$RED"
	fi
}	

#MG
MenuUninstallGlow(){
	DepCheck "glow" || return 0
	
	MenuHeader	
	Wuff "$TXT_MG_UNINSTALL" "$CYAN" "-e\n\n"
	Wuff "$TXT_MG_UNIN" "-e\n\n"
	Woof "#"
	
	YesOrNo || return 0
	UnInstall "glow"
	}

#ME
MenuUninstall(){
	MenuHeader
	Wuff "$TXT_MF_UNINSTALL" "$CYAN" "-e\n\n"
	Wuff "$TXT_MF_CONFIRM" "-e\n\n"
	Woof "#"
	
	YesOrNo || exit 0
	}

#ME
MenuInstallComplete(){
	MenuHeader
	Wuff "$TXT_MD_COMPLETE" "$GREEN" "-e\n\n"
	Wuff "$TXT_MD_UNINSTALL" "-e\n\n"
	Wuff "$TXT_MD_HELP" "-e\n\n"
	Woof "#"
	}

#MD
MenuInstallMain(){
		MenuHeader
		
		Wuff "$TXT_ME_COPY" "$CYAN" "-e\n\n"
		Wuff "$TXT_ME_INFO" "-e\n\n"
		Woof "#"
		YesOrNo || exit 0
		
		if ! InstallMain; then
			Wuff "$TXT_INSTALL_ERR" 
			return 1
		fi
	
	}
	
#MC
MenuInstallService(){
	RequiredSystemd || return 0
	ServiceCheck && return 0
	
	MenuHeader
	Wuff "$TXT_MC_RESET $TXT_OPTIONAL" "$CYAN" "-e\n\n"
	Wuff "$TXT_MC_CONNECT" "-e\n\n"
	Wuff "$TXT_MC_INFO" "-e\n\n"
	Wuff "$TXT_MC_ENA_SERVICE" "$YELLOW" "$HPA_A" "-e\n\n"
	Wuff "$TXT_MC_DEL_SERVICE" "-e\n\n"
	Woof "#"
	
	YesOrNo || return 0
	if InstallServiceReset; then
		Wuff
		Wuff "$TXT_MC_INSTALL_OK" "$GREEN" "-a\n" "-e\n\n"
	else
		Wuff "$TXT_MC_INSTALL_ERR" "$RED" "-a\n" "-e\n\n"
	fi
	
	}

#MB
MenuInstallGlow(){
	DepCheck "glow" && return 0
	
	MenuHeader
	Wuff "$TXT_MB_GLOW $TXT_OPTIONAL" "$CYAN" "-e\n\n"
	Wuff "$TXT_MB_GLOW_DESCR" "-e\n\n" 
	Woof "#"
	
	YesOrNo || return 0
	Install "glow"
	}

#MA
MenuInstall(){
	MenuHeader
	
	Wuff "$TXT_MA_INSTALL" "$CYAN" "-e\n\n"
	Wuff "$TXT_MA_DESCRIBE" "-e\n\n"
	Wuff "$TXT_MA_FIREWALL" "-e\n\n"
	Wuff "$TXT_MA_KILLSWITCH" "-e\n\n"
	Woof "#"
	
	YesOrNo || exit 0
	}

#MR
MenuRequired(){
	local appname="$1"
	local paket="$2"
	
	DepCheck "$appname" && return 0
		
		MenuHeader
		Wuff "$TXT_MR_REQUIRED" "$CYAN"
		Woof "#"
		
		YesOrNo || exit 0
		Install "$paket"
	}

#ML
MenuSumMain(){
	SumCheck "$SRC_MAIN" "$SUM_MAIN" && return 0
	
	MenuHeader
	Wuff "$TXT_ML_MAINFILE" "" "$RED" "-e\n\n"
	Wuff "$TXT_CHECKSUM" "-e\n\n"
	Wuff "$SRC_MAIN" "$RED" "-e\n\n"
	Woof "#"
	
	YesOrNo || exit 1
	}

#MK	
MenuSumLang(){
	SumCheck "$SRC_LANG" "$SUM_LANG" && return 0
	
	MenuHeader
	Wuff "$TXT_MK_LANGFILE" "$RED" "-e\n\n"
	Wuff "$TXT_CHECKSUM"  "-e\n\n"
	Wuff "$SRC_LANG" "$RED" "-e\n\n"
	Woof "#"
	
	YesOrNo || exit 1
	}

#MJ
MenuSyntax(){
		SyntaxCheck "$SRC_MAIN" && return 0
		
		MenuHeader
		Wuff "" "$YELLOW" "-e\n\n"
		Wuff "TXT_SYNTAX" "-e\n\n"
		Wuff "$SRC_MAIN" "-e\n\n"
		Woof #
		
		YesOrNo || exit 1
	}
	
#----------------------------------------------------------------------#

main(){
	local mode="$1"
	mode="${mode:-install}"
	 
	readonly LANGUAGE="$( SetLang )"
	LoadConfig "${BASE_DIR}/lang/txt_install_${LANGUAGE}.conf"
	
	if [[ "$mode" == "install" ]]; then
		MenuInstall
		sleep "$DELAY"
		MenuSumMain
		MenuSumLang
		MenuSyntax
		MenuRequired "ufw" "ufw"
		MenuRequired "nmcli" "network-manager"
		MenuInstallGlow
		sleep "$DELAY"
		if MenuInstallMain; then
			sleep "$DELAY"
			MenuInstallService
			sleep "$DELAY"
			MenuInstallComplete
		fi
		
	elif [[ "$mode" == "uninstall" ]]; then
		MenuUninstall
		sleep "$DELAY"
		MenuUninstallGlow
		sleep "$DELAY"
		MenuUninstallService
		sleep "$DELAY"
		MenuUninstallMain
	fi
}

main "$1"


