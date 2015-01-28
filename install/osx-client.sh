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

MODULE_homebrew_done=0
MODULE_cache_done=0
MODULE_packer_done=0
MODULE_puppet_done=0
MODULE_rubytools_done=0
MODULE_vagrant_done=0
MODULE_virtualbox_done=0
MODULE_vmware_done=0

MODULES=(homebrew puppet rubytools)
ALL_MODULES=(homebrew cache packer puppet rubytools vagrant virtualbox vmware)

CACHE_ROOT='/var/cache/daas'
CACHE_SOURCE='https://raw.githubusercontent.com/inin-apac/puppet-me/master/install/sources.json'
trap trace_end EXIT

# Module: tracing # {{{

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
} # 2}}}

function trace_init() # {{{2
{
  local log_file=$(basename $LOG)
  local log_group="wheel"
  local result

  while :; do # {{{3
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
  done # 3}}}

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
  trace --trace-member "Removing CIFS mount points"
  if [[ ! -z $(mount | grep /Volumes/WindowsShare) ]]; then
    sudo umount /Volumes/WindowsShare-* 2>&1 > /dev/null
  fi
  trace --trace-member "[END] -------"
} # 2}}}

function verbose() ## {{{2
{
  trace --trace-member "$@"
  [[ $VERBOSE > 0 ]] && echo -e "$@"
} # 2}}}

function warn() # {{{2
{
  trace --trace-member "[WARNING] $@"
  echo -e "Warning: $@"
} # 2}}}

function error() # {{{2
{
  trace --trace-member "[ERROR] $@"
  echo -e "Error: $@" >&2
} # 2}}}

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
} # 2}}}

# Module: tracing # }}}

function capitalize() # {{{2
{
  local value=$1

  echo "$(tr '[:lower:]' '[:upper:]' <<< ${value:0:1})${value:1}"
} # 2}}}

function mask_cidr2dotted() #{{{2
{
   # Number of args to shift, 255..255, first non-255 byte, zeroes
   set -- $(( 5 - ($1 / 8) )) 255 255 255 255 $(( (255 << (8 - ($1 % 8))) & 255 )) 0 0 0
   [ $1 -gt 1 ] && shift $1 || shift
   echo ${1-0}.${2-0}.${3-0}.${4-0}
} # 2}}}

function mask_dotted2cidr() #{{{2
{
   # Assumes there's no "255." after a non-255 byte in the mask
   set -- 0^^^128^192^224^240^248^252^254^ ${#1} ${1##*255.}
   set -- $(( ($2 - ${#3})*2 )) ${1%%${3%%.*}*}
   echo $(( $1 + (${#2}/4) ))
} # 2}}}

function mask_hex2cidr() #{{{2
{
   # Assumes there's no "ff" after a non-ff byte in the mask
   set -- 08ce ${#1} ${1##*f}
   set -- $(( ($2 - ${#3})*4 )) ${1%%${3%%0*}*}
   echo $(( $1 + ${#2} ))
} # 2}}}

function urldecode() #{{{2
{
  local value=${1//+/ }         # decode + into space
  printf '%b' "${value//%/\\x}" # decode hexa characters (ANSI only)
} # 2}}}

function prompt() #{{{2
{
  local query=$1

  if [[ -z "$SSH_CLIENT" ]]; then
    # We are on the Mac screen
    entry=$(osascript -e "Tell application 'System Events' to display dialog '${query}' default answer ''" -e 'text returned of result' 2>/dev/null)
    if [ $? -ne 0]; then
      # The user pressed cancel
      return 1
    fi
  else
    # We are in an SSH session
    read -p "${query}" value
    printf '%s' $value
  fi
} # 2}}}

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
} # 2}}}

function usage() # {{{2
{
  echo "$(basename $0) [options]"
} # 2}}}

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
      --macmini)
        MODULES=(homebrew rubytools puppet vmware vagrant cache packer)
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
      --noop|--dry-run)
        warn "This program will execute in dry mode, your system will not be modified"
        NOOP=:
        ;;
      -h|-\?|--help)
       trace "Showing usage"
       usage
       exit 1
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
} # 2}}}

function download() # {{{2
{
  # download "http://login:password@hostname/path/file?k1=v1&k2=v2" "local_folder"
  # download "smb://login:password@hostname/path/file?k1=v1&k2=v2" "local_folder"
  local source=$1
  local target=$2
  local checksum_type=$3
  local checksum_value=$4
  local checksum='md5'
  local target_checksum
  local filename
  local filename_path

  filename=${source##*/}        # Remove everything up to the last /
  filename=${filename%%\?*}     # emove everything after the ? (including)
  target_path="${target}/${filename}"

  verbose "  Downloading ${filename}..."

  case $checksum_type in
    MD5|md5)   checksum='md5';;
    SHA1|sha1) checksum='shasum';;
    null|'')   checksum='';;
    *)
    error "Unsupported checksum type ($checksum_type) while downloading $filename"
    return 1
  esac
  trace "Expect $checksum_type checksum: $checksum_value"

  [[ -w "$(dirname $target)" ]] || sudo='sudo'
  $NOOP $sudo mkdir -p $target
  [[ -w $target ]] || sudo='sudo'
  if [[ -r "${target_path}" && ! -z ${checksum} ]]; then
    target_checksum=$( $checksum "${target_path}")
    if [[ $target_checksum =~ \s*$checksum_value\s* ]]; then
      verbose "  File already downloaded and checksum verified"
      return 0
    else
      $NOOP sudo rm -f "$target_path"
    fi
  fi
  if [[ ${source%%:*} == 'smb' ]]; then
    verbose "  Copying from CIFS location"
    # source is like smb://domain;userid:password@server/share/path/file
    # domain, userid, and password are optional
    trace ">> source: ${source}"
    smb_user=''
    smb_domain=''
    smb_password=''
    smb_mount=$(dirname ${source#*:})
    trace ">> mount: ${smb_mount}"
    if [[ "${smb_mount}" =~ .*@.* ]]; then      # Search for user
      trace "  Found a user"
      smb_user=${smb_mount#*//}                 # remove the heading //
      smb_user=${smb_user%@*}                   # keep the credentials
      trace "  >> smb_user: ${smb_user}"
      if [[ "${smb_user}" =~ .*:.* ]]; then     # Search for password
        trace "  Found a password"
        smb_password=${smb_user#*:}             # extract password
        smb_user=${smb_user%:*}                 # remove all after :
      fi
      if [[ "${smb_user}" =~ .*\;.* ]]; then    # Search for domain
        trace "  Found a domain"
        smb_domain=${smb_user%;*}               # extract domain
        smb_user=${smb_user#*;}                 # extract user
      fi
    fi
    smb_host=${smb_mount#*@}                    # remove the user
    smb_share=${smb_host#*/}                    # remove the host
    smb_path=${smb_share#*/}                    # extract the path
    smb_share=${smb_share%%/*}                  # extract the share
    smb_host=${smb_host%%/*}                    # extract the host
    trace "smb: host: ${smb_host}, share: ${smb_share}, path: ${smb_path}, user: ${smb_user}, domain: ${smb_domain}, password: ${smb_password}"

    if [[ -z "$smb_user" ]]; then
      smb_user=$(prompt "User for mounting ${smb_share} on ${smb_host}: ")
      [[ ! -z "$smb_user" ]] && smb_user=$userid
      smb_user=${smb_user/\\/;/}                # change \ into ;
    elif [[ ! -z "$smb_domain" ]]; then
      smb_user="${smb_domain};${smb_user}"
    fi
    if [[ -z "$smb_password" ]]; then
      smb_password=$(prompt "Password for ${smb_user}: ")
      smb_mount="//${smb_user}@${smb_host}/${smb_share}"
    else
      smb_mount="//${smb_user}:${smb_password}@${smb_host}/${smb_share}"
    fi

    smb_target="/Volumes/WindowsShare-${smb_host}-${smb_share}.$$"
    if [[ -z "$(mount | grep $smb_target)" ]]; then
      verbose "  Mounting ${smb_share} from ${smb_host} as ${smb_user}"
      trace ">> mount -t smbfs '${smb_mount}' $smb_target"
      mkdir -p $smb_target
      mount -t smbfs  "${smb_mount}" $smb_target
      if [[ $? > 0 ]]; then
        error "Cannot mount ${smb_mount}"
        return 1
      fi
    fi
    verbose "  Copying $filename"
    trace $sudo cp "${smb_target}/$(urldecode ${smb_path})/$filename" "${target_path}"
    $NOOP $sudo cp "${smb_target}/$(urldecode ${smb_path})/$filename" "${target_path}"
    $NOOP $sudo chmod 664 "${target_path}"
  else
    verbose "  Copying from url location"
    trace $sudo curl --location --show-error --progress-bar --output "${target_path}" "${source}"
    $NOOP $sudo curl --location --show-error --progress-bar --output "${target_path}" "${source}"
  fi
  if [[ -r "${target_path}" && ! -z ${checksum} ]]; then
    target_checksum=$( $checksum "${target_path}")
    if [[ ! $target_checksum =~ \s*$checksum_value\s* ]]; then
      error "Invalid ${document_checksum_type} checksum for the downloaded document"
      $NOOP sudo rm -f "$target_path"
      return 1
    fi
  fi
} # 2}}}

function install_dmg() # {{{2
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

  verbose "    Mounting ${target}"
  mount=$(hdiutil attach ${target} | sed -e 's/^\/.* \//\//')
  verbose "      mounted on ${mount}"

  #  #TODO: ERROR

  verbose "    Installing ${target}"
  local package=$(find ${mount} -name '*.pkg' -mindepth 1 -maxdepth 1)
  verbose "      Package: ${package}"
  $NOOP sudo installer -pkg ${package} -target /

  verbose "    Unmounting ${target}"
  hdiutil eject ${mount} > /dev/null
} # 2}}}

function brew_install() # {{{2
{
  local app_binary=$1
  local app_name=$(capitalize $1)

  if which $app_binary > /dev/null 2>&1; then
    if [[ ! -z $(brew info $app_binary | grep '^Not installed$') ]]; then
      verbose "$app_name was manually installed (no automatic updates possible)"
    else
      verbose "$app_name is already installed via Homebrew"
    fi
  else
    verbose "Installing $app_name"
    $NOOP brew install $app_binary
  fi
} # 2}}}

function cask_install() # {{{2
{
  local app_binary=$1
  local app_name=$(capitalize $1)

  if which $app_binary > /dev/null 2>&1; then
    if [[ ! -z $(brew cask info $app_binary | grep '^Not installed$') ]]; then
      verbose "$app_name was manually installed (no automatic updates possible)"
    else
      verbose "$app_name is already installed via Homebrew"
    fi
  else
    verbose "Installing $app_name"
    $NOOP brew install Caskroom/cask/$app_binary
  fi
} # 2}}}

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
    product=$(softwareupdate -l 2>&1 | grep "\*.*Command Line" | tail -1 | sed -e 's/^   \* //' | tr -d '\n')
    verbose "  Downloading and Installing $product"
    $NOOP softwareupdate --install "$product"
  else # Older versions like Mountain Lion, Lion
    verbose "Installing XCode tools from Website"
    [[ $os_min == 7 ]] && url=http://devimages.apple.com/downloads/xcode/command_line_tools_for_xcode_os_x_lion_april_2013.dmg
    [[ $os_min == 8 ]] && url=http://devimages.apple.com/downloads/xcode/command_line_tools_for_osx_mountain_lion_april_2014.dmg
    $NOOP install_dmg $url
  fi
} # 2}}}

function install_homebrew() # {{{2
{
  # Installing homebrew from http://brew.sh
  # prerequisites:
  install_xcode_tools

  if which brew > /dev/null 2>&1; then
    verbose "Homebrew is already installed, upgrading..."
    $NOOP brew update && brew upgrade && brew cleanup
  else
    verbose "Installing Homebrew..."
    $NOOP ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

    # Preparing brew for first time or sanitizing it if already installed
    $NOOP brew doctor
  fi

  # Installing bash completion
  if [[ ! -z $(brew info bash-completion | grep '^Not installed$') ]]; then
    verbose "Installing bash completion..."
    $NOOP brew install bash-completion
  else
    verbose "Homebrew bash completion is already installed"
  fi

  if [[ -z $(brew tap | grep 'homebrew/completions') ]]; then
    brew tap homebrew/completions
  fi

  if [[ -z $(brew tap | grep 'homebrew/binary') ]]; then
    brew tap homebrew/binary
  fi

  # Installing Cask from http://caskroom.io
  if [[ ! -z $(brew info brew-cask | grep '^Not installed$') ]]; then
    verbose "Installing Homebrew Cask..."
    $NOOP brew install caskroom/cask/brew-cask
  else
    verbose "Homebrew Cask is already installed"
  fi

  # Installing jq for querying json from bash
  if [[ ! -z $(brew info jq | grep '^Not installed$') ]]; then
    verbose "Installing ijq..."
    $NOOP brew install jq
  else
    verbose "jq is already installed"
  fi
  MODULE_homebrew_done=1
} # 2}}}

function install_packer() # {{{2
{
  [[ $MODULE_homebrew_done  == 0 ]] && install_homebrew
  [[ $MODULE_rubytools_done == 0 ]] && install_rubytools
  [[ $MODULE_vagrant_done   == 0 ]] && install_vagrant
  [[ $MODULE_cache_done     == 0 ]] && install_cache

  brew_install packer

  # Installing bash completion
  if [[ ! -z $(brew info homebrew/completions/packer-completion | grep '^Not installed$') ]]; then
    verbose "Installing bash completion for Packer..."
    $NOOP brew install homebrew/completions/packer-completion
  fi

  packer_bindir=$(dirname $(which packer))
  if [[ ! -x $packer_bindir/packer-provisioner-wait ]]; then
    verbose "  Install Packer plugin: provisioner-wait"
    $NOOP curl -sSL https://github.com/gildas/packer-provisioner-wait/raw/master/bin/0.1.0/darwin/packer-provisioner-wait --output $packer_bindir/packer-provisioner-wait
  fi

  packer_windows=$HOME/Documents/packer/packer-windows
  if [[ ! -d "$packer_windows" ]]; then
    echo "  Installing Packer framework for building Windows machines"
    $NOOP mkdir -p $(dirname $packer_windows)
    $NOOP git clone https://github.com/gildas/packer-windows $packer_windows
  else
    echo "  Upgrading Packer framework for building Windows machines"
    $NOOP git --git-dir "${packer_windows}/.git" pull
  fi

  for file in `\ls -1 /var/cache/daas/`; do
    [[ "$file" == 'sources.json' ]] && continue
    if [ ! -L "${packer_windows}/iso/${file}" ]; then
      [ -r "${packer_windows}/iso/${file}" ] && sudo rm "${packer_windows}/iso/${file}"
      ln -s "/var/cache/daas/${file}" ${packer_windows}/iso
    fi
  done

  if [[ -f "$packer_windows/Gemfile" ]]; then
    [[ -z "$NOOP" ]] && (cd $packer_windows ; bundle install)
  fi
  MODULE_packer_done=1
} # 2}}}

function install_puppet() # {{{2
{
  local os_maj=$(sw_vers -productVersion | cut -d. -f1)
  local os_min=$(sw_vers -productVersion | cut -d. -f2)

  [[ $MODULE_homebrew_done == 0 ]] && install_homebrew

  verbose "installing facter, hiera, and puppet"
  cask_install puppet
  cask_install hiera
  cask_install facter

  verbose "Creating user/group resources"
  dseditgroup -o read puppet &> /dev/null
  if [ ! $? -eq 0 ]; then
    verbose "  Creating group 'puppet'"
    $NOOP sudo puppet resource group puppet ensure=present
  else
    verbose "  Group 'puppet' is already created"
  fi
  dseditgroup -o checkmember -m puppet puppet &> /dev/null
  if [ ! $? -eq 0 ]; then
    verbose "  Adding puppet to group 'puppet'"
    $NOOP sudo puppet resource user puppet ensure=present gid=puppet shell="/sbin/nologin"
  else
    verbose "  User 'puppet' is already a member of group 'puppet'"
  fi

  verbose "Hiding the puppet user from the Login window"
  if [[ $os_min -ge 10 ]]; then # Yosemite or later
    if [[ -z $(dscl . read /Users/puppet | grep IsHidden) ]]; then
      sudo dscl . create /Users/puppet IsHidden 1
    elif [[ -z $(dscl . read /Users/puppet IsHidden | grep 1) ]]; then
      sudo dscl . create /Users/puppet IsHidden 1
    else
      verbose "  User puppet is already hidden from the Login window"
    fi
  else
    hidden_users=$(/usr/libexec/PlistBuddy -c "Print :HiddenUsersList" /Library/Preferences/com.apple.loginwindow.plist 2>&1)
    if [ ! $? -eq 0 ]; then
      verbose "  Adding the HiddenUsersList entry"
      $NOOP sudo /usr/libexec/PlistBuddy -c "Add :HiddenUsersList array" /Library/Preferences/com.apple.loginwindow.plist &> /dev/null
    fi
    if [[ ! ${hidden_users} =~ "puppet" ]]; then
      verbose "  Adding puppet to the hidden user list"
      $NOOP sudo /usr/libexec/PlistBuddy -c "Add :HiddenUsersList: string puppet" /Library/Preferences/com.apple.loginwindow.plist &> /dev/null
    else
      verbose "  User puppet is already hidden from the Login window"
    fi
  fi

  verbose "Creating folders"
  [[ ! -d /var/log/puppet ]]       && $NOOP sudo mkdir -p /var/log/puppet
  [[ ! -d /var/lib/puppet ]]       && $NOOP sudo mkdir -p /var/lib/puppet
  [[ ! -d /var/lib/puppet/cache ]] && $NOOP sudo mkdir -p /var/lib/puppet/cache
  [[ ! -d /etc/puppet/ssl ]]       && $NOOP sudo mkdir -p /etc/puppet/ssl
  $NOOP sudo chown -R puppet:puppet /var/lib/puppet
  $NOOP sudo chmod 750 /var/lib/puppet
  $NOOP sudo chown -R puppet:puppet /var/log/puppet
  $NOOP sudo chmod 750 /var/log/puppet
  $NOOP sudo chown -R puppet:puppet /etc/puppet
  $NOOP sudo chmod 750 /etc/puppet

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
    $NOOP sudo install -m 0644 -o puppet -g puppet ${config} /etc/puppet/puppet.conf
  fi

  verbose "Installing the puppet agent daemon"
  if [ ! -f "/Library/LaunchDaemons/com.puppetlabs.puppet.plist" ]; then
    $NOOP curl --location --show-error --progress-bar --output "$HOME/Downloads/com.puppetlabs.puppet.plist" https://raw.github.com/inin-apac/puppet-me/master/config/osx/com.puppetlabs.puppet.plist
    $NOOP sudo install -m 0644 -o root -g wheel $HOME/Downloads/com.puppetlabs.puppet.plist /Library/LaunchDaemons
    $NOOP sudo launchctl load -w /Library/LaunchDaemons/com.puppetlabs.puppet.plist
  fi
  verbose "Starting the puppet agent daemon"
  $NOOP sudo launchctl start com.puppetlabs.puppet
  MODULE_puppet_done=1
} # 2}}}

function install_rubytools() # {{{2
{
  [[ $MODULE_homebrew_done == 0 ]] && install_homebrew

  # On Mac OS/X, ruby is always installed. And since Mavericks, we get 2.0.0
  # Gem and Rake are also installed.
  if [[ ! -z $(gem list --local | grep bundler) ]]; then
    verbose "Bundler is already installed"
  else
    $NOOP sudo gem install bundler
  fi
  MODULE_rubytools_done=1
} # 2}}}

function install_vagrant() # {{{2
{
  [[ $MODULE_homebrew_done == 0 ]] && install_homebrew

  cask_install vagrant
  $NOOP vagrant plugin update

  # Installing bash completion
  if [[ ! -z $(brew info homebrew/completions/vagrant-completion | grep '^Not installed$') ]]; then
    verbose "Installing bash completion for Vagrant..."
    $NOOP brew install homebrew/completions/vagrant-completion
  fi

  if [[ -z $(vagrant plugin list | grep 'vagrant-host-shell') ]]; then
    verbose "  Installing Vagrant Plugin for Host Shell"
    $NOOP vagrant plugin install vagrant-host-shell
  fi

  if [[ -z $(vagrant plugin list | grep 'vagrant-vmware-fusion') ]]; then
    verbose "  Installing Vagrant Plugin for VMWare"
    $NOOP vagrant plugin install vagrant-vmware-fusion
    warn "  TODO: install your Vagrant for VMWare license!"
  fi
  MODULE_vagrant_done=1
} # 2}}}

function install_virtualbox() # {{{2
{
  [[ $MODULE_homebrew_done == 0 ]] && install_homebrew

  cask_install virtualbox
  MODULE_virtualbox_done=1
} # 2}}}

function install_vmware() # {{{2
{
  if [[ -d '/Applications/VMware Fusion.app' ]]; then
    verbose "VMWare Fusion is installed"
  else
    warn "Please install VMWare Fusion before building virtual machines"
  fi
  MODULE_vmware_done=1
} # 2}}}

function cache_stuff() # {{{2
{
  local nic_names nic_name nic_info nic_ip nic_mask ip_addresses ip_address ip_masks ip_mask

  verbose "Caching ISO files"
  [[ -d "$CACHE_ROOT" ]] || $NOOP sudo mkdir -p "$CACHE_ROOT"
  download "$CACHE_SOURCE" "${CACHE_ROOT}"
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
      trace "  Destination: ${document_destination}"
      document_checksum=$(echo "$document" | jq --raw-output '.checksum.value')
      document_checksum_type=$(echo "$document" | jq --raw-output '.checksum.type')
      download $source_url "$document_destination" $document_checksum_type $document_checksum
    else
      warn "Cannot cache $( echo "$document" | jq --raw-output '.name' ), no source available"
    fi
  done
  MODULE_cache_done=1
} # 2}}}

# Main
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
      homebrew)
        install_homebrew
        ;;
      cache)
        cache_stuff
        ;;
      packer)
        install_packer
        ;;
      puppet)
        install_puppet
        ;;
      rubytools)
        install_rubytools
        ;;
      vagrant)
        install_vagrant
        ;;
      virtualbox)
        install_virtualbox
        ;;
      vmware)
        install_vmware
        ;;
      *)
        die "Unsupported Module: ${module}"
        ;;
    esac
  done
} # }}}
main "$@"
