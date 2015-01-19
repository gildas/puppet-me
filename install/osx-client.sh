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

MODULES=(homebrew puppet)
ALL_MODULES=(homebrew cache packer puppet rubytools vagrant virtualbox vmware)

CACHE_ROOT='/var/cache/daas'
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
        MODULES=(homebrew rubytools puppet vmware vagrant packer cache)
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
  local source=$1
  local target=$2
  local filename

  filename=${source##*/}        # Remove everything up to the last /
  filename=${filename%%\?*}     # emove everything after the ? (including)
  verbose "  Downloading ${filename}..."

  $NOOP mkdir -p $target
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
  MODULE_homebrew_done=1
} # 2}}}

function install_packer() # {{{2
{
  [[ $MODULE_homebrew_done  == 0 ]] && install_homebrew
  [[ $MODULE_rubytools_done == 0 ]] && install_rubytools

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

  if [[ -f "$packer_windows/Gemfile" ]]; then
    [[ -z "$NOOP" ]] && (cd $packer_windows ; bundle install)
  fi
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

  if [[ -z $(vagrant plugin list | grep 'vagrant-vmware-fusion') ]]; then
    verbose "  Installing Vagrant Plugin for VMWare"
    $NOOP vagrant plugin install vagrant-vmware-fusion
    warn "  TODO: install your Vagrant for VMWare license!"
  fi
} # 2}}}

function install_virtualbox() # {{{2
{
  [[ $MODULE_homebrew_done == 0 ]] && install_homebrew

  cask_install virtualbox
} # 2}}}

function install_vmware() # {{{2
{
  if [[ -d '/Applications/VMware Fusion.app' ]]; then
    verbose "VMWare Fusion is installed"
  else
    warn "Please install VMWare Fusion before building virtual machines"
  fi
} # 2}}}

function cache_stuff() # {{{2
{
  verbose "Caching ISO files"
  [[ -d "$CACHE_ROOT" ]] || mkdir -p "$CACHE_ROOT"

  for cached in "${CACHE_SOURCES[*]}"; do
    KEY="${cached%%|*}"
    VALUE="${cached#*:}"
    verbose "Caching $KEY"
    verbose "  data: $VALUE"
  done
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
}
main "$@"
# }}}
