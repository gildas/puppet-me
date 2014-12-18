#!/usr/bin/env bash

shopt -s extglob
set -o errtrace
#set -o errexit
set +o noclobber

export NOOP=

ASSUMEYES=0
VERBOSE=0
LOG="/var/log/puppet-me.log"
tmp="tmp"
puppet_master="puppet"
userid=$(whoami)

MODULES=(homebrew puppet)

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

  echo "[$(date +'%Y%m%dT%H%M%S')]${BASH_SOURCE[$caller_index]}::${FUNCNAME[$caller_index]}@${BASH_LINENO[(($caller_index - 1))]}: $@" >> $LOG
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
  trace --trace-member "[END] -------"
} # 2}}}

function verbose() ## {{{2
{
  trace --trace-member $@
  [[ $VERBOSE > 0 ]] && echo $@
} # 2}}}

function warn() # {{{2
{
  trace --trace-member "[WARNING] $@"
  echo "Warning: " $@
} # 2}}}

function error() # {{{2
{
  trace --trace-member "[ERROR] $@"
  echo "Error:" $@ >&2
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
  echo $message >&2
  exit $errorlevel
} # 2}}}

# Module: tracing # }}}

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
	#MODULES=(homebrew git puppet vagrant packer ISO_cache)
	MODULES=(homebrew git vagrant packer ISO_cache)
	;;
      --modules)
        [[ -z $2 || ${2:0:1} == '-' ]] && die "Argument for option $1 is missing"
	MODULES=(${2//,/ })
        shift 2
        continue
	;;
      --modules=*?)
        MODULES=${1#*=} # delete everything up to =
	MODULES=(${MODULES//,/ })
	;;
      --modules=)
        die "Argument for option $1 is missing"
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
  local source=$1
  local target=$2
  local filename

  filename=${source##*/}        # Remove everything up to the last /
  filename=${filename%%\?*}     # emove everything after the ? (including)
  verbose "  Downloading ${filename}..."

  $NOOP curl --location --show-error --progress-bar --output "${target}/${filename}" "${source}"
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
  $NOOP mount=$(hdiutil attach ${target} | sed -e 's/^\/.* \//\//')
  verbose "      mounted on ${mount}"

  #  #TODO: ERROR

  verbose "    Installing ${target}"
  $NOOP local package=$(find ${mount} -name '*.pkg' -mindepth 1 -maxdepth 1)
  verbose "      Package: ${package}"
  $NOOP sudo installer -pkg ${package} -target /

  verbose "    Unmounting ${target}"
  $NOOP hdiutil eject ${mount} > /dev/null
} # 2}}}

function install_puppet_dmg() # {{{2
{
  local module="$1"
  local version="$2"
  local basename="${module}-${version}"
  local archive="${basename}.dmg"
  local url="$3"

  verbose "Installing module ${module}"
  if [ "$version" = "*" ]; then
    verbose "  Checking version numbers for ${module}"
    archive=$(curl --silent --list-only "${url}/" | grep --ignore-case "${module}-\d" | grep --invert-match --regexp="rc\d*\.dmg" | tail -1 | sed -e 's/.*href="\([^"]*\)".*/\1/')
    basename=${archive%.*}
    version=${basename#*-}
  fi
  verbose "  Targetting version ${version} for module ${module}"
  if [[ -x $(which $module) && "$($(which $module) --version)" == "${version}" ]]; then
    verbose "    ${module} is already installed properly"
  else
    verbose "    Downloading $archive"
    source="${url}/${archive}"
    target="$HOME/Downloads/${archive}"
    [ -f "${target}" ] && verbose "Deleting existing archive" && rm -f "$target"
    verbose "    Downloading ${source} into ${target}"
    $NOOP curl --location --show-error --progress-bar --output "${target}" "${source}"

    verbose "    Mounting ${target}"
    $NOOP local plist_path=$(mktemp -t $module)
    $NOOP hdiutil attach -plist ${target} > ${plist_path}
    verbose "      plist_path: ${plist_path}"
    $NOOP mount=$(grep -E -o '/Volumes/[-.a-zA-Z0-9]+' ${plist_path})
    verbose "      mounted on ${mount}"

  #  #TODO: ERROR

    verbose "    Installing ${target}"
    $NOOP package=$(find ${mount} -name '*.pkg' -mindepth 1 -maxdepth 1)
    verbose "      Package: ${package}"
    $NOOP sudo installer -pkg ${package} -target /

    verbose "    Unmounting ${target}"
    $NOOP hdiutil eject ${mount} > /dev/null
  fi
} # 2}}}

function install_puppet() # {{{2
{
  verbose "installing facter, hiera, and puppet"
  install_puppet_dmg facter "*" http://downloads.puppetlabs.com/mac/
  install_puppet_dmg hiera  "*" http://downloads.puppetlabs.com/mac/
  install_puppet_dmg puppet "*" http://downloads.puppetlabs.com/mac/

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
    $NOOP sudo puppet resource user  puppet ensure=present gid=puppet shell="/sbin/nologin"
  else
    verbose "  User 'puppet' is already a member of group 'puppet"
  fi

  verbose "Hiding the puppet user from the Login window"
  hidden_users=$(/usr/libexec/PlistBuddy -c "Print :HiddenUsersList" /Library/Preferences/com.apple.loginwindow.plist)
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
    read -p "  Please enter the hostname or ip address of the puppet server [${puppet_master}]: " input_puppet_master
    [[ ! -z "${input_puppet_master}" ]] && puppet_master=$input_puppet_master
    read -p "  Please enter your userid [${userid}]: " input_userid
    [[ ! -z "${input_userid}" ]] && userid=$input_userid
    certname="osx-sandbox-${userid}"
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
} # 2}}}

function install_xcode_tools() # {{{2
{
  local downloaded=0

  #if xcode-select -p > /dev/null 2>&1; then
  if [[ '1' == '2' ]]; then
    echo "XCode tools are already installed"
  else
    verbose "Installing XCode tools"
    myips=($(ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p'))
    for ip in ${myips[*]} ; do
      verbose "Checking IP: $ip"
      if [[ $ip =~ 172\.22\.16\.[0-9]+ ]]; then
	install_dmg http://tyofiles/AppShare/Development/XCode/commandlinetoolsosx10.10forxcode6.1.1.dmg
        return
        break
      fi
    done

    if [[ $(ping -t 1 tyofiles) ]]; then
      install_dmg http://tyofiles/AppShare/Development/XCode/commandlinetoolsosx10.10forxcode6.1.1.dmg
      return
    fi

    die "Unable to install XCode Command Line Tools"
  fi
} # 2}}}

function install_homebrew() # {{{2
{
  # Installing homebrew from http://brew.sh
  # prerequisites:
  install_xcode_tools

  if which brew > /dev/null 2>&1; then
    verbose "Homebrew is already installed, updating formulas..."
    $NOOP brew update
  else
    verbose "Installing Homebrew..."
    $NOOP ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
  fi

  # Installing Cask from http://caskroom.io
  if [[ ! -z $(brew info cask | grep -v '^Not installed$') ]]; then
    verbose "Installing Homebrew Cask..."
    $NOOP brew install caskroom/cask/brew-cask
  fi
} # 2}}}

function install_git() # {{{2
{
  verbose "Installing git"
} # 2}}}

function install_vagrant() # {{{2
{
  # vagrant + vagrant_host_shell
  verbose "Installing Vagrant"
} # 2}}}

function install_packer() # {{{2
{
  # packer + packer_windows
  verbose "Installing Packer"
} # 2}}}

function cache_ISO() # {{{2
{
  verbose "Caching ISO files"
} # 2}}}

# Main
function main() # {{{
{
  trace_init "$@"
  parse_args "$@"

  for module in ${MODULES[*]} ; do
    trace "Installing Module ${module}"
    case $module in
      git)
        install_git
        ;;
      homebrew)
        install_homebrew
        ;;
      ISO_cache)
        cache_ISO
        ;;
      packer)
        install_packer
        ;;
      puppet)
        install_puppet
        ;;
      vagrant)
        install_vagrant
        ;;
      *)
        die "Unsupported Module: ${module}"
        ;;
    esac
  done
}
main "$@"
# }}}
