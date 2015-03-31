#!/usr/bin/env bash

shopt -s extglob
set -o errtrace
#set -o errexit
set +o noclobber

export NOOP=

ASSUMEYES=0
VERBOSE=1
FORCE_UPDATE=0
LOG="$HOME/Downloads/puppet-me.log"
tmp="tmp"
puppet_master="puppet"
userid=$(whoami)

DOWNLOAD_MAX_ATTEMPTS=5
CURL="/usr/bin/curl --location --progress-bar "

MODULE_homebrew_done=0
MODULE_cache_done=0
MODULE_packer_done=0
MODULE_puppet_done=0
MODULE_rubytools_done=0
MODULE_vagrant_done=0
MODULE_parallels_done=0
MODULE_updateme_done=0
MODULE_virtualbox_done=0
MODULE_vmware_done=0
MODULE_virtualization_done=0

MODULES=(homebrew puppet rubytools)
ALL_MODULES=(homebrew cache noidle packer puppet rubytools vagrant virtualbox vmware parallels updateme)

CACHE_ROOT='/var/cache/daas'
CACHE_SOURCE='https://cdn.rawgit.com/inin-apac/puppet-me/f608740be2aa6966420c053771016ca900c3faf5/config/sources.json'
CACHE_MOUNTS=()
CONNECTED_VPNS=()

MODULE_VMWARE_HOME=''
MODULE_VMWARE_KEY=''
MODULE_VIRTUALBOX_HOME=''
MODULE_PARALLELS_HOME=''
MODULE_PACKER_VIRT=vmware
MODULE_PACKER_HOME="$HOME/Documents/packer"
[[ -n "$PACKER_HOME"    ]] && MODULE_PACKER_HOME="$PACKER_HOME"
MODULE_PACKER_BUILD=()
MODULE_PACKER_LOAD=()
MODULE_VAGRANT_HOME="$HOME/.vagrant.d"
[[ -n "$XDG_CONFIG_HOME" ]] && MODULE_VAGRANT_HOME="$XDG_CONFIG_HOME/vagrant"
[[ -n "$VAGRANT_HOME"    ]] && MODULE_VAGRANT_HOME="$VAGRANT_HOME"
MODULE_VAGRANT_VMWARE_LICENSE=''

MODULE_updateme_root="$HOME/Desktop"
MODULE_updateme_source='https://github.com/inin-apac/puppet-me/raw/ab0a2f58b93cace74f498c687eb053ae8c116c56/config/osx/UpdateMe.7z'
MODULE_updateme_args="$@"

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
  trace --trace-member "[BEGIN] --8<----------------------8<------------------------8<------------  [BEGIN]"
} # }}}

function trace_end() # {{{2
{
  for cache_mount in ${CACHE_MOUNTS[@]}; do
    trace --trace-member "Removing CIFS mount point: $cache_mount"
    umount $cache_mount 2>&1 > /dev/null
  done

  for vpn_id in ${CONNECTED_VPNS[@]}; do
    vpn_stop --id=$vpn_id
  done

  trace --trace-member "[END]   --8<----------------------8<------------------------8<------------    [END]"
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

function curl_get_error() # {{{2
{
  local error

  case $1 in
    0) error="All fine. Proceed as usual." ;;
    1) error="The URL you passed to libcurl used a protocol that this libcurl does not support. The support might be a compile-time option that you didn't use, it can be a misspelled protocol string or just a protocol libcurl has no code for." ;;
    2) error="Very early initialization code failed. This is likely to be an internal error or problem, or a resource problem where something fundamental couldn't get done at init time." ;;
    3) error="The URL was not properly formatted." ;;
    4) error="A requested feature, protocol or option was not found built-in in this libcurl due to a build-time decision. This means that a feature or option was not enabled or explicitly disabled when libcurl was built and in order to get it to function you have to get a rebuilt libcurl." ;;
    5) error="Couldn't resolve proxy. The given proxy host could not be resolved." ;;
    6) error="Couldn't resolve host. The given remote host was not resolved." ;;
    7) error="Failed to connect() to host or proxy." ;;
    8) error="After connecting to a FTP server, libcurl expects to get a certain reply back. This error code implies that it got a strange or bad reply. The given remote server is probably not an OK FTP server." ;;
    9) error="We were denied access to the resource given in the URL. For FTP, this occurs while trying to change to the remote directory." ;;
    10) error="While waiting for the server to connect back when an active FTP session is used, an error code was sent over the control connection or similar." ;;
    11) error="After having sent the FTP password to the server, libcurl expects a proper reply. This error code indicates that an unexpected code was returned." ;;
    12) error="During an active FTP session while waiting for the server to connect, the CURLOPT_ACCEPTTIMOUT_MS(3) (or the internal default) timeout expired." ;;
    13) error="libcurl failed to get a sensible result back from the server as a response to either a PASV or a EPSV command. The server is flawed." ;;
    14) error="FTP servers return a 227-line as a response to a PASV command. If libcurl fails to parse that line, this return code is passed back." ;;
    15) error="An internal failure to lookup the host used for the new connection." ;;
    16) error="A problem was detected in the HTTP2 framing layer. This is somewhat generic and can be one out of several problems, see the error buffer for details." ;;
    17) error="Received an error when trying to set the transfer mode to binary or ASCII." ;;
    18) error="A file transfer was shorter or larger than expected. This happens when the server first reports an expected transfer size, and then delivers data that doesn't match the previously given size." ;;
    19) error="This was either a weird reply to a 'RETR' command or a zero byte transfer complete." ;;
    21) error="When sending custom "QUOTE" commands to the remote server, one of the commands returned an error code that was 400 or higher (for FTP) or otherwise indicated unsuccessful completion of the command." ;;
    22) error="This is returned if CURLOPT_FAILONERROR is set TRUE and the HTTP server returns an error code that is >= 400." ;;
    23) error="An error occurred when writing received data to a local file, or an error was returned to libcurl from a write callback." ;;
    25) error="Failed starting the upload. For FTP, the server typically denied the STOR command. The error buffer usually contains the server's explanation for this." ;;
    26) error="There was a problem reading a local file or an error returned by the read callback." ;;
    27) error="A memory allocation request failed. This is serious badness and things are severely screwed up if this ever occurs." ;;
    28) error="Operation timeout. The specified time-out period was reached according to the conditions." ;;
    30) error="The FTP PORT command returned error. This mostly happens when you haven't specified a good enough address for libcurl to use. See CURLOPT_FTPPORT." ;;
    31) error="The FTP REST command returned error. This should never happen if the server is sane." ;;
    33) error="The server does not support or accept range requests." ;;
    34) error="This is an odd error that mainly occurs due to internal confusion." ;;
    35) error="A problem occurred somewhere in the SSL/TLS handshake. You really want the error buffer and read the message there as it pinpoints the problem slightly more. Could be certificates (file formats, paths, permissions), passwords, and others." ;;
    36) error="The download could not be resumed because the specified offset was out of the file boundary." ;;
    37) error="A file given with FILE:// couldn't be opened. Most likely because the file path doesn't identify an existing file. Did you check file permissions?" ;;
    38) error="LDAP cannot bind. LDAP bind operation failed." ;;
    39) error="LDAP search failed." ;;
    41) error="Function not found. A required zlib function was not found." ;;
    42) error="Aborted by callback. A callback returned "abort" to libcurl." ;;
    43) error="Internal error. A function was called with a bad parameter." ;;
    45) error="Interface error. A specified outgoing interface could not be used. Set which interface to use for outgoing connections' source IP address with CURLOPT_INTERFACE." ;;
    47) error="Too many redirects. When following redirects, libcurl hit the maximum amount. Set your limit with CURLOPT_MAXREDIRS." ;;
    48) error="An option passed to libcurl is not recognized/known. Refer to the appropriate documentation. This is most likely a problem in the program that uses libcurl. The error buffer might contain more specific information about which exact option it concerns." ;;
    49) error="A telnet option string was Illegally formatted." ;;
    51) error="The remote server's SSL certificate or SSH md5 fingerprint was deemed not OK." ;;
    52) error="Nothing was returned from the server, and under the circumstances, getting nothing is considered an error." ;;
    53) error="The specified crypto engine wasn't found." ;;
    54) error="Failed setting the selected SSL crypto engine as default!" ;;
    55) error="Failed sending network data." ;;
    56) error="Failure with receiving network data." ;;
    58) error="problem with the local client certificate." ;;
    59) error="Couldn't use specified cipher." ;;
    60) error="Peer certificate cannot be authenticated with known CA certificates." ;;
    61) error="Unrecognized transfer encoding." ;;
    62) error="Invalid LDAP URL." ;;
    63) error="Maximum file size exceeded." ;;
    64) error="Requested FTP SSL level failed." ;;
    65) error="When doing a send operation curl had to rewind the data to retransmit, but the rewinding operation failed." ;;
    66) error="Initiating the SSL Engine failed." ;;
    67) error="The remote server denied curl to login (Added in 7.13.1)" ;;
    68) error="File not found on TFTP server." ;;
    69) error="Permission problem on TFTP server." ;;
    70) error="Out of disk space on the server." ;;
    71) error="Illegal TFTP operation." ;;
    72) error="Unknown TFTP transfer ID." ;;
    73) error="File already exists and will not be overwritten." ;;
    74) error="This error should never be returned by a properly functioning TFTP server." ;;
    75) error="Character conversion failed." ;;
    76) error="Caller must register conversion callbacks." ;;
    77) error="Problem with reading the SSL CA cert (path? access rights?)" ;;
    78) error="The resource referenced in the URL does not exist." ;;
    79) error="An unspecified error occurred during the SSH session." ;;
    80) error="Failed to shut down the SSL connection." ;;
    81) error="Socket is not ready for send/recv wait till it's ready and try again. This return code is only returned from curl_easy_recv and curl_easy_send (Added in 7.18.2)" ;;
    82) error="Failed to load CRL file (Added in 7.19.0)" ;;
    83) error="Issuer check failed (Added in 7.19.0)" ;;
    84) error="The FTP server does not understand the PRET command at all or does not support the given argument. Be careful when using CURLOPT_CUSTOMREQUEST, a custom LIST command will be sent with PRET CMD before PASV as well. (Added in 7.20.0)" ;;
    85) error="Mismatch of RTSP CSeq numbers." ;;
    86) error="Mismatch of RTSP Session Identifiers." ;;
    87) error="Unable to parse FTP file list (during FTP wildcard downloading)." ;;
    88) error="Chunk callback reported error." ;;
    89) error="(For internal use only, will never be returned by libcurl) No connection available, the session will be queued. (added in 7.30.0)" ;;
    .*) error="Unknown error $1" ;;
  esac
  printf -- %s "$error"
} # }}}2

function canonicalize_path() # {{{2
{
  local path=$1

  while [ -h "$file" ]; do
    path=$(readlink -- "$path")
  done

  local folder=$(dirname -- "$path")
  printf -- %s "$(cd -- "$folder" && pwd -P)/$(basename -- "$path")"
} # }}}2

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
  local title='DaaS Me!'
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
      --title)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "$FUNCNAME: Argument for option $1 is missing" && return 1
        title=$2
        shift 2
        continue
      ;;
      --title=*?)
        title=${1#*=} # delete everything up to =
      ;;
      --title=)
        error "$FUNCNAME: Argument for option $1 is missing"
        return 1
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
  trace "Query: ${query}, Default: ${default}, Silent: ${silent}"
  if [[ -z "$SSH_CLIENT" ]]; then
    # We are on the Mac screen
    trace "Prompting with GUI"
    [[ -n $silent ]] && silent='with hidden answer'
    script="Tell application \"System Events\" to display dialog \"${query/\\/\\\\}\" giving up after 119 with title \"${title}\" with icon 0 ${silent} default answer \"${default/\\/\\\\}\""
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
  if [[ -n "$silent" ]]; then
    trace "Results: XXXXXXXXXX"
  else
    trace "Results: ${value}"
  fi
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
  if [[ -z "$service" ]]; then # {{{4
    error "option service cannot be empty"
    return 2
  fi # }}}4
  # }}}3
  trace "Searching $kind user $user @ $service protocol: $protocol"
  if [[ $command == 'find-internet-password' ]]; then
    trace "Key Type is internet, analyzing protocol $protocol"
    case $protocol in
      http)            user=$(/usr/bin/security $command -r "$protocol" -s "$service") ;;
      https|htps)      user=$(/usr/bin/security $command -r "htps" -s "$service") ;;
      cifs)            user=$(/usr/bin/security $command -r "smb " -s "$service") ;;
      afp|ftp|smb|ssh) user=$(/usr/bin/security $command -r "$protocol " -s "$service") ;;
      *)               user=$(/usr/bin/security $command -s "$service") ;;
    esac
  else
    user=$(/usr/bin/security $command -s "$service")
  fi
  status=$?
  [[ $status != 0 ]] && trace "$(/usr/bin/security error $status)" && return $status
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
  if [[ -z "$service" ]]; then # {{{4
    error "option service cannot be empty"
    return 2
  fi # }}}4
  if [[ -z "$user" ]]; then # {{{4
    error "option user cannot be empty"
    return 2
  fi # }}}4
  # }}}3
  trace "Searching password for $kind user $user @ $service protocol: $protocol"
  trace "Exec: [/usr/bin/security $command -r "$protocol" -s \"$service\" -a \"$user\" -w]"
  if [[ $command == 'find-internet-password' ]]; then
    trace "Key Type is internet, analyzing protocol $protocol"
    case $protocol in
      http)            password=$(/usr/bin/security $command -r "$protocol" -s "$service" -a "$user" -w) ;;
      https|htps)      password=$(/usr/bin/security $command -r "htps" -s "$service" -a "$user" -w) ;;
      cifs)            password=$(/usr/bin/security $command -r "smb " -s "$service" -a "$user" -w) ;;
      afp|ftp|smb|ssh) password=$(/usr/bin/security $command -r "$protocol " -s "$service" -a "$user" -w) ;;
      *)               password=$(/usr/bin/security $command -s "$service" -w) ;;
    esac
  else
    password=$(/usr/bin/security $command -s "$service" -w)
  fi
  status=$?
  [[ $status != 0 ]] && trace "$(/usr/bin/security error $status)" && return $status
  trace "Found password for $user @ $service: XXXXXX"
  printf '%s' $password
} # }}}2

function keychain_echo_credentials() # {{{2
{
  local status
  local url=$1
  local user
  local password

  user=$(keychain_get_user --kind=internet --url=${url})
  status=$?
  [[ $status != 0 ]] && exit $status
  if [[ -n "$user" ]]; then
    password=$(keychain_get_password --kind=internet --url=${url} --user=${user})
    status=$?
    [[ $status != 0 ]] && exit $status
  fi
  echo "URL: $url => user=$user, password=$password"
} # }}}2

function keychain_set_password() # {{{2
{
  local service
  local path
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
      --path)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        path=$2
        shift 2
        continue
      ;;
      --path=*?)
        path=${1#*=} # delete everything up to =
      ;;
      --path=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      --protocol)
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
  trace "Updating password for $kind user $user @ $service protocol: $protocol"
  trace "Exec: [/usr/bin/security $command -r "$protocol" -s \"$service\" -a \"$user\" -w XXXX]"
  if [[ $command == 'add-internet-password' ]]; then
    trace "Key Type is internet, analyzing protocol $protocol"
    case $protocol in
      http)       /usr/bin/security $command -U -r "$protocol"  -s "$service" -a "$user" -w "$password" ;;
      https|htps) /usr/bin/security $command -U -r "htps"       -s "$service" -a "$user" -w "$password" ;;
      cifs)       /usr/bin/security $command -U -r "smb "       -s "$service" -a "$user" -w "$password" -D "network password" -p $path ;;
      ftp|ssh)    /usr/bin/security $command -U -r "$protocol " -s "$service" -a "$user" -w "$password" ;;
      afp|smb)    /usr/bin/security $command -U -r "$protocol " -s "$service" -a "$user" -w "$password" -D "network password" -p $path ;;
      *)          /usr/bin/security $command -U                 -s "$service" -a "$user" -w "$password" ;;
    esac
  else
    /usr/bin/security $command -U -s "$service" -a "$user" -w "$password"
  fi
  status=$?
  [[ $status != 0 ]] && trace "$(/usr/bin/security error $status)" && return $status
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
  trace ">> source: ${source}"
  source_protocol=${source%%:*}
  trace ">> source protocol: ${source_protocol}"

  if [[ $source =~ ^\/\/.* ]] ; then
    trace ">> Missing protocol, assuming smb/cifs"
    source="smb:${source}"
    source_protocol="smb"
    trace ">> source protocol: ${source_protocol}"
  elif [[ $source_protocol == $source ]] ; then
    trace ">> Missing protocol, assuming file and getting absolute path"
    # no readlink -e on Mac OS!
    source="$(cd "$(dirname "$source")" ; pwd)/$(basename ${source})"
    trace "  Absolute path: ${source}"
    source="file://${source/ /+}"
    source_protocol="file"
    trace "  with protocol: ${source}"
    trace ">> source protocol: ${source_protocol}"
  fi

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
        trace "  >> source_password: XXXXXXXX"
      fi
      if [[ "${source_user}" =~ .*\;.* ]]; then       # search for domain
        source_domain=${source_user%;*}               # extract domain
        source_user=${source_user#*;}                 # extract user
        trace "  >> source_domain: ${source_domain}"
      fi
      trace "  >> source_user [from URL]: ${source_user}"
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
        trace "  >> source_user [from keychain]: ${source_user}"
      fi
    fi
    if [[ -z "$source_password" && -n "$source_user" ]]; then
      trace "  Querying keychain for password for user $source_user on site $source_host over $source_protocol"
      source_password=$(keychain_get_password --kind=internet --protocol=$source_protocol --site=$source_host --user=$source_user)
      status=$?
      if [[ $status != 0 ]]; then
        trace "  Error $status: No password for use $source_user"
        source_password=''
      else
        trace "  >> source_password [from keychain]: XXXXXX"
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
    verbose "Creating folder ${target}"
    # Here we are a bit lazy and choose the admin group which of the user has to be a member
    if ! mkdir -p "$target" 2>&1 > /dev/null; then
      sudo='sudo'
      $NOOP sudo mkdir -p "$target"
    fi
    $NOOP $sudo chgrp -R admin "$target"
    $NOOP $sudo chmod -R g+w "$target"
    sudo=''
    [[ -w "$target" ]] || sudo='sudo'
  fi # }}}3

  # Validate checksum  # {{{3
  case $checksum_type in
    MD5|md5)   checksum='md5';;
    SHA1|sha1) checksum='shasum';;
    null|'')   checksum=''; checksum_value=''; checksum_type='';;
    *)
    error "Unsupported checksum type $checksum_type while downloading $filename"
    return 1
  esac
  trace "Expect ${checksum_type:-no} checksum${checksum_type:+: }$checksum_value"

  if [[ -r "${target_path}" && ! -z ${checksum} ]]; then
    if [[ ! -f "${target_path}.${checksum_type}" ]]; then
      verbose "  Calculating checksum of the file that is already cached"
      target_checksum=$(bar -n "$target_path" | $checksum)
      echo -n "$target_checksum" | $sudo tee "${target_path}.$checksum_type" > /dev/null
    else
      verbose "  Loading checksum of the file that is already cached"
      target_checksum=$(cat "${target_path}.$checksum_type")
      trace "  cached checksum: ${target_checksum}"
    fi
    if [[ $target_checksum =~ \s*$checksum_value\s* ]]; then
      verbose "  File already cached and checksum verified"
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
      local attempt=0
      while [[ $attempt < $DOWNLOAD_MAX_ATTEMPTS ]]; do
        if [[ $need_auth == 1 ]]; then
          if [[ -z "$source_password" ]]; then
            verbose "  Requesting credentials for //${source_host}/${source_share}"
            source_user=$(prompt --default="$source_user" --title "Downloading $filename" "User for mounting ${source_share} on ${source_host}")
            if [[ $? != 0 ]]; then
              warn "User cancelled prompt operation"
              return 0
            fi
            source_password=$(prompt -s --title "Downloading $filename" "Password for ${source_user}")
            if [[ $? != 0 ]]; then
              warn "User cancelled prompt operation"
              return 0
            fi
            source_credentials_updated=1
            echo
          fi
          smb_creds="${source_user/\\/;}:${source_password//@/%40}@"
        fi
        smb_mount="//${smb_creds}${source_host}/${source_share}"
        smb_target="/Volumes/WindowsShare-${source_host}-${source_share}.$$"

        verbose "  Mounting ${source_share} from ${source_host} ${source_user:+as }${source_user} (attempt: ${attempt}/${DOWNLOAD_MAX_ATTEMPTS})"
        trace ">> mount -t smbfs '//${source_user/\\/;}${source_password:+:XXXXX}${source_user:+@}${source_host}/${source_share}' $smb_target"
        mkdir -p $smb_target && mount -t smbfs  "${smb_mount}" $smb_target
        status=$?
        case $status in
          0)
            trace "//${source_host}/${source_share} Successfully mounted"
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
	    ((attempt++))
          ;;
        esac
      done
      if [[ $status != 0 ]]; then
        error "  Cannot mount ${source_share} after $((attempt + 1)) attempts. Last Error: ${status}"
        return $status
      fi
    else
      smb_target=$(mount | grep -i $source_host | grep -i $source_share | awk '{print $3}')
      verbose "  ${source_share} is already mounted on ${smb_target}"
    fi
    verbose "  Copying $filename"
    if [[ $filename =~ [\*\?] ]]; then
      verbose "  Filename contains wildcards"
      errors=0
      for _filename in ${smb_target}/${source_path}/$filename; do
        verbose "  Copying $(basename $_filename)"
        trace $sudo $CURL $has_resume --output "${target}/$(basename $_filename)" "file://$_filename"
        $NOOP $sudo $CURL $has_resume --output "${target}/$(basename $_filename)" "file://$_filename"
        status=$? && [[ $status != 0 ]] && error "Failed to download $filename.\nError $status: $(curl_get_error $status)" && ((errors++))
        $NOOP $sudo chmod 664 "${target}/$(basename $_filename)"
        status=$? && [[ $status != 0 ]] && error "Failed to set permission on $filename.\nError: $status" && ((errors++))
      done
      [[ errors == 1 ]] && return 1
    else
      trace $sudo $CURL $has_resume --output "${target_path}" "file://${smb_target}/${source_path}/$filename"
      $NOOP $sudo $CURL $has_resume --output "${target_path}" "file://${smb_target}/${source_path}/$filename"
      status=$? && [[ $status != 0 ]] && error "Failed to download $filename.\nError $status: $(curl_get_error $status)" && return $status
      $NOOP $sudo chmod 664 "${target_path}"
      status=$? && [[ $status != 0 ]] && error "Failed to set permission on $filename.\nError: $status" && return $status
    fi
  # }}}3
  elif [[ ${source_protocol} == 'file' ]]; then # {{{3
    if [[ -n "${filename_path}" ]]; then
      source=${source#*://}                     # remove protocol
      source_ext=${source##*\.}                 # extract extension
      verbose "Archive type: ${source_ext}"
      case $source_ext in
        iso|ISO)
          verbose "Mounting ISO ${source}"
          mount_info=$(hdiutil mount ${source})
          status=$? && [[ $status != 0 ]] && error "Failed to mount ISO file ${source}\nError: $status" && return $status
          mount_path=$(echo "$mount_info" | awk '{print $2}')
          trace "mount info: ${mount_info}"
          trace "mount path: ${mount_path}"
          trace $sudo $CURL $has_resume --output "${target_path}" "file://${mount_path}/${filename_path}"
          $NOOP $sudo $CURL $has_resume --output "${target_path}" "file://${mount_path}/${filename_path}"
          status=$? && [[ $status != 0 ]] && error "Failed to copy ${filename_path}\nError $status: $(curl_get_error $status)" && return $status
          $NOOP $sudo chmod 664 "${target_path}"
          status=$? && [[ $status != 0 ]] && error "Failed to set permission on ${filename_path}.\nError: $status" && return $status
          results=$(hdiutil unmount ${mount_path})
          status=$? && [[ $status != 0 ]] && error "Cannot unmount ${source}.\nError: $status" && return $status
        ;;
        *)
          error "Unsupported archive format in ${source}"
          return 1
        ;;
      esac
    else
      trace $sudo $CURL $has_resume --output "${target_path}" "${source}"
      $NOOP $sudo $CURL $has_resume --output "${target_path}" "${source}"
      status=$? && [[ $status != 0 ]] && error "Failed to copy ${source}\nError $status: $(curl_get_error $status)" && return $status
      $NOOP $sudo chmod 664 "${target_path}"
      status=$? && [[ $status != 0 ]] && error "Failed to set permission on ${source}\nError: $status" && return $status
    fi
  # }}}3
  else # other urls (http, https, ftp) {{{3
    local attempt=0
    while [[ $attempt < $DOWNLOAD_MAX_ATTEMPTS ]]; do
      verbose "  Copying from url location (attempt: ${attempt}/${DOWNLOAD_MAX_ATTEMPTS})"
      curl_creds=''
      if [[ $need_auth == 1 ]]; then
        if [[ -z "$source_password" ]]; then
          verbose "  Requesting credentials for ${source_host}"
          source_user=$(prompt --default="$source_user" --title "Downloading $filename" "User to download from ${source_host}")
          if [[ $? != 0 ]]; then
            warn "User cancelled prompt operation"
            return 0
          fi
          source_password=$(prompt -s --title "Downloading $filename" "Password for ${source_user}")
          if [[ $? != 0 ]]; then
            warn "User cancelled prompt operation"
            return 0
          fi
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
          error "  Unable to download from ${source}\nError $status: $(curl_get_error $status)"
	  ((attempt++))
        ;;
      esac
    done
    if [[ $status != 0 ]]; then
      error "  Cannot download ${source} after $((attempt + 1)) attempts. Last Error: ${status}"
    fi
    return $status
  fi # }}}3

  # Validate downloaded target checksum {{{3
  if [[ -r "${target_path}" && -n ${checksum} ]]; then
    verbose "  Calculating checksum of the downloaded file"
    target_checksum=$(bar -n "$target_path" | $checksum)
    trace "  Downloaded checksum: ${target_checksum} (Expected: ${checksum_value})"
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
    if [[ -n $source_share ]]; then
      keychain_set_password --kind=internet --protocol=$source_protocol --site=$source_host --path="$source_share" --user=$source_user --password=$source_password
    else
      keychain_set_password --kind=internet --protocol=$source_protocol --site=$source_host --user=$source_user --password=$source_password
    fi
    status=$? && [[ $status != 0 ]] && error "Could not save credentials.\nError: $status"
  fi
  return 0
} # }}}2

function vpn_find_by_server() #{{{2
{
  trace "Looking for VPNs that match server: $1"
  local vpn_server
  local vpn_ids=( $(/usr/sbin/scutil --nc list | grep IPSec | awk '{print $3}') )

  for vpn_id in ${vpn_ids[*]} ; do
    trace "Checking VPN $vpn_id"
    vpn_server=$(/usr/sbin/scutil --nc show $vpn_id | awk '/RemoteAddress/ { print $3 }')
    if [[ $vpn_server =~ $1 ]]; then
      trace "VPN ${vpn_id} matched $1"
      printf -- %s "$vpn_id"
      return 0
    fi
  done
  error "No VPN has a server matching \"$1\""
  return 1
} # }}}2

function vpn_get_name() #{{{2
{
  printf %s "$(/usr/sbin/scutil --nc show $1 | head -1 | sed 's/[^"]*"//' | sed 's/".*//')"
} # }}}2

function vpn_start() #{{{2
{
  local vpn_id
  local user
  local password

  while :; do # Parse aguments {{{3
    case $1 in
      --id)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        vpn_id=$2
        shift 2
        continue
      ;;
      --id=*?)
        vpn_id=${1#*=} # delete everything up to =
      ;;
      --id=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      --server)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        vpn_id=$(vpn_find_by_server "$2")
        status=$? && [[ $status != 0 ]] && return $status
        shift 2
        continue
      ;;
      --server=*?)
        vpn_id=$(vpn_find_by_server "${1#*=}") # delete everything up to =
        status=$? && [[ $status != 0 ]] && return $status
      ;;
      --server=)
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
  if [[ -z "$vpn_id" ]]; then # {{{4
    error "At least one of these options must be given: --server, --id"
    return 2
  fi # }}}4
  # }}}3

  local vpn_name=$(vpn_get_name $vpn_id)
  printf %s "Starting VPN ${vpn_name}..."
  trace "Starting VPN ${vpn_name} [$vpn_id]"
  /usr/sbin/scutil --nc start $vpn_id
  status=$? && [[ $status != 0 ]] && return $status
  loop=0
  while :; do
    sleep 5
    if [[ -n $(/usr/sbin/scutil --nc status $vpn_id | grep '^Connected$') ]]; then
      verbose "  Connected!"
      CONNECTED_VPNS+=( $vpn_id )
      trace "Connected VPNs: ${CONNECTED_VPNS[@]}"
      return 0
    fi
    printf %s '.'
    trace "Still nothing at loop $loop"
    ((loop++))
    if [[ $loop > 6 ]]; then
      error "Timeout while connecting to VPN $vpn_name"
      return 1
    fi
  done
  error "Cannot connect to VPN $vpn_name"
  return 1
} # }}}2

function vpn_stop() #{{{2
{
  local vpn_id

  while :; do # Parse aguments {{{3
    case $1 in
      --id)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        vpn_id=$2
        shift 2
        continue
      ;;
      --id=*?)
        vpn_id=${1#*=} # delete everything up to =
      ;;
      --id=)
        error "${FUNCNAME}: Argument for option $1 is missing"
        return 1
        ;;
      --server)
        [[ -z $2 || ${2:0:1} == '-' ]] && error "${FUNCNAME}: Argument for option $1 is missing" && return 1
        vpn_id=$(vpn_find_by_server "$2")
        status=$? && [[ $status != 0 ]] && return $status
        shift 2
        continue
      ;;
      --server=*?)
        vpn_id=$(vpn_find_by_server "${1#*=}") # delete everything up to =
        status=$? && [[ $status != 0 ]] && return $status
      ;;
      --server=)
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
  if [[ -z "$vpn_id" ]]; then # {{{4
    error "At least one of these options must be given: --server, --id"
    return 2
  fi # }}}4
  # }}}3

  local vpn_name=$(vpn_get_name $vpn_id)
  verbose "Stopping VPN ${vpn_name}..."
  /usr/sbin/scutil --nc stop $vpn_id
  status=$? && [[ $status != 0 ]] && return $status
  i=0
  for id in ${CONNECTED_VPNS[@]} ; do
    if [[ $id == $vpn_id ]]; then
      unset CONNECTED_VPNS[$i]
      trace "Connected VPNs: ${CONNECTED_VPNS[@]}"
    fi
    ((i++))
  done
  verbose "Stopped VPN ${vpn_name}"
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
  mount=$(hdiutil attach "${target}" | sed -e 's/^\/.* \//\//')
  status=$? && [[ $status != 0 ]] && return $status
  verbose "      mounted on ${mount}"

  verbose "    Installing ${target}"
  local package=$(find "${mount}" -name '*.pkg' -mindepth 1 -maxdepth 1)
  verbose "      Package: ${package}"
  $NOOP sudo installer -pkg "${package}" -target /
  status=$? && [[ $status != 0 ]] && return $status

  verbose "    Unmounting ${target}"
  hdiutil eject "${mount}" > /dev/null
  status=$? && [[ $status != 0 ]] && return $status
} # }}}2

function brew_install() # {{{2
{
  local app_name=$1
  local app_binary=${2:-$1}

  if [[ -z "$(brew info $app_name | grep '^Not installed$')" ]]; then
    verbose "$app_name is already installed via Homebrew"
  elif which "$app_binary" > /dev/null 2>&1; then
    verbose "$app_name was manually installed \(no automatic updates possible\)"
  else
    verbose "Installing $app_name"
    $NOOP brew install --appdir=/Applications $app_binary
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
  local filestamp="/usr/local/last_updated-homebrew"
  # Installing homebrew from http://brew.sh
  # prerequisites:
  install_xcode_tools
  status=$? && [[ $status != 0 ]] && return $status

  if which brew > /dev/null 2>&1; then

    trace "Force Update: $FORCE_UPDATE"
    [[ -f $filestamp ]] && trace "filestamp: $filestamp, $(stat -f "%Sm" $filestamp)"
    if [[ $FORCE_UPDATE == "1" || ! -f $filestamp || -n "$(find "$filestamp" -mmin +240)" ]]; then
      verbose "Homebrew is already installed, upgrading..."
      $NOOP brew update && brew upgrade && brew cleanup
      status=$? && [[ $status != 0 ]] && return $status
      touch $filestamp
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

  # Installing 7zip for querying json from bash
  if [[ ! -z $(brew info p7zip | grep '^Not installed$') ]]; then
    verbose "Installing 7-Zip..."
    $NOOP brew install p7zip
    status=$? && [[ $status != 0 ]] && return $status
  else
    verbose "7-Zip is already installed"
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
    chmod 755 "${packer_bindir}/packer-provisioner-wait"
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

  if [[ ${#MODULE_PACKER_BUILD[@]} > 0 || ${#MODULE_PACKER_LOAD[@]} > 0 ]]; then

    verbose "Going to packer windows"
    pushd "$packer_windows"

    for task in ${MODULE_PACKER_BUILD[@]} ; do
      verbose "Building $task"
      trace "Executing: rake build:$task"
      $NOOP rake build:$task
    done

    for task in ${MODULE_PACKER_LOAD[@]} ; do
      verbose "Loading $task"
      trace "Executing: rake load:$task"
      $NOOP rake load:$task
    done

    popd
  fi

  #TODO: Make this multi-virtualization!
  [[ $MODULE_parallels_done  == 1 ]] && MODULE_PACKER_VIRT=parallels
  [[ $MODULE_virtualbox_done == 1 ]] && MODULE_PACKER_VIRT=virtualbox
  [[ $MODULE_vmware_done     == 1 ]] && MODULE_PACKER_VIRT=vmware
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
  fi

  if [[ -n "$(vagrant 2>&1 | grep 'valid license.*Vagrant VMware')" ]]; then
    if [[ -n $MODULE_VAGRANT_VMWARE_LICENSE ]]; then
      $NOOP vagrant plugin license vagrant-vmware-fusion $MODULE_VAGRANT_VMWARE_LICENSE
    else
      warn "  TODO: install your Vagrant for VMWare license!"
    fi
  else
    verbose "Vagrant Plugin for VMWare is already licensed"
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

  vmware_root='/Applications'
  if [[ ! -d '/Applications/VMware Fusion.app' ]]; then
    verbose "Linking VMWare Fusion in /Applications"
    if [[ -d "$HOME/Applications/VMWare Fusion.app" ]]; then
      vmware_root="$HOME/Applications"
    else
      vmware_root=$(brew cask info vagrant | awk '/^\/opt/ { print $1 }')
    fi
    trace "VMWare Fusion is in: $vmware_root"
    verbose "VMWare Fusion is in: $vmware_root"
    ln -s "$vmware_root/VMware Fusion.app"  /Applications
  fi
  vmware_bin="$vmware_root/VMWare Fusion.app/Contents/Library"

  if ! $("$vmware_bin"/vmrun list 2>&1 > /dev/null); then
    verbose "Initializing VMWare Fusion..."
    $NOOP sudo "$vmware_bin/Initialize VMware Fusion.tool" set
    status=$? && [[ $status != 0 ]] && return $status
    verbose "Configuring license..."
    $NOOP sudo "$vmware_bin/licenses/vmware-licensetool" enter "$MODULE_VMWARE_KEY" '' '' '7.0' 'VMware Fusion for Mac OS' '' \
               | grep -q '200 License operation succeeded.'
    status=$? && [[ $status != 0 ]] && return $status
  fi

  if [[ -n "$MODULE_VMWARE_HOME" ]]; then
    current=$(defaults read com.vmware.fusion NSNavLastRootDirectory 2> /dev/null)
    if [[ "$current" != "$MODULE_VMWARE_HOME" ]]; then
      verbose "Updating Virtual Machine home to ${MODULE_VMWARE_HOME}"
      LOCATION='/Library/Preferences/VMWare Fusion/lastLocationUsed'
      $NOOP sudo rm -f -- "$LOCATION".tmp
      $NOOP sudo print -- %s "$(canonicalize_path $MODULE_VMWARE_HOME)" > $LOCATION.tmp
      $NOOP sudo chmod 444 $LOCATION.tmp
      $NOOP sudo mv -f $LOCATION.tmp $LOCATION
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
            source_vpn="$(echo "$source" | jq --raw-output '.vpn' | grep -v null)"
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
      if [[ -n $source_vpn ]]; then
        vpn_start --server="${source_vpn}"
        status=$? && [[ $status != 0 ]] && return $status
      fi
      download $source_has_resume $source_need_auth $source_url "$document_destination" $document_checksum_type $document_checksum
      status=$? && [[ $status != 0 ]] && return $status
      if [[ -n $source_vpn ]]; then
        vpn_stop --server="${source_vpn}"
        status=$? && [[ $status != 0 ]] && return $status
      fi
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

function install_updateme() # {{{2
{
  [[ $MODULE_homebrew_done == 0 ]] && install_homebrew

  [[ -d "$MODULE_updateme_root" ]] || $NOOP mkdir -p "$MODULE_updateme_root"
  status=$? && [[ $status != 0 ]] && return $status
  trace "Creating a temporary folder"
  temp_dir=$(mktemp -d -t puppet-me)
  status=$? && [[ $status != 0 ]] && return $status
  download "$MODULE_updateme_source" $temp_dir
  status=$? && [[ $status != 0 ]] && rm -rf $temp_dir && return $status

  verbose "Unarchiving UpdateMe applications"
  trace "Executing: [7z x -o\"${MODULE_updateme_root}\" -y \"$temp_dir/$(basename ${MODULE_updateme_source})\"]"
  7z x -o"${MODULE_updateme_root}" -y "$temp_dir/$(basename ${MODULE_updateme_source})"
  status=$? && [[ $status != 0 ]] && rm -rf $temp_dir && return $status
  rm -rf $temp_dir

  verbose "Configuring UpdateMe applications"
  local install_me="curl -sSL http://tinyurl.com/puppet-me-osx | bash -s -- ${MODULE_updateme_args}"

  scripts=$(find $HOME/Desktop -name script -print)
  trace "scripts: ${scripts[*]}"
  for script in "$HOME/Desktop/DaaS - Update Me.app/Contents/Resources/script" "$HOME/Desktop/DaaS - Update & Build Me.app/Contents/Resources/script" ; do
    trace "Updating [$script]"
    verbose "Updating $(basename "$(dirname "$(dirname "$(dirname "$script")")")" .app)"
    sed -i '.org' -e "s;^curl.*;${install_me};" -e "s;^PACKER_HOME=.*;PACKER_HOME=\"${MODULE_PACKER_HOME}/packer-windows\";" -e "s;^PACKER_VIRT=.*;PACKER_VIRT=${MODULE_PACKER_VIRT};" "$script"
  done

  MODULE_updateme_done=1
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
  echo " --credentials *url*  "
  echo "   Store the credentials from the given url to the keychain.  "
  echo "   Note the credentials have to follow RFC 3986.  "
  echo "   Examples: ftp://myuser:s3cr3t@ftp.acme.com  "
  echo "             smb://acme;myuser:s3cr3t@files.acme.com/share  "
  echo "   Note: if the password contains the @ sign, it should be replaced with %40  "
  echo " --force  "
  echo "   Force all updates to happen (downloads still do not happen if already done)." 
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
  echo " --packer-build *tasks*  "
  echo "   Will tell packer-windows to build boxes (comma separated list).  "
  echo "   If the virtualization software for a build is not installed, the script will produce an error.  "
  echo "   E.g.:  "
  echo "     --packer-build vmware:windows-2012R2-core-standard-eval  "
  echo "     will build the box windows 2012R2 Core edition (evaluation license) for VMWare Fusion.  "
  echo "     --packer-build virtualbox:all  "
  echo "     will build all boxes known to packer-windows for Virtualbox.  "
  echo "   Default value: N/A  "
  echo " --packer-load *tasks*  "
  echo "   Will tell packer-windows to load (and build before as needed) boxes in Vagrant (comma separated list).  "
  echo "   If the virtualization software for a build is not installed, the script will produce an error.  "
  echo "   E.g.:  "
  echo "     --packer-load vmware:windows-2012R2-core-standard-eval  "
  echo "     will (build and) load the box windows 2012R2 Core edition (evaluation license) for VMWare Fusion.  "
  echo "     --packer-build virtualbox:all  "
  echo "     will (build and load) all boxes known to packer-windows for Virtualbox.  "
  echo "   Default value: N/A  "
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
  echo " --vagrant-vmware-license *path*  "
  echo "   Contains the location of the license file for the Vagrant VMWare Plugin.  "
  echo " --verbose  "
  echo "   Runs the script verbosely, that's by default."
  echo " --virtualbox-home *path*  "
  echo "   Contains the location virtual machine data will be stored.  "
  echo "   Default value: $HOME/Documents/Virtual Machines"
  echo " --vmware-home *path*  "
  echo "   Contains the location virtual machine data will be stored.  "
  echo "   Default value: $HOME/Documents/Virtual Machines"
  echo " --vmware-license *key*  "
  echo "   Contains the license key to configure VMWare Fusion.  "
  echo "   If not provided here and VMWare needs to be configured,  "
  echo "   The VMWare initialization script will request it.  "
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
      --credentials|--creds)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing"
        keychain_set_password --kind=internet --url=$2
        shift 2
        continue
      ;;
      --credentials=*?|--creds=*?)
        userid=${1#*=} # delete everything up to =
        keychain_set_password --kind=internet --url=$2
      ;;
      --credentials=|--creds=)
        die "Argument for option $1 is missing"
        ;;
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
      --macmini|--macmini-vmware)
        MODULES=(noidle homebrew updateme rubytools puppet vmware vagrant cache packer)
        ;;
      --macmini-parallels)
        MODULES=(noidle homebrew updateme rubytools puppet parallels vagrant cache packer)
        ;;
      --macmini-virtualbox)
        MODULES=(noidle homebrew updateme rubytools puppet virtualbox vagrant cache packer)
        ;;
      --macmini-all)
        MODULES=(noidle homebrew updateme rubytools puppet parallels virtualbox vmware vagrant cache packer)
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
      --packer-build)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing."
        MODULE_PACKER_BUILD=(${2//,/ })
        shift 2
        continue
        ;;
      --packer-build=*?)
        MODULE_PACKER_BUILD=${1#*=} # delete everything up to =
        MODULE_PACKER_BUILD=(${MODULE_PACKER_BUILD//,/ })
        ;;
      --packer-build=)
        die "Argument for option $1 is missing."
        ;;
      --packer-load)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing."
        MODULE_PACKER_LOAD=(${2//,/ })
        shift 2
        continue
        ;;
      --packer-load=*?)
        MODULE_PACKER_LOAD=${1#*=} # delete everything up to =
        MODULE_PACKER_LOAD=(${MODULE_PACKER_LOAD//,/ })
        ;;
      --packer-load=)
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
      --vagrant-vmware-license)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing."
        MODULE_VAGRANT_VMWARE_LICENSE=$2
        shift 2
        continue
        ;;
      --vagrant-vmware-license=*?)
        MODULE_VAGRANT_VMWARE_LICENSE=${1#*=} # delete everything up to =
        ;;
      --vagrant-vmware-license=)
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
      --vmware-license)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing."
        MODULE_VMWARE_KEY=$2
        shift 2
        continue
        ;;
      --vmware-license=*?)
        MODULE_VMWARE_KEY=${1#*=} # delete everything up to =
        ;;
      --vmware-license=)
        die "Argument for option $1 is missing."
        ;;
      --noop|--dry-run)
        warn "This program will execute in dry mode, your system will not be modified"
        NOOP=:
        ;;
      --test-keychain)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing."
        keychain_echo_credentials $2
        exit
        ;;
      --test-keychain=*?)
        keychain_echo_credentials $2
        exit
        ;;
      --test-keychain=)
        die "Argument for option $1 is missing."
        ;;
      --force)
       trace "Force updates: on"
       FORCE_UPDATE=1
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

  verbose "Welcome, $userid!"

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
      updateme)   install_updateme ;;
      *)          die "Unsupported Module: ${module}" ;;
    esac
    status=$? && [[ $status != 0 ]] && die "Error $status while installing module $module" $status
  done
} # }}}
main "$@"
