#!/usr/bin/env bash

shopt -s extglob
set -o errtrace
set +o noclobber

export VERBOSE=1
export DEBUG=1

function log()
{
  printf "%b\n" "$*";
}

function debug()
{
  [[ ${DEBUG:-0} -eq 0 ]] || printf "[debug] $#: $*";
}

function verbose()
{
  [[ ${VERBOSE:-0} -eq 0 ]] || printf "$*\n";
}

function init_config()
{
  puppet_master="puppet"
  userid=$(whoami)
}

function parse_args()
{
  flags=()

  while (( $# > 0 ))
  do
    arg="$1"
    shift
    case "$arg" in
      (--userid)
	shift
	userid=$arg
	flags+=( "$arg" )
	;;
      (--trace)
        set -o trace
	TRACE=1
	flags+=( "$arg" )
	;;
      (--debug)
        export DEBUG=1
        flags+=( "$arg" )
        ;;
      (--quiet)
        export VERBOSE=0
        flags+=( "$arg" )
        ;;
      (--verbose)
        export VERBOSE=1
        flags+=( "$arg" )
        ;;
    esac
  done

}

function install_dmg()
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
    curl --location --show-error --progress-bar --output "${target}" "${source}"

    verbose "    Mounting ${target}"
    local plist_path=$(mktemp -t $module)
    hdiutil attach -plist ${target} > ${plist_path}
    verbose "      plist_path: ${plist_path}"
    mount=$(grep -E -o '/Volumes/[-.a-zA-Z0-9]+' ${plist_path})
    verbose "      mounted on ${mount}"

  #  #TODO: ERROR

    verbose "    Installing ${target}"
    package=$(find ${mount} -name '*.pkg' -mindepth 1 -maxdepth 1)
    verbose "      Package: ${package}"
    sudo installer -pkg ${package} -target /

    verbose "    Unmounting ${target}"
    hdiutil eject ${mount} > /dev/null
  fi
}

# Main
init_config
parse_args "$@"
verbose "NOTE: You might have to enter your password to allow the script to modify your system!"
install_dmg facter "*" http://downloads.puppetlabs.com/mac/
install_dmg hiera  "*" http://downloads.puppetlabs.com/mac/
install_dmg puppet "*" http://downloads.puppetlabs.com/mac/

verbose "Creating user/group resources"
dseditgroup -o read puppet &> /dev/null
if [ ! $? -eq 0 ]; then
  verbose "  Creating group 'puppet'"
  sudo puppet resource group puppet ensure=present
else
  verbose "  Group 'puppet' is already created"
fi
dseditgroup -o checkmember -m puppet puppet &> /dev/null
if [ ! $? -eq 0 ]; then
  verbose "  Adding puppet to group 'puppet'"
  sudo puppet resource user  puppet ensure=present gid=puppet shell="/sbin/nologin"
else
  verbose "  User 'puppet' is already a member of group 'puppet"
fi

verbose "Hiding the puppet user from the Login window"
hidden_users=$(/usr/libexec/PlistBuddy -c "Print :HiddenUsersList" /Library/Preferences/com.apple.loginwindow.plist)
if [ ! $? -eq 0 ]; then
  verbose "  Adding the HiddenUsersList entry"
  sudo /usr/libexec/PlistBuddy -c "Add :HiddenUsersList array" /Library/Preferences/com.apple.loginwindow.plist &> /dev/null
fi
if [[ ! ${hidden_users} =~ "puppet" ]]; then
  verbose "  Adding puppet to the hidden user list"
  sudo /usr/libexec/PlistBuddy -c "Add :HiddenUsersList: string puppet" /Library/Preferences/com.apple.loginwindow.plist &> /dev/null
else
  verbose "  User puppet is already hidden from the Login window"
fi

verbose "Creating folders"
[[ ! -d /var/log/puppet ]]       && sudo mkdir -p /var/log/puppet
[[ ! -d /var/lib/puppet ]]       && sudo mkdir -p /var/lib/puppet
[[ ! -d /var/lib/puppet/cache ]] && sudo mkdir -p /var/lib/puppet/cache
[[ ! -d /etc/puppet/ssl ]]       && sudo mkdir -p /etc/puppet/ssl
sudo chown -R puppet:puppet /var/lib/puppet
sudo chmod 750 /var/lib/puppet
sudo chown -R puppet:puppet /var/log/puppet
sudo chmod 750 /var/log/puppet
sudo chown -R puppet:puppet /etc/puppet
sudo chmod 750 /etc/puppet

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
  sudo install -m 0644 -o puppet -g puppet ${config} /etc/puppet/puppet.conf
fi

verbose "Installing the puppet agent daemon"
if [ ! -f "/Library/LaunchDaemons/com.puppetlabs.puppet.plist" ]; then
  curl --location --show-error --progress-bar --output "$HOME/Downloads/com.puppetlabs.puppet.plist" https://raw.github.com/inin-apac/puppet-me/master/config/osx/com.puppetlabs.puppet.plist
  sudo install -m 0644 -o root -g wheel $HOME/Downloads/com.puppetlabs.puppet.plist /Library/LaunchDaemons
  sudo launchctl load -w /Library/LaunchDaemons/com.puppetlabs.puppet.plist
fi
verbose "Starting the puppet agent daemon"
sudo launchctl start com.puppetlabs.puppet
