#!/usr/bin/env bash

shopt -s extglob
set -o errtrace
#set -o errexit
set +o noclobber

export NOOP=

ASSUMEYES=0
VERBOSE=1
LOG="$HOME/Downloads/puppet-me.log"
tmp="tmp"
puppet_master="puppet"
userid=$(whoami)

CURL="/usr/bin/curl --location --progress-bar "

MODULE_homebrew_done=0
MODULE_cache_done=0
MODULE_packer_done=0
MODULE_puppet_done=0
MODULE_rubytools_done=0
MODULE_vagrant_done=0
MODULE_parallels_done=0
MODULE_virtualbox_done=0
MODULE_vmware_done=0
MODULE_virtualization_done=0

MODULES=(homebrew puppet rubytools)
ALL_MODULES=(homebrew cache noidle packer puppet rubytools vagrant virtualbox vmware parallels)

CACHE_ROOT='/var/cache/daas'
CACHE_SOURCE='https://cdn.rawgit.com/inin-apac/puppet-me/c8795de6ad1484c9386436543cc5a0f9d3290a23/config/sources.json'
CACHE_MOUNTS=()

MODULE_VMWARE_HOME=''
MODULE_VIRTUALBOX_HOME=''
MODULE_PARALLELS_HOME=''
MODULE_PACKER_HOME="$HOME/Documents/packer"
[[ -n "$PACKER_HOME"    ]] && MODULE_PACKER_HOME="$PACKER_HOME"
MODULE_VAGRANT_HOME="$HOME/.vagrant.d"
[[ -n "$XDG_CONFIG_HOME" ]] && MODULE_VAGRANT_HOME="$XDG_CONFIG_HOME/vagrant"
[[ -n "$VAGRANT_HOME"    ]] && MODULE_VAGRANT_HOME="$VAGRANT_HOME"

trap trace_end EXIT

# Module: tracing {{{

function trace() # {{{2
{
  local caller_index=1

  while :; do
    case $1 in
      --trace-member)
      caller_index=2
      ;;
      --noop|-n)
        return
      ;;
     *)  # End of options
       break
       ;;
    esac
    shift
  done

  echo -e "[$(date +'%Y%m%dT%H%M%S')]${BASH_SOURCE[$caller_index]}::${FUNCNAME[$caller_index]}@${BASH_LINENO[(($caller_index - 1))]}: $@" >> $LOG
} # }}}2

function trace_init() # {{{2
{
  local log_file=$(basename $LOG)
  local log_group="wheel"
  local result

  while :; do # Parse arguments {{{3
    case $1 in
      --logdest)
        [[ -z $2 || ${2:0:1} == '-' ]] && die -n "Argument for option $1 is missing"
        LOG="$2/$log_file"
        shift 2
        continue
      ;;
      --logdest=*?)
        LOG="${1#*=}/$log_file"
      ;;
      --logdest=)
        die -n "Argument for option $1 is missing"
      ;;
      --loggroup)
        [[ -z $2 || ${2:0:1} == '-' ]] && die -n "Argument for option $1 is missing"
        log_group="$2/$log_file"
        shift 2
        continue
      ;;
      --loggroup=*?)
        log_group=${1#*=}
      ;;
      --loggroup=)
        die -n "Argument for option $1 is missing"
      ;;
     -?*) # Invalid options
       ;;
     --) # Force end of options
       shift
       break
       ;;
     *)  # End of options
       break
       ;;
    esac
    shift
  done # }}}3

  if [[ ! -w $LOG ]]; then
    if [[ ! -w $(dirname $LOG) ]]; then
      echo "NOTE: You might have to enter your password to allow the script to modify your system!"
      if [[ ! -d $(dirname $LOG) ]]; then
        sudo mkdir -p $(dirname $LOG) 2>&1 | tee /dev/null > /dev/null
        result=$?
        [[ $result ]] && die -n "Could not create folder $(dirname $LOG)" $result
      fi
      sudo touch $LOG 2>&1 | tee /dev/null > /dev/null
      [[ $result ]] && die -n "Could not create $LOG" $result
      sudo chown $(whoami):${log_group} $LOG
      [[ $result ]] && die -n "Could not change owner for $LOG" $result
      sudo chmod 640 $LOG 2>&1 | tee /dev/null > /dev/null
      [[ $result ]] && die -n "Could not change permissions for $LOG" $result
    else
      touch $LOG 2>&1 | tee /dev/null > /dev/null
      [[ $result ]] && die -n "Could not create $LOG" $result
      chgrp ${log_group} $LOG 2>&1 | tee /dev/null > /dev/null
      [[ $result ]] && die -n "Could not change group for $LOG" $result
      chmod 640 $LOG 2>&1 | tee /dev/null > /dev/null
      [[ $result ]] && die -n "Could not change permissions for $LOG" $result
    fi
  fi
  trace --trace-member "[BEGIN] -------"
} # }}}

function trace_end() # {{{2
{
  for cache_mount in ${CACHE_MOUNTS[@]}; do
    trace --trace-member "Removing CIFS mount point: $cache_mount"
    umount $cache_mount 2>&1 > /dev/null
  done
  trace --trace-member "[END] -------"
} # }}}2

function verbose() ## {{{2
{
  trace --trace-member "$@"
  [[ $VERBOSE > 0 ]] && echo -e "$@"
} # }}}2

function warn() # {{{2
{
  trace --trace-member "[WARNING] $@"
  echo -e "Warning: $@"
} # }}}2

function error() # {{{2
{
  trace --trace-member "[ERROR] $@"
  echo -e "Error: $@" >&2
} # }}}2

function die() # {{{2
{
  local trace_noop=
  if [[ $1 == '-n' ]]; then
   trace_noop=:
   shift
  fi
  local message=$1
  local errorlevel=$2

  [[ -z $message    ]] && message='Died'
  [[ -z $errorlevel ]] && errorlevel=1
  $trace_noop trace --trace-member "[FATALERROR] $errorlevel $message"
  $trace_noop trace_end
  echo -e $message >&2
  exit $errorlevel
} # }}}2

# }}}

# Module: tools {{{

function capitalize() # {{{2
{
  local value=$1

  echo "$(tr '[:lower:]' '[:upper:]' <<< ${value:0:1})${value:1}"
} # }}}2

function mask_cidr2dotted() #{{{2
{
   # Number of args to shift, 255..255, first non-255 byte, zeroes
   set -- $(( 5 - ($1 / 8) )) 255 255 255 255 $(( (255 << (8 - ($1 % 8))) & 255 )) 0 0 0
   [ $1 -gt 1 ] && shift $1 || shift
   echo ${1-0}.${2-0}.${3-0}.${4-0}
} # }}}2

function mask_dotted2cidr() #{{{2
{
   # Assumes there's no "255." after a non-255 byte in the mask
   set -- 0^^^128^192^224^240^248^252^254^ ${#1} ${1##*255.}
   set -- $(( ($2 - ${#3})*2 )) ${1%%${3%%.*}*}
   echo $(( $1 + (${#2}/4) ))
} # }}}2

function mask_hex2cidr() #{{{2
{
   # Assumes there's no "ff" after a non-ff byte in the mask
   set -- 08ce ${#1} ${1##*f}
   set -- $(( ($2 - ${#3})*4 )) ${1%%${3%%0*}*}
   echo $(( $1 + ${#2} ))
} # }}}2

function urldecode() #{{{2
{
  local value=${1//+/ }         # decode + into space
  printf '%b' "${value//%/\\x}" # decode hexa characters (ANSI only)
} # }}}2

function prompt() #{{{2
{
  local silent=''
  local default=''
  local query
  local value

  while :; do # Parse aguments {{{3
    case $1 in
      --default)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "$FUNCNAME: Argument for option $1 is missing" && return 1
        default=$2
        shift 2
        continue
      ;;
      --default=*?)
        default=${1#*=} # delete everything up to =
      ;;
      --default=)
        error "$FUNCNAME: Argument for option $1 is missing"
        return 1
        ;;
      -s|--silent)
        silent='-s'
      ;;
      -?*) # Invalid options
        warn "Unknown option $1 will be ignored"
      ;;
      *)  # End of options
        break
      ;;
    esac
    shift
  done # }}}3
  query=$1
  trace "Query: ${query}"
  trace "Default: ${default}"
  trace "Silent: ${silent}"
  if [[ -z "$SSH_CLIENT" ]]; then
    # We are on the Mac screen
    trace "Prompting with GUI"
    [[ -n $silent ]] && silent='with hidden answer'
    script="Tell application \"System Events\" to display dialog \"${query}\" giving up after 20 default answer \"${default}\" $silent"
    trace "OSA Script: $script"
    value="$(osascript -e "$script" -e 'text returned of result' 2>&1)"
    status=$?
    if [ $status -ne 0 ]; then
      trace " Error $status: $value"
      return 1
    fi
  else
    # We are in an SSH session
    trace "Prompting within the shell"
    [[ -n "$default" ]] && query="${query} [${default}]"
    trace "Query: $query"
    read $silent -p "${query}: " value < /dev/tty
  fi
  [[ -z "$value" ]] && value=$default
  printf '%s' $value
} # }}}2

function version() # {{{2
{
  #GNU style
  if $1 --version 2>&1; then
    version=$($1 --version)
  elif $1 -version 2>&1; then
    version=$($1 -version)
  elif $1 -V 2>&1; then
    version=$($1 -V)
  elif $1 version 2>&1; then
    version=$($1 version)
  else
    version='unknown'
  fi
  echo -n $version | tr -d '\n'
} # }}}2

function keychain_get_user() # {{{2
{
  local service
  local protocol
  local command
  local kind
  local user
  local url

  while :; do # Parse aguments {{{3
    case $1 in
      --kind|-k)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        kind=$2
        shift 2
        continue
      ;;
      --kind=*?)
        kind=${1#*=} # delete everything up to =
      ;;
      --kind=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      --protocol|-p)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        protocol=$2
        shift 2
        continue
      ;;
      --protocol=*?)
        protocol=${1#*=} # delete everything up to =
      ;;
      --protocol=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      --service|--host|--site|-s)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        service=$2
        shift 2
        continue
      ;;
      --service=*?|--host=*?|--site=*?)
        service=${1#*=} # delete everything up to =
      ;;
      --service=|--host=|--site=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      --url)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        url=$2
        shift 2
        continue
      ;;
      --url=*?)
        url=${1#*=} # delete everything up to =
      ;;
      --url=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      -?*) # Invalid options
        warn "${FUNCTNAME}: Unknown option $1 will be ignored"
      ;;
      *)  # End of options
        break
      ;;
    esac
    shift
  done # }}}3

  # Validate Arguments {{{3
  case $kind in # {{{4
    internet|'')         command='find-internet-password' ;;
    application|generic) command='find-generic-password' ;;
    *)
      error "$FUNCNAME: Unsupported kind \"${kind}\""
      return 2
    ;;
  esac # }}}4
  if [[ -n "$url" ]]; then # url {{{4
    trace "  >> url: ${url}"
    protocol=${url%%:*}
    trace "  >> url protocol: ${protocol}"
    service=${url#*://}                               # remove protocol
    if [[ "${service}" =~ .*@.* ]]; then              # search for credentials
      user=${service#*//}                             # remove heading //
      user=${user%@*}                                 # keep credentials
      if [[ "${user}" =~ .*:.* ]]; then               # search for password
        user=${user%:*}                               # remove all after :
      fi
      user=${user/;/\\/}
      service=${service#*@}                           # remove user
      trace "  >> user: ${user}"
    fi
    service=${service%%/*}                            # extract host
    trace "  >> service: ${service}"
  fi # }}}4
  if [[ $command == 'find-internet-password' ]]; then # protocol {{{4
    trace "Kind is internet, analyzing protocol ($protocol)"
    case $protocol in
      afp)        protocol='afp ' ;;
      http)       protocol='http' ;;
      https|htps) protocol='htps' ;;
      ftp)        protocol='ftp ' ;;
      smb|cifs)   protocol='smb ' ;;
      ssh)        protocol='ssh ' ;;
      '')         protocol='';;
      *)
        error "$FUNCNAME: Unsupported protocol \"${protocol}\""
        return 2
      ;;
    esac
  fi # }}}4
  if [[ -z "$service" ]]; then # {{{4
    error "option service cannot be empty"
    return 2
  fi # }}}4
  # }}}3
  trace "Searching $kind user $user @ $service (protocol: $protocol)"
  if [[ -n "$protocol" ]]; then
    trace "Exec: [/usr/bin/security $command -r "$protocol" -s \"$service\"]"
    user=$(/usr/bin/security $command -r "$protocol" -s "$service" 2>&1)
  else
    trace "Exec: [/usr/bin/security $command -s \"$service\"]"
    user=$(/usr/bin/security $command -s "$service" 2>&1)
  fi
  status=$?
  [[ $status != 0 ]] && trace "Error $status: $user" && return $status
  user=$(echo "$user" | grep acct | awk -F= '{print $2 }' | tr -d '"' | sed -e 's/^0x[0-9,A-F]*[[:space:]]*//' | sed -e 's/\\134/\\/')
  trace "Found $kind user @ $service: $user"
  printf '%s' $user
} # }}}2

function keychain_get_password() # {{{2
{
  local service
  local protocol
  local command
  local kind
  local user
  local password
  local url

  while :; do # Parse aguments {{{3
    case $1 in
      --kind|-k)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        kind=$2
        shift 2
        continue
      ;;
      --kind=*?)
        kind=${1#*=} # delete everything up to =
      ;;
      --kind=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      --protocol|-p)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        protocol=$2
        shift 2
        continue
      ;;
      --protocol=*?)
        protocol=${1#*=} # delete everything up to =
      ;;
      --protocol=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      --service|--host|--site|-s)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        service=$2
        shift 2
        continue
      ;;
      --service=*?|--host=*?|--site=*?)
        service=${1#*=} # delete everything up to =
      ;;
      --service=|--host=|--site=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      --url)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        url=$2
        shift 2
        continue
      ;;
      --url=*?)
        url=${1#*=} # delete everything up to =
      ;;
      --url=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      --user|--userid|--username|-u)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        user=$2
        shift 2
        continue
      ;;
      --user=*?|--userid=*?|--username=*?)
        user=${1#*=} # delete everything up to =
      ;;
      --user=|--userid=|--username=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      -?*) # Invalid options
        warn "${FUNCTNAME}: Unknown option $1 will be ignored"
      ;;
      *)  # End of options
        break
      ;;
    esac
    shift
  done # }}}3

  # Validate Arguments {{{3
  case $kind in # {{{4
    internet|'')         command='find-internet-password' ;;
    application|generic) command='find-generic-password' ;;
    *)
      error "$FUNCNAME: Unsupported kind \"${kind}\""
      return 2
    ;;
  esac # }}}4
  if [[ -n "$url" ]]; then # url {{{4
    trace "  >> url: ${url}"
    protocol=${url%%:*}
    trace "  >> url protocol: ${protocol}"
    service=${url#*://}                               # remove protocol
    if [[ "${service}" =~ .*@.* ]]; then              # search for credentials
      user=${service#*//}                             # remove heading //
      user=${user%@*}                                 # keep credentials
      if [[ "${user}" =~ .*:.* ]]; then               # search for password
        user=${user%:*}                               # remove all after :
      fi
      user=${user/;/\\/}
      service=${service#*@}                           # remove user
      trace "  >> user: ${user}"
    fi
    service=${service%%/*}                            # extract host
    trace "  >> service: ${service}"
  fi # }}}4
  if [[ $command == 'find-internet-password' ]]; then # protocol {{{4
    trace "Kind is internet, analyzing protocol ($protocol)"
    case $protocol in
      afp)        protocol='afp ' ;;
      http)       protocol='http' ;;
      https|htps) protocol='htps' ;;
      ftp)        protocol='ftp ' ;;
      smb|cifs)   protocol='smb ' ;;
      ssh)        protocol='ssh ' ;;
      '')         protocol='';;
      *)
        error "$FUNCNAME: Unsupported protocol \"${protocol}\""
        return 2
      ;;
    esac
  fi # }}}4
  if [[ -z "$service" ]]; then # {{{4
    error "option service cannot be empty"
    return 2
  fi # }}}4
  if [[ -z "$user" ]]; then # {{{4
    error "option user cannot be empty"
    return 2
  fi # }}}4
  # }}}3
  trace "Searching password for $kind user $user @ $service (protocol: $protocol)"
  trace "Exec: [/usr/bin/security $command -r "$protocol" -s \"$service\" -a \"$user\" -w]"
  if [[ -n "$protocol" ]]; then
    password=$(/usr/bin/security $command -r "$protocol" -s "$service" -a "$user" -w 2>&1)
  else
    password=$(/usr/bin/security $command -s "$service" -a "$user" -w 2>&1)
  fi
  status=$?
  [[ $status != 0 ]] && trace "Error $status: $password" && return $status
  trace "Found password for $user @ $service: XXXXXX"
  printf '%s' $password
} # }}}2

function keychain_set_password() # {{{2
{
  local service
  local protocol
  local command
  local kind
  local user
  local password
  local url

  while :; do # Parse aguments {{{3
    case $1 in
      --kind|-k)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        kind=$2
        shift 2
        continue
      ;;
      --kind=*?)
        kind=${1#*=} # delete everything up to =
      ;;
      --kind=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      --protocol|-p)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        protocol=$2
        shift 2
        continue
      ;;
      --protocol=*?)
        protocol=${1#*=} # delete everything up to =
      ;;
      --protocol=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      --service|--host|--site|-s)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        service=$2
        shift 2
        continue
      ;;
      --service=*?|--host=*?|--site=*?)
        service=${1#*=} # delete everything up to =
      ;;
      --service=|--host=|--site=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      --url)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        url=$2
        shift 2
        continue
      ;;
      --url=*?)
        url=${1#*=} # delete everything up to =
      ;;
      --url=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      --user|--userid|--username|-u)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        user=$2
        shift 2
        continue
      ;;
      --user=*?|--userid=*?|--username=*?)
        user=${1#*=} # delete everything up to =
      ;;
      --user=|--userid=|--username=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      --password)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        password=$2
        shift 2
        continue
      ;;
      --password=*?)
        password=${1#*=} # delete everything up to =
      ;;
      --password=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      -?*) # Invalid options
        warn "${FUNCTNAME}: Unknown option $1 will be ignored"
      ;;
      *)  # End of options
        break
      ;;
    esac
    shift
  done # }}}3

  # Validate Arguments {{{3
  case $kind in # {{{4
    internet|'')         command='add-internet-password' ;;
    application|generic) command='add-generic-password' ;;
    *)
      error "$FUNCNAME: Unsupported kind \"${kind}\""
      return 2
    ;;
  esac # }}}4
  if [[ -n "$url" ]]; then # url {{{4
    trace "  >> url: ${url}"
    protocol=${url%%:*}
    trace "  >> url protocol: ${protocol}"
    service=${url#*://}                               # remove protocol
    if [[ "${service}" =~ .*@.* ]]; then              # search for credentials
      user=${service#*//}                             # remove heading //
      user=${user%@*}                                 # keep credentials
      if [[ "${user}" =~ .*:.* ]]; then               # search for password
        password=${user#*:}                           # extract password
        user=${user%:*}                               # remove all after :
      fi
      user=${user/;/\\/}
      service=${service#*@}                           # remove user
      trace "  >> user: ${user}"
    fi
    service=${service%%/*}                            # extract host
    trace "  >> service: ${service}"
  fi # }}}4
  if [[ $command == 'find-internet-password' ]]; then # protocol {{{4
    trace "Kind is internet, analyzing protocol ($protocol)"
    case $protocol in
      afp)        protocol='afp ' ;;
      http)       protocol='http' ;;
      https|htps) protocol='htps' ;;
      ftp)        protocol='ftp ' ;;
      smb|cifs)   protocol='smb ' ;;
      ssh)        protocol='ssh ' ;;
      '')         protocol='';;
      *)
        error "$FUNCNAME: Unsupported protocol \"${protocol}\""
        return 2
      ;;
    esac
  fi # }}}4
  if [[ -z "$service" ]]; then # {{{4
    error "option service cannot be empty"
    return 2
  fi # }}}4
  if [[ -z "$user" ]]; then # {{{4
    error "option user cannot be empty"
    return 2
  fi # }}}4
  if [[ -z "$password" ]]; then # {{{4
    error "option password cannot be empty"
    return 2
  fi # }}}4
  # }}}3
  trace "Updating password for $kind user $user @ $service (protocol: $protocol)"
  trace "Exec: [/usr/bin/security $command -r "$protocol" -s \"$service\" -a \"$user\" -w XXXX]"
  if [[ -n "$protocol" ]]; then
    /usr/bin/security $command -U -r "$protocol" -s "$service" -a "$user" -w "$password"
  else
    /usr/bin/security $command -U -s "$service" -a "$user" -w "$password"
  fi
  status=$?
  [[ $status != 0 ]] && trace "Error: $status" && return $status
  trace "Set password for $user @ $service"
} # }}}2

function download() # {{{2
{
  # download "http://login:password@hostname/path/file?k1=v1&k2=v2" "local_folder"
  # download "smb://login:password@hostname/path/file?k1=v1&k2=v2" "local_folder"
  local need_auth=0
  local has_resume
  local source
  local target
  local checksum_type
  local checksum_value
  local checksum='md5'
  local target_checksum
  local archive_source
  local filename
  local filename_path
  local source_protocol
  local source_user
  local source_domain
  local source_password
  local source_host
  local source_path
  local source_ext
  local source_credentials_updated=0
  local sudo

  while :; do # Parse aguments {{{3
    case $1 in
      --has_resume)
        has_resume="--continue-at -"
        trace "The source URL handles resume downloads"
      ;;
      --need_auth)
        need_auth=1
        trace "The source URL needs authentication"
      ;;
      -?*) # Invalid options
        warn "Unknown option $1 will be ignored"
      ;;
      *)  # End of options
        break
      ;;
    esac
    shift
  done # }}}3

  source=$1
  target=$2
  checksum_type=$3
  checksum_value=$4

  # Extract source components {{{3
  if [[ "$source" =~ ^\/\/.* ]] ; then
    trace ">> Missing protocol, assuming smb/cifs"
    source="smb:${source}"
  elif [[ "$source" =~ ^\/.* ]] ; then
    trace ">> Missing protocol, assuming file"
    source="file://${source}"
  fi
  trace ">> source: ${source}"
  source_protocol=${source%%:*}
  trace ">> source protocol: ${source_protocol}"

  if [[ ${source_protocol} == 'file' && "${source}" =~ .*\?.* ]]; then
    # source is like: file:///path/archive.ext?filename
    #   the script will open the archive and extract filename.
    #   if the archive is an ISO, it is mounted for the extraction
    trace "extracting a file from an archive"
    filename_path=${source#*\?}                       # extract file in archive
    filename=${filename_path##*/}                     # remove path
    source=${source%\?*}                              # remove path in archive
    trace "  >> filename: ${filename}"
    trace "  >> filename_path: ${filename_path}"
  else
    trace "Extracting components from a URL"
    filename=${source##*/}                            # extract filename
    trace "  >> filename: ${filename}"
    source_host=$(dirname ${source#*://})             # remove protocol
    if [[ "${source_host}" =~ .*@.* ]]; then          # search for credentials
      source_user=${source_host#*//}                  # remove heading //
      source_user=${source_user%@*}                   # keep credentials
      if [[ "${source_user}" =~ .*:.* ]]; then        # search for password
        source_password=${source_user#*:}             # extract password
        source_user=${source_user%:*}                 # remove all after :
	trace "  >> source_password: (obfuscated)"
      fi
      if [[ "${source_user}" =~ .*\;.* ]]; then       # search for domain
        source_domain=${source_user%;*}               # extract domain
        source_user=${source_user#*;}                 # extract user
        trace "  >> source_domain: ${source_domain}"
      fi
      trace "  >> source_user (from URL): ${source_user}"
      source_host=${source_host#*@}                   # remove user
    fi
    source_path=${source_host#*/}                     # extract path
    source_host=${source_host%%/*}                    # extract host
    trace "  >> source_path: ${source_path}"
    trace "  >> source_host: ${source_host}"

    if [[ -z "$source_user" ]]; then
      trace "  Querying keychain for user on site $source_host over $source_protocol"
      source_user=$(keychain_get_user --kind=internet --protocol=$source_protocol --site=$source_host 2>&1)
      status=$?
      if [[ $status != 0 ]]; then
        trace "  Error $status: No user for site $source_host over $source_protocol"
        source_user=''
      else
        trace "  >> source_user (from keychain): ${source_user}"
      fi
    fi
    if [[ -z "$source_password" && -n "$source_user" ]]; then
      trace "  Querying keychain for password for user $source_user on site $source_host over $source_protocol"
      source_password=$(keychain_get_password --kind=internet --protocol=$source_protocol --site=$source_host --user=$source_user)
      if [[ $status != 0 ]]; then
        trace "  Error $status: No password for use $source_user"
        source_password=''
      else
        trace "  >> source_password (from keychain): XXXXXX"
      fi
    fi
    [[ -z "$source_user" && $need_auth == 1 ]] && source_user=$userid
    trace "  >> source_user: ${source_user}"
  fi
  trace "  >> source: ${source}"
  # }}}3

  target_path="${target}/${filename}"
  verbose "  File to eventually download: ${filename}..."

  # Validate target {{{3
  if [[ -e "$target" ]] ; then
    trace "  Target ${target} exists"
    [[ -w "$target" ]] || sudo='sudo'
  else
    trace "  Target ${target} does not exists"
    # Here we are a bit lazy and choose the admin group which of the user has to be a member
    [[ -w "$(dirname $target)" ]] || sudo='sudo'
    $NOOP $sudo mkdir -p "$target"
    $NOOP $sudo chgrp -R admin "$target"
    $NOOP $sudo chmod -R g+w "$target"
    sudo=''
    [[ -w "$target" ]] || sudo='sudo'
  fi # }}}3

  # Validate checksum  # {{{3
  case $checksum_type in
    MD5|md5)   checksum='md5';;
    SHA1|sha1) checksum='shasum';;
    null|'')   checksum='';;
    *)
    error "Unsupported checksum type ($checksum_type) while downloading $filename"
    return 1
  esac
  trace "Expect $checksum_type checksum: $checksum_value"

  if [[ -r "${target_path}" && ! -z ${checksum} ]]; then
    if [[ ! -f "${target_path}.${checksum_type}" || -n "$(find "${target_path}.${checksum_type}" -mmin +20)" ]]; then
      verbose "  Calculating checksum of the file that is already cached"
      target_checksum=$(bar -n "$target_path" | $checksum)
    else
      verbose "  Loading checksum of the file that is already cached"
      target_checksum=$(cat "${target_path}.$checksum_type")
    fi
    if [[ $target_checksum =~ \s*$checksum_value\s* ]]; then
      verbose "  File already cached and checksum verified"
      [[ -f "${target_path}.${checksum_type}" ]] || (echo -n "$target_checksum" | $sudo tee "${target_path}.$checksum_type" > /dev/null)
      return 0
    else
      $NOOP $sudo rm -f "$target_path"
    fi
  fi # }}}3

  if [[ ${source_protocol} == 'smb' ]]; then # {{{3
    verbose "  Copying from CIFS location"
    # source is like smb://domain;userid:password@server/share/path/file
    # domain, userid, and password are optional
    source_share=${source_path%%/*}             # extract SMB share
    source_path=${source_path#*/}               # remove SMB share

    if [[ -n "$source_domain" ]]; then
      source_user="${source_domain}\\${source_user}"
    fi

    smb_target=''
    smb_creds=''
    if [[ -z "$(mount | grep -i $source_host | grep -i $source_share)" ]]; then
      while true; do
        if [[ $need_auth == 1 ]]; then
          if [[ -z "$source_password" ]]; then
            verbose "  Requesting credentials for //${source_host}/${source_share}"
            source_user=$(prompt --default="$source_user" "  User for mounting ${source_share} on ${source_host}")
            if [[ $? != 0 ]]; then
              warn "User cancelled prompt operation"
              return 1
            fi
            source_password=$(prompt -s "  Password for ${source_user}")
            source_credentials_updated=1
            echo
          fi
          smb_creds="${source_user/\\/;}:${source_password//@/%40}@"
        fi
        smb_mount="//${smb_creds}${source_host}/${source_share}"
        smb_target="/Volumes/WindowsShare-${source_host}-${source_share}.$$"

        verbose "  Mounting ${source_share} from ${source_host} ${source_user:+as }${source_user}"
        trace ">> mount -t smbfs '//${source_user/\\/;}${source_password:+:XXXXX}${source_user:+@}${source_host}/${source_share}' $smb_target"
        mkdir -p $smb_target && mount -t smbfs  "${smb_mount}" $smb_target
        status=$?
        case $status in
          0)
            trace "Successful download"
            CACHE_MOUNTS+=( "//${source_user/\\/;}@${source_host}/${source_share}" )
            break
          ;;
          68)
            error "  Empty password, please enter new credentials"
            source_password=''
            need_auth=1
          ;;
          77)
            error "  Wrong credentials, please enter new credentials"
            source_password=''
            need_auth=1
          ;;
          *)
            error "  Cannot mount ${source_share} on ${source_host} as ${source_user}\nError: $status"
            return 1
          ;;
        esac
      done
    else
      smb_target=$(mount | grep -i $source_host | grep -i $source_share | awk '{print $3}')
      verbose "  ${source_share} is already mounted on ${smb_target}"
    fi
    verbose "  Copying $filename"
    trace $sudo $CURL $has_resume --output "${target_path}" "file://${smb_target}/${source_path}/$filename"
    $NOOP $sudo $CURL $has_resume --output "${target_path}" "file://${smb_target}/${source_path}/$filename"
    $NOOP $sudo chmod 664 "${target_path}"
  # }}}3
  elif [[ ${source_protocol} == 'file' ]]; then # {{{3
    if [[ -n "${filename_path}" ]]; then
      source=${source#*://}                     # remove protocol
      source_ext=${source##*\.}                 # extract extension
      verbose "Archive type: ${source_ext}"
      case $source_ext in
        iso|ISO)
          mount_info=$(hdiutil mount ${source})
          if [ $? -ne 0 ]; then
            error "Cannot mount ${source}"
            return 1
          fi
          mount_path=$(echo "$mount_info" | awk '{print $2}')
          trace "mount info: ${mount_info}"
          trace "mount path: ${mount_path}"
          trace $sudo $CURL $has_resume --output "${target_path}" "file://${mount_path}/${filename_path}"
          $NOOP $sudo $CURL $has_resume --output "${target_path}" "file://${mount_path}/${filename_path}"
          if [ $? -ne 0 ]; then
            error "Cannot copy ${mount_path}/${filename_path} to ${target_path}"
          else
            $NOOP $sudo chmod 664 "${target_path}"
          fi
          results=$(hdiutil unmount ${mount_path})
          if [ $? -ne 0 ]; then
            error "Cannot unmount ${source}, error: ${results}"
            return 1
          fi
        ;;
        *)
          error "Unsupported archive format in ${source}"
          return 1
        ;;
      esac
    else
      trace $sudo $CURL $has_resume --output "${target_path}" "${source}"
      $NOOP $sudo $CURL $has_resume --output "${target_path}" "${source}"
      $NOOP $sudo chmod 664 "${target_path}"
    fi
  # }}}3
  else # other urls (http, https, ftp) {{{3
    verbose "  Copying from url location"
    while true; do
      curl_creds=''
      if [[ $need_auth == 1 ]]; then
        if [[ -z "$source_password" ]]; then
          verbose "  Requesting credentials for ${source_host}"
          source_user=$(prompt --default="$source_user" "  User to download from ${source_host}")
          if [[ $? != 0 ]]; then
            warn "User cancelled prompt operation"
            return 1
	  fi
          source_password=$(prompt -s "  Password for ${source_user}")
          source_credentials_updated=1
          echo
        fi
        curl_creds="--user ${source_user/\\/;/}:${source_password}" # encode domain
      fi
      verbose "  Downloading..."
      trace $sudo $CURL $has_resume ${curl_creds} --output "${target_path}" "${source}"
      $NOOP $sudo $CURL $has_resume ${curl_creds} --output "${target_path}" "${source}"
      status=$?
      case $status in
        0)
          trace "Successful download"
          $NOOP $sudo chmod 664 "${target_path}"
          break
        ;;
        67)
          error "  Wrong credentials, please enter new credentials"
          source_password=''
          need_auth=1
        ;;
        *)
          error "  Unable to download from ${source}\nError: $status"
          return 1
        ;;
      esac
    done
  fi # }}}3

  # Validate downloaded target checksum {{{3
  if [[ -r "${target_path}" && -n ${checksum} ]]; then
    verbose "  Calculating checksum of the downloaded file"
    target_checksum=$(bar -n "$target_path" | $checksum)
    if [[ ! $target_checksum =~ \s*$checksum_value\s* ]]; then
      error "Invalid ${document_checksum_type} checksum for the downloaded document"
      $NOOP $sudo rm -f "$target_path"
      return 1
    else
      echo -n "$target_checksum" | $sudo tee "${target_path}.$checksum_type" > /dev/null
    fi
  fi # }}}3

  # The download was a success, let's save the credentials in keychain
  if [[ $source_credentials_updated != 0 ]]; then
    keychain_set_password --kind=internet --protocol=$source_protocol --site=$source_host --user=$source_user --password=$source_password
    status=$? && [[ $status != 0 ]] && error "Could not save credentials.\nError: $status"
  fi
  return 0
} # }}}2

# }}}

# Module: Module Installers {{{

function dmg_install() # {{{2
{
  local source="$1"
  local target_dir="$HOME/Downloads"
  local filename
  local target
  local mount
  local package
  local plist_path

  filename=${source##*/}        # Remove everything up to the last /
  filename=${filename%%\?*}     # emove everything after the ? (including)
  target="${target_dir}/${filename}"

  download "$source" "$target_dir"
  status=$? && [[ $status != 0 ]] && return $status

  verbose "    Mounting ${target}"
  mount=$(hdiutil attach ${target} | sed -e 's/^\/.* \//\//')
  status=$? && [[ $status != 0 ]] && return $status
  verbose "      mounted on ${mount}"

  verbose "    Installing ${target}"
  local package=$(find ${mount} -name '*.pkg' -mindepth 1 -maxdepth 1)
  verbose "      Package: ${package}"
  $NOOP sudo installer -pkg ${package} -target /
  status=$? && [[ $status != 0 ]] && return $status

  verbose "    Unmounting ${target}"
  hdiutil eject ${mount} > /dev/null
  status=$? && [[ $status != 0 ]] && return $status
} # }}}2

function brew_install() # {{{2
{
  local app_name=$1
  local app_binary=${2:-$1}

  if [[ -z "$(brew info $app_name | grep '^Not installed$')" ]]; then
    verbose "$app_name is already installed via Homebrew"
  elif which "$app_binary" > /dev/null 2>&1; then
    verbose "$app_name was manually installed (no automatic updates possible)"
  else
    verbose "Installing $app_name"
    $NOOP brew install $app_binary
    status=$? && [[ $status != 0 ]] && return $status
  fi
  return 0
} # }}}2

function cask_install() # {{{2
{
  local app_name=$1
  local app_binary=${2:-$1}

  if [[ -z "$(brew cask info $app_name | grep '^Not installed$')" ]]; then
    verbose "$app_name is already installed via Homebrew"
  elif which "$app_binary" > /dev/null 2>&1; then
    verbose "$app_name was manually installed (no automatic updates possible)"
  else
    verbose "Installing $app_name"
    $NOOP brew install "Caskroom/cask/$app_name"
    status=$? && [[ $status != 0 ]] && return $status
  fi
  return 0
} # }}}2

function install_xcode_tools() # {{{2
{
  local downloaded=0
  local os_maj=$(sw_vers -productVersion | cut -d. -f1)
  local os_min=$(sw_vers -productVersion | cut -d. -f2)
  local product
  local url
  local mount

  if xcode-select -p > /dev/null 2>&1; then
    echo "XCode tools are already installed"
  elif [[ $os_min -ge 9 ]]; then # Mavericks or later
    verbose "Installing CLI tools via Software Update"
    verbose "  Finding proper version"
    touch /tmp/.com.apple.dt.CommandLinetools.installondemand.in-progress
    product=$(softwareupdate --list 2>&1 | grep "\*.*Command Line" | tail -1 | sed -e 's/^   \* //' | tr -d '\n')
    status=$? && [[ $status != 0 ]] && return $status
    verbose "  Downloading and Installing ${product}. You should get some coffee or tea as this might take a while..."
    $NOOP sudo softwareupdate --install "$product"
    status=$? && [[ $status != 0 ]] && return $status
  else # Older versions like Mountain Lion, Lion
    verbose "Installing XCode tools from Website"
    [[ $os_min == 7 ]] && url=http://devimages.apple.com/downloads/xcode/command_line_tools_for_xcode_os_x_lion_april_2013.dmg
    [[ $os_min == 8 ]] && url=http://devimages.apple.com/downloads/xcode/command_line_tools_for_osx_mountain_lion_april_2014.dmg
    $NOOP dmg_install $url
    status=$? && [[ $status != 0 ]] && return $status
  fi
  return 0
} # }}}2

function install_homebrew() # {{{2
{
  # Installing homebrew from http://brew.sh
  # prerequisites:
  install_xcode_tools
  status=$? && [[ $status != 0 ]] && return $status

  if which brew > /dev/null 2>&1; then
    if [[ ! -f "$CACHE_ROOT/last_updated-homebrew" || -n "$(find "$CACHE_ROOT/last_updated-homebrew" -mmin +240)" ]]; then
      verbose "Homebrew is already installed, upgrading..."
      $NOOP brew update && brew upgrade && brew cleanup
      status=$? && [[ $status != 0 ]] && return $status
      touch $CACHE_ROOT/last_updated-homebrew
    else
      verbose "Homebrew was updated less than 4 hours ago, let's give the Internet some rest..."
    fi
  else
    verbose "Installing Homebrew..."
    $NOOP ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    status=$? && [[ $status != 0 ]] && return $status

    # Preparing brew for first time or sanitizing it if already installed
    $NOOP brew doctor
    status=$? && [[ $status != 0 ]] && return $status
  fi

  # Installing bash completion
  if [[ ! -z $(brew info bash-completion | grep '^Not installed$') ]]; then
    verbose "Installing bash completion..."
    $NOOP brew install bash-completion
    status=$? && [[ $status != 0 ]] && return $status
  else
    verbose "Homebrew bash completion is already installed"
  fi

  if [[ -z $(brew tap | grep 'homebrew/completions') ]]; then
    brew tap homebrew/completions
    status=$? && [[ $status != 0 ]] && return $status
  fi

  if [[ -z $(brew tap | grep 'homebrew/binary') ]]; then
    brew tap homebrew/binary
    status=$? && [[ $status != 0 ]] && return $status
  fi

  # Installing Cask from http://caskroom.io
  if [[ -z $(brew tap | grep 'caskroom/cask') ]]; then
    brew tap caskroom/cask
    status=$? && [[ $status != 0 ]] && return $status
  fi

  if [[ ! -z $(brew info brew-cask | grep '^Not installed$') ]]; then
    verbose "Installing Homebrew Cask..."
    $NOOP brew install brew-cask
    status=$? && [[ $status != 0 ]] && return $status
  else
    verbose "Homebrew Cask is already installed"
  fi

  if [[ ! -z $(brew info bar | grep '^Not installed$') ]]; then
    verbose "Installing bar..."
    $NOOP brew install bar
    status=$? && [[ $status != 0 ]] && return $status
  else
    verbose "bar is already installed"
  fi

  # Installing jq for querying json from bash
  if [[ ! -z $(brew info jq | grep '^Not installed$') ]]; then
    verbose "Installing jq..."
    $NOOP brew install jq
    status=$? && [[ $status != 0 ]] && return $status
  else
    verbose "jq is already installed"
  fi
  MODULE_homebrew_done=1
  return 0
} # }}}2

function install_packer() # {{{2
{
  [[ $MODULE_homebrew_done  == 0 ]] && install_homebrew
  [[ $MODULE_rubytools_done == 0 ]] && install_rubytools
  [[ $MODULE_vagrant_done   == 0 ]] && install_vagrant

  brew_install packer
  status=$? && [[ $status != 0 ]] && return $status

  # Installing bash completion
  if [[ ! -z $(brew info homebrew/completions/packer-completion | grep '^Not installed$') ]]; then
    verbose "Installing bash completion for Packer..."
    $NOOP brew install homebrew/completions/packer-completion
    status=$? && [[ $status != 0 ]] && return $status
  fi

  packer_bindir=$(dirname $(which packer))
  if [[ ! -x $packer_bindir/packer-provisioner-wait ]]; then
    verbose "  Install Packer plugin: provisioner-wait"
    download https://cdn.rawgit.com/gildas/packer-provisioner-wait/master/bin/0.1.0/darwin/packer-provisioner-wait "${packer_bindir}"
    status=$? && [[ $status != 0 ]] && return $status
  fi

  packer_windows=${MODULE_PACKER_HOME}/packer-windows
  if [[ ! -d "$packer_windows" ]]; then
    echo "  Installing Packer framework for building Windows machines"
    $NOOP mkdir -p $(dirname $packer_windows)
    $NOOP git clone https://github.com/gildas/packer-windows $packer_windows
    status=$? && [[ $status != 0 ]] && return $status
  else
    echo "  Upgrading Packer framework for building Windows machines"
    $NOOP git --git-dir "${packer_windows}/.git" pull
    status=$? && [[ $status != 0 ]] && return $status
  fi

  if [[ "$MODULE_PACKER_HOME" != "$HOME/Documents/packer" ]]; then
    [[ -L "$HOME/Documents/packer" ]] || ln -s "$MODULE_PACKER_HOME" "$HOME/Documents/packer"
  fi

  if [[ -f "$packer_windows/Gemfile" ]]; then
    [[ -z "$NOOP" ]] && (cd $packer_windows ; bundle install)
    status=$? && [[ $status != 0 ]] && return $status
  fi
  MODULE_packer_done=1
  return 0
} # }}}2

function install_puppet() # {{{2
{
  local os_maj=$(sw_vers -productVersion | cut -d. -f1)
  local os_min=$(sw_vers -productVersion | cut -d. -f2)

  [[ $MODULE_homebrew_done == 0 ]] && install_homebrew

  verbose "installing facter, hiera, and puppet"
  cask_install puppet
  status=$? && [[ $status != 0 ]] && return $status
  cask_install hiera
  status=$? && [[ $status != 0 ]] && return $status
  cask_install facter
  status=$? && [[ $status != 0 ]] && return $status

  verbose "Creating user/group resources"
  dseditgroup -o read puppet &> /dev/null
  if [ $? -ne 0 ]; then
    verbose "  Creating group 'puppet'"
    $NOOP sudo puppet resource group puppet ensure=present
    status=$? && [[ $status != 0 ]] && return $status
  else
    verbose "  Group 'puppet' is already created"
  fi
  dseditgroup -o checkmember -m puppet puppet &> /dev/null
  if [ ! $? -eq 0 ]; then
    verbose "  Adding puppet to group 'puppet'"
    $NOOP sudo puppet resource user puppet ensure=present gid=puppet shell="/sbin/nologin"
    status=$? && [[ $status != 0 ]] && return $status
  else
    verbose "  User 'puppet' is already a member of group 'puppet'"
  fi

  verbose "Hiding the puppet user from the Login window"
  if [[ $os_min -ge 10 ]]; then # Yosemite or later
    if [[ -z $(dscl . read /Users/puppet | grep IsHidden) ]]; then
      sudo dscl . create /Users/puppet IsHidden 1
      status=$? && [[ $status != 0 ]] && return $status
    elif [[ -z $(dscl . read /Users/puppet IsHidden | grep 1) ]]; then
      sudo dscl . create /Users/puppet IsHidden 1
      status=$? && [[ $status != 0 ]] && return $status
    else
      verbose "  User puppet is already hidden from the Login window"
    fi
  else
    hidden_users=$(/usr/libexec/PlistBuddy -c "Print :HiddenUsersList" /Library/Preferences/com.apple.loginwindow.plist 2>&1)
    if [ ! $? -eq 0 ]; then
      verbose "  Adding the HiddenUsersList entry"
      $NOOP sudo /usr/libexec/PlistBuddy -c "Add :HiddenUsersList array" /Library/Preferences/com.apple.loginwindow.plist &> /dev/null
      status=$? && [[ $status != 0 ]] && return $status
    fi
    if [[ ! ${hidden_users} =~ "puppet" ]]; then
      verbose "  Adding puppet to the hidden user list"
      $NOOP sudo /usr/libexec/PlistBuddy -c "Add :HiddenUsersList: string puppet" /Library/Preferences/com.apple.loginwindow.plist &> /dev/null
      status=$? && [[ $status != 0 ]] && return $status
    else
      verbose "  User puppet is already hidden from the Login window"
    fi
  fi

  verbose "Creating folders"
  [[ ! -d /var/log/puppet ]]       && $NOOP sudo mkdir -p /var/log/puppet       && status=$? && [[ $status != 0 ]] && return $status
  [[ ! -d /var/lib/puppet ]]       && $NOOP sudo mkdir -p /var/lib/puppet       && status=$? && [[ $status != 0 ]] && return $status
  [[ ! -d /var/lib/puppet/cache ]] && $NOOP sudo mkdir -p /var/lib/puppet/cache && status=$? && [[ $status != 0 ]] && return $status
  [[ ! -d /etc/puppet/ssl ]]       && $NOOP sudo mkdir -p /etc/puppet/ssl       && status=$? && [[ $status != 0 ]] && return $status
  $NOOP sudo chown -R puppet:puppet /var/lib/puppet
  status=$? && [[ $status != 0 ]] && return $status
  $NOOP sudo chmod 750 /var/lib/puppet
  status=$? && [[ $status != 0 ]] && return $status
  $NOOP sudo chown -R puppet:puppet /var/log/puppet
  status=$? && [[ $status != 0 ]] && return $status
  $NOOP sudo chmod 750 /var/log/puppet
  status=$? && [[ $status != 0 ]] && return $status
  $NOOP sudo chown -R puppet:puppet /etc/puppet
  status=$? && [[ $status != 0 ]] && return $status
  $NOOP sudo chmod 750 /etc/puppet
  status=$? && [[ $status != 0 ]] && return $status

  verbose "Configuring Puppet"
  if [ ! -f "/etc/puppet/puppet.conf" ]; then
    config=$(mktemp -t puppet)
    puppet_master='puppet'
    #read -p "  Please enter the hostname or ip address of the puppet server [${puppet_master}]: " input_puppet_master
    #[[ ! -z "${input_puppet_master}" ]] && puppet_master=$input_puppet_master
    #read -p "  Please enter your userid [${userid}]: " input_userid
    #[[ ! -z "${input_userid}" ]] && userid=$input_userid
    #certname="osx-sandbox-${userid}"
    certname=$(basename $(uname -n) .local)
    verbose "  Configuring Puppet to connect to ${puppet_master} with certificate name: ${certname}"
    cat > ${config} << EOF
[main]
  pluginsync = true
  logdir     = /var/log/puppet
  rundir     = /var/run/puppet

[agent]
  server      = ${puppet_master}
  certname    = ${certname}
  report      = true
  runinterval = 300
EOF
    status=$? && [[ $status != 0 ]] && return $status
    $NOOP sudo install -m 0644 -o puppet -g puppet ${config} /etc/puppet/puppet.conf
    status=$? && [[ $status != 0 ]] && return $status
  fi

  verbose "Installing the puppet agent daemon"
  if [ ! -f "/Library/LaunchDaemons/com.puppetlabs.puppet.plist" ]; then
    download https://raw.github.com/inin-apac/puppet-me/master/config/osx/com.puppetlabs.puppet.plist "$HOME/Downloads"
    status=$? && [[ $status != 0 ]] && return $status
    $NOOP sudo install -m 0644 -o root -g wheel $HOME/Downloads/com.puppetlabs.puppet.plist /Library/LaunchDaemons
    status=$? && [[ $status != 0 ]] && return $status
    $NOOP sudo launchctl load -w /Library/LaunchDaemons/com.puppetlabs.puppet.plist
    status=$? && [[ $status != 0 ]] && return $status
  fi
  verbose "Starting the puppet agent daemon"
  $NOOP sudo launchctl start com.puppetlabs.puppet
  status=$? && [[ $status != 0 ]] && return $status
  MODULE_puppet_done=1
  return 0
} # }}}2

function install_rubytools() # {{{2
{
  [[ $MODULE_homebrew_done == 0 ]] && install_homebrew

  # On Mac OS/X, ruby is always installed. And since Mavericks, we get 2.0.0
  # Gem and Rake are also installed.
  if [[ ! -z $(gem list --local | grep bundler) ]]; then
    verbose "Bundler is already installed"
  else
    $NOOP sudo gem install bundler
    status=$? && [[ $status != 0 ]] && return $status
  fi
  MODULE_rubytools_done=1
  return 0
} # }}}2

function install_vagrant() # {{{2
{
  [[ $MODULE_homebrew_done == 0 ]]        && install_homebrew
  [[ $MODULE_virtualization_done == 0 ]]  && die "You must install at least one virtualization kit to install vagrant"

  if [[ -z "$VAGRANT_HOME" && "$MODULE_VAGRANT_HOME" != "$HOME/.vagrant.d" ]]; then
    if [[ "$MODULE_VAGRANT_HOME" =~ $HOME ]]; then
      if [[ -z "$(grep --no-messages VAGRANT_HOME $HOME/.bash_profile)" ]]; then
        echo "export VAGRANT_HOME=\"$MODULE_VAGRANT_HOME\"" | tee -a $HOME/.bash_profile > /dev/null
      fi
    else
      echo "export VAGRANT_HOME=\"$MODULE_VAGRANT_HOME\"" | sudo tee /etc/profile.d/vagrant.sh > /dev/null
    fi
  fi
  export VAGRANT_HOME="$MODULE_VAGRANT_HOME"

  cask_install vagrant
  status=$? && [[ $status != 0 ]] && return $status
  verbose "Updating installed Vagrant plugins..."
  $NOOP vagrant plugin update
  status=$? && [[ $status != 0 ]] && return $status

  # Installing bash completion
  if [[ ! -z $(brew info homebrew/completions/vagrant-completion | grep '^Not installed$') ]]; then
    verbose "Installing bash completion for Vagrant..."
    $NOOP brew install homebrew/completions/vagrant-completion
    status=$? && [[ $status != 0 ]] && return $status
  fi

  if [[ -z $(vagrant plugin list | grep 'vagrant-host-shell') ]]; then
    verbose "  Installing Vagrant Plugin for Host Shell"
    $NOOP vagrant plugin install vagrant-host-shell
    status=$? && [[ $status != 0 ]] && return $status
  fi

  if [[ $MODULE_vmware_done == 1 && -z $(vagrant plugin list | grep 'vagrant-vmware-fusion') ]]; then
    verbose "  Installing Vagrant Plugin for VMWare"
    $NOOP vagrant plugin install vagrant-vmware-fusion
    status=$? && [[ $status != 0 ]] && return $status
    warn "  TODO: install your Vagrant for VMWare license!"
  fi

  if [[ $MODULE_parallels_done == 1 && -z $(vagrant plugin list | grep 'vagrant-parallels') ]]; then
    verbose "  Installing Vagrant Plugin for Parallels"
    $NOOP vagrant plugin install vagrant-parallels
    status=$? && [[ $status != 0 ]] && return $status
  fi
  MODULE_vagrant_done=1
  return 0
} # }}}2

function install_parallels() # {{{2
{
  [[ $MODULE_homebrew_done == 0 ]] && install_homebrew

  cask_install parallels-desktop
  status=$? && [[ $status != 0 ]] && return $status

  if ! which prlsrvctl > /dev/null 2>&1; then
    verbose "Initializing Parallels Desktop"
    $NOOP sudo $HOME/Applications/Parallels\ Desktop.app/Contents/MacOS/inittool init -s
    status=$? && [[ $status != 0 ]] && return $status
  fi

  if [[ -n "$MODULE_PARALLELS_HOME" ]]; then
    current=$(prlsrvctl user list 2> /dev/null | grep "$whoami" | awk '{ print $3 }')
    if [[ "$current" != "$MODULE_PARALLELS_HOME" ]]; then
      verbose "Updating Virtual Machine home to ${MODULE_PARALLELS_HOME}"
      $NOOP mkdir -p "$MODULE_PARALLELS_HOME"
      $NOOP prlsrvctl user set --def-vm-home "$MODULE_PARALLELS_HOME"
      status=$? && [[ $status != 0 ]] && return $status
    fi
  fi
  MODULE_parallels_done=1
  MODULE_virtualization_done=1
  return 0
} # }}}2

function install_virtualbox() # {{{2
{
  [[ $MODULE_homebrew_done == 0 ]] && install_homebrew

  cask_install virtualbox
  status=$? && [[ $status != 0 ]] && return $status

  if [[ -n "$MODULE_VIRTUALBOX_HOME" ]]; then
    current=$(/usr/bin/VBoxManage list systemproperties | grep 'Default machine folder' | cut -d: -f2 | sed -e 's/^ *//')
    if [[ "$current" != "$MODULE_VIRTUALBOX_HOME" ]]; then
      verbose "Updating Virtual Machine home to ${MODULE_VIRTUALBOX_HOME}"
      $NOOP /usr/bin/VBoxManage setproperty machinefolder "$MODULE_VIRTUALBOX_HOME"
      status=$? && [[ $status != 0 ]] && return $status
    fi
  fi
  MODULE_virtualbox_done=1
  MODULE_virtualization_done=1
  return 0
} # }}}2

function install_vmware() # {{{2
{
  [[ $MODULE_homebrew_done == 0 ]] && install_homebrew

  cask_install vmware-fusion '/Applications/VMware Fusion.app/Contents/Library/vmrun'
  status=$? && [[ $status != 0 ]] && return $status

  if [[ -n "$MODULE_VMWARE_HOME" ]]; then
    current=$(defaults read com.vmware.fusion NSNavLastRootDirectory 2> /dev/null)
    if [[ "$current" != "$MODULE_VMWARE_HOME" ]]; then
      verbose "Updating Virtual Machine home to ${MODULE_VMWARE_HOME}"
      $NOOP sudo defaults write com.vmware.fusion NSNavLastRootDirectory "$MODULE_VMWARE_HOME"
      status=$? && [[ $status != 0 ]] && return $status
    fi
  fi
  MODULE_vmware_done=1
  MODULE_virtualization_done=1
} # }}}2

function cache_stuff() # {{{2
{
  [[ $MODULE_homebrew_done == 0 ]] && install_homebrew
  local nic_names nic_name nic_info nic_ip nic_mask ip_addresses ip_address ip_masks ip_mask

  verbose "Caching ISO files"
  [[ -d "$CACHE_ROOT" ]]                          || $NOOP sudo mkdir -p "$CACHE_ROOT"
  status=$? && [[ $status != 0 ]] && return $status
  [[ $(stat -f "%Sg" "$CACHE_ROOT") == 'admin' ]] || $NOOP sudo chgrp -R admin "$CACHE_ROOT"
  status=$? && [[ $status != 0 ]] && return $status
  [[ -w "$CACHE_ROOT" ]]                          || $NOOP sudo chmod -R g+w "$CACHE_ROOT"
  status=$? && [[ $status != 0 ]] && return $status
  download "$CACHE_SOURCE" "${CACHE_ROOT}"
  status=$? && [[ $status != 0 ]] && return $status
  document_catalog="${CACHE_ROOT}/sources.json"

  ip_addresses=( $NETWORK )
  ip_masks=()
  nic_names=(  $(/sbin/ifconfig | grep mtu | grep 'utun\d:' | cut -d: -f1) )
  for nic_name in ${nic_names[*]}; do
    nic_info=$( /sbin/ifconfig $nic_name | grep 'inet\s' | grep -v 127.0.0.1 )
    if [[ ! -z "$nic_info" ]]; then
      ip_addresses+=( "$(echo $nic_info | cut -d' ' -f2)/$( mask_hex2cidr $(echo $nic_info | cut -d' ' -f6 | cut -dx -f2) )" )
    fi
  done
  nic_names=( $(/sbin/ifconfig | grep mtu | grep 'en\d:'   | cut -d: -f1) )
  for nic_name in ${nic_names[*]}; do
    nic_info=$( /sbin/ifconfig $nic_name | grep 'inet\s' | grep -v 127.0.0.1 )
    if [[ ! -z "$nic_info" ]]; then
      ip_addresses+=( "$(echo $nic_info | cut -d' ' -f2)/$( mask_hex2cidr $(echo $nic_info | cut -d' ' -f4 | cut -dx -f2) )" )
    fi
  done
  verbose "IP Addresses: ${ip_addresses[*]}"

  document_ids=( $(jq '.[] | .id' "$document_catalog") )
  
  for document_id in ${document_ids[*]}; do
    document=$(jq ".[] | select(.id == $document_id)" "$document_catalog")
    document_name=$(echo "$document" | jq --raw-output '.name')
    verbose "Caching $document_name"
    sources_size=$( echo $document | jq '.sources | length' )
    source_location=''
    source_url=''
    if [[ $sources_size > 0 ]]; then
      for ip_address in ${ip_addresses[*]}; do
        for (( i=0; i < $sources_size; i++ )); do
          source=$( echo "$document" | jq ".sources[$i]" )
          source_network=$( echo "$source" | jq '.network' )
          if [[ \"$ip_address\" =~ $source_network  ]]; then
            source_location=$(echo "$source" | jq --raw-output '.location')
            source_url=$(echo "$source" | jq --raw-output '.url')
            source_has_resume=''
	    [[ "$(echo "$source" | jq '.has_resume')" == 'true' ]] && source_has_resume='--has_resume'
	    source_need_auth=''
	    [[ "$(echo "$source" | jq '.need_auth')" == 'true' ]] && source_need_auth='--need_auth'
            #debug   "  Matched $source_network from $ip_address at $source_location"
	    verbose "  Downloading from $source_location"
            break
          fi
        done
        [[ ! -z "$source_location" ]] && break
      done
    fi

    if [[ ! -z "$source_location" ]]; then
      document_destination=$(echo "$document" | jq --raw-output '.destination')
      trace "  Destination: ${document_destination}"
      [[ -z "$document_destination" || "$document_destination" == 'null' ]] && document_destination=$CACHE_ROOT
      [[ ! "$document_destination" =~ ^\/.* ]]                              && document_destination="${CACHE_ROOT}/${document_destination}"
      trace "  Destination: ${document_destination}"
      document_checksum=$(echo "$document" | jq --raw-output '.checksum.value')
      document_checksum_type=$(echo "$document" | jq --raw-output '.checksum.type')
      download $source_has_resume $source_need_auth $source_url "$document_destination" $document_checksum_type $document_checksum
      status=$? && [[ $status != 0 ]] && return $status
    else
      warn "Cannot cache $( echo "$document" | jq --raw-output '.name' ), no source available"
    fi
  done
  MODULE_cache_done=1
  return 0
} # }}}2

function set_noidle() # {{{2
{
  verbose "Setting Energy Saver for Mac Mini server"
  sudo pmset -c autorestart 1
  status=$? && [[ $status != 0 ]] && return $status
  sudo pmset -c sleep       0
  status=$? && [[ $status != 0 ]] && return $status
  sudo pmset -c disksleep   0
  status=$? && [[ $status != 0 ]] && return $status

  MODULE_noidle_done=1
  return 0
} # }}}2

# }}}

# Module: Argument parsing {{{

function usage() # {{{2
{
  echo "$(basename $0) [options]"
  echo "  Installs necessary software to run virtual machines" 
  echo "  Options are:"
  echo " --cache-root *path*  "
  echo "   Contains the location of the cache for ISO, MSI, etc files.  "
  echo "   Default /var/cache/daas"
  echo " --cache-source *url*  "
  echo "   Contains the URL of the configuration file for the cached sources.  "
  echo "   Default value: https://raw.githubusercontent.com/inin-apac/puppet-me/master/install/sources.json"
  echo " --help  "
  echo "   Prints some help on the output."
  echo " --macmini-parallels  "
  echo "   will install these modules: noidle homebrew rubytools puppet parallels vagrant cache packer"
  echo " --macmini-virtualbox  "
  echo "   will install these modules: noidle homebrew rubytools puppet virtualbox vagrant cache packer"
  echo " --macmini-vmware or --macmini  "
  echo "   will install these modules: noidle homebrew rubytools puppet vmware vagrant cache packer"
  echo " --modules  "
  echo "   contains a comma-separated list of modules to install.  "
  echo "   The complete list can be obtained with --help.  "
  echo "   The --macmini options will change that list.  "
  echo "   Default: homebrew,puppet,rubytools"
  echo " --network  *ip_address*/*cidr*"
  echo "   can be used to force the script to believe it is run in a given network.  "
  echo "   Both an ip address and a network (in the cidr form) must be given.  "
  echo "   Default: N/A."
  echo " --noop, --dry-run  "
  echo "   Do not execute instructions that would make changes to the system (write files, install software, etc)."
  echo " --packer-home *path*  "
  echo "   Contains the location where packer user work data will be stored.  "
  echo "   Default: \$HOME/Documents/packer"
  echo " --parallels-home *path*  "
  echo "   Contains the location virtual machine data will be stored.  "
  echo "   Default: \$HOME/Documents/Virtual Machines"
  echo " --quiet  "
  echo "   Runs the script without any message."
  echo " --userid *value*  "
  echo "   contains the default user for various authentications \(like cifs/smb\).  "
  echo "   Default: current user."
  echo " --vagrant-home *path*  "
  echo "   Contains the location where vagrant user work data will be stored.  "
  echo "   Default value: \$HOME/.vagrant.d"
  echo " --verbose  "
  echo "   Runs the script verbosely, that's by default."
  echo " --virtualbox-home *path*  "
  echo "   Contains the location virtual machine data will be stored.  "
  echo "   Default value: $HOME/Documents/Virtual Machines"
  echo " --vmware-home *path*  "
  echo "   Contains the location virtual machine data will be stored.  "
  echo "   Default value: $HOME/Documents/Virtual Machines"
  echo " --yes, --assumeyes, -y  "
  echo "   Answers yes to any questions automatiquely."
  echo ""
  echo "The possible modules are currently: "
  echo "${ALL_MODULES[*]}"
} # }}}2

function parse_args() # {{{2
{
  while :; do
    trace "Analyzing option \"$1\""
    case $1 in
      --userid|--user|-u)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing"
        userid=$2
        shift 2
        continue
      ;;
      --userid=*?|--user=*?)
        userid=${1#*=} # delete everything up to =
      ;;
      --userid=|--user=)
        die "Argument for option $1 is missing"
        ;;
      --macmini|macmini-vmware)
        MODULES=(noidle homebrew rubytools puppet vmware vagrant cache packer)
        ;;
      --macmini-parallels)
        MODULES=(noidle homebrew rubytools puppet parallels vagrant cache packer)
        ;;
      --macmini-virtualbox)
        MODULES=(noidle homebrew rubytools puppet virtualbox vagrant cache packer)
        ;;
      --macmini-all)
        MODULES=(noidle homebrew rubytools puppet parallels virtualbox vmware vagrant cache packer)
        ;;
      --modules)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing.\nIt is a comma-separated list of the possible values are: ${ALL_MODULES[*]}"
        MODULES=(${2//,/ })
        shift 2
        continue
        ;;
      --modules=*?)
        MODULES=${1#*=} # delete everything up to =
        MODULES=(${MODULES//,/ })
        ;;
      --modules=)
        die "Argument for option $1 is missing.\nIt is a comma-separated list of the possible values are: ${ALL_MODULES[*]}"
        ;;
      --network)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing."
        NETWORK=$2
        shift 2
        continue
        ;;
      --network=*?)
        NETWORK=${1#*=} # delete everything up to =
        ;;
      --network=)
        die "Argument for option $1 is missing."
        ;;
      --cache-root)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing."
        CACHE_ROOT=$2
        shift 2
        continue
        ;;
      --cache-root=*?)
        CACHE_ROOT=${1#*=} # delete everything up to =
        ;;
      --cache-root=)
        die "Argument for option $1 is missing."
        ;;
      --cache-source)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing."
        CACHE_SOURCE=$2
        shift 2
        continue
        ;;
      --cache-source=*?)
        CACHE_SOURCE=${1#*=} # delete everything up to =
        ;;
      --cache-source=)
        die "Argument for option $1 is missing."
        ;;
      --packer-home)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing."
        MODULE_PACKER_HOME=$2
        shift 2
        continue
        ;;
      --packer-home=*?)
        MODULE_PACKER_HOME=${1#*=} # delete everything up to =
        ;;
      --packer-home=)
        die "Argument for option $1 is missing."
        ;;
      --vagrant-home)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing."
        MODULE_VAGRANT_HOME=$2
        shift 2
        continue
        ;;
      --vagrant-home=*?)
        MODULE_VAGRANT_HOME=${1#*=} # delete everything up to =
        ;;
      --vagrant-home=)
        die "Argument for option $1 is missing."
        ;;
      --parallels-home)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing."
        MODULE_PARALLELS_HOME=$2
        shift 2
        continue
        ;;
      --parallels-home=*?)
        MODULE_PARALLELS_HOME=${1#*=} # delete everything up to =
        ;;
      --parallels-home=)
        die "Argument for option $1 is missing."
        ;;
      --virtualbox-home)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing."
        MODULE_VIRTUALBOX_HOME=$2
        shift 2
        continue
        ;;
      --virtualbox-home=*?)
        MODULE_VIRTUALBOX_HOME=${1#*=} # delete everything up to =
        ;;
      --virtualbox-home=)
        die "Argument for option $1 is missing."
        ;;
      --vmware-home)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing."
        MODULE_VMWARE_HOME=$2
        shift 2
        continue
        ;;
      --vmware-home=*?)
        MODULE_VMWARE_HOME=${1#*=} # delete everything up to =
        ;;
      --vmware-home=)
        die "Argument for option $1 is missing."
        ;;
      --noop|--dry-run)
        warn "This program will execute in dry mode, your system will not be modified"
        NOOP=:
        ;;
      --test-keychain)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing."
        user=$(keychain_get_user --kind=internet --url=$2)
        status=$?
        [[ $status != 0 ]] && exit $status
        if [[ -n "$user" ]]; then
          password=$(keychain_get_password --kind=internet --url=$2 --user=$user)
          status=$?
          [[ $status != 0 ]] && exit $status
        fi
        echo "URL: $2 => user=$user, password=$password"
        exit
        ;;
      --test-keychain=*?)
        ;;
      --test-keychain=)
        die "Argument for option $1 is missing."
        ;;
      -h|-\?|--help)
       trace "Showing usage"
       usage
       exit 0
       ;;
     --quiet)
       VERBOSE=0
       trace "Verbose level: $VERBOSE"
       ;;
     -v|--verbose)
       VERBOSE=$((VERBOSE + 1))
       trace "Verbose level: $VERBOSE"
       ;;
     -y|--yes|--assumeyes|--assume-yes) # All questions will get a "yes"  answer automatically
       ASSUMEYES=1
       trace "All prompts will be answered \"yes\" automatically"
       ;;
     -?*) # Invalid options
       warn "Unknown option $1 will be ignored"
       ;;
     --) # Force end of options
       shift
       break
       ;;
     *)  # End of options
       break
       ;;
    esac
    shift
  done
} # }}}2

# }}}

function main() # {{{
{
  trace_init "$@"
  parse_args "$@"

  dseditgroup -o checkmember -m $userid admin &> /dev/null
  if [[ $? != 0 ]]; then
    dseditgroup -o checkmember -m $userid wheel &> /dev/null
    if [[ $? != 0 ]]; then
      die "You must be a member of the sudoer group as this script will need to install software"
    fi
  fi
  warn "You might have to enter your password to verify you can install software"

  for module in ${MODULES[*]} ; do
    trace "Installing Module ${module}"
    case $module in
      noidle)     set_noidle ;;
      homebrew)   install_homebrew ;;
      cache)      cache_stuff ;;
      packer)     install_packer ;;
      parallels)  install_parallels ;;
      puppet)     install_puppet ;;
      rubytools)  install_rubytools ;;
      vagrant)    install_vagrant ;;
      virtualbox) install_virtualbox ;;
      vmware)     install_vmware ;;
      *)          die "Unsupported Module: ${module}" ;;
    esac
    status=$? && [[ $status != 0 ]] && die "Error $status while installing module $module" $status
  done
} # }}}
main "$@"
