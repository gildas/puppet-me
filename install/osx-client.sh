#!/usr/bin/env bash

shopt -s extglob
set -o errexit
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

function parse_args()
{
  flags=()

  while (( $# > 0 ))
  do
    arg="$1"
    shift
    case "$arg" in
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

  if [ "$version" = "*" ]; then
    verbose "Checking version numbers for ${module}"
    archive=$(curl --silent --list-only "${url}/" | grep --ignore-case "${module}-\d" | grep --invert-match --regexp="rc\d*\.dmg" | tail -1 | sed -e 's/.*href="\([^"]*\)".*/\1/')
    basename=${archive%.*}
    version=${basename#*-}
  fi
  verbose "Targetting version ${version} for module ${module}"
  if [[ -x $(which $module) && "$($(which $module) --version)" == "${version}" ]]; then
    verbose "${module} is already installed properly"
  else
    verbose "Downloading $archive"
    source="${url}/${archive}"
    target="$HOME/Downloads/${archive}"
    [ -f "${target}" ] && verbose "Deleting existing archive" && rm -f "$target"
    verbose "Downloading ${source} into ${target}"
    curl --location --show-error --progress-bar --output "${target}" "${source}"

    verbose "mounting ${target}"
    local plist_path=$(mktemp -t $module)
    hdiutil attach -plist ${target} > ${plist_path}
    verbose "plist_path: ${plist_path}"
    mount=$(grep -E -o '/Volumes/[-.a-zA-Z0-9]+' ${plist_path})
    verbose "mounted on ${mount}"

  #  #TODO: ERROR

    verbose "Installing ${target}"
    verbose " NOTE: You might have to enter your password to allow that package to be installed!"
    package=$(find ${mount} -name '*.pkg' -mindepth 1 -maxdepth 1)
    verbose "  Package: ${package}"
    sudo installer -pkg ${package} -target /

    verbose "Unmounting ${target}"
    hdiutil eject ${mount} > /dev/null
  fi
}

# Main
parse_args "$@"
install_dmg facter "*" http://downloads.puppetlabs.com/mac/
install_dmg hiera  "*" http://downloads.puppetlabs.com/mac/
install_dmg puppet "*" http://downloads.puppetlabs.com/mac/

verbose "Creating user/group resources"
sudo puppet resource group puppet ensure=present
sudo puppet resource user  puppet ensure=present gid=puppet shell="/sbin/nologin"

# Hide all users from the loginwindow with uid below 500, which will include the puppet user
hide_500=$(/usr/libexec/PlistBuddy -c "print :Hide500Users" /Library/Preferences/com.apple.loginwindow.plist)
if [ -z "$hide_500" -o "$hide_500" = "false" ]; then
  sudo /usr/libexec/PlistBuddy -c "set :Hide500Users:true" /Library/Preferences/com.apple.loginwindow.plist
# sudo defaults write /Library/Preferences/com.apple.loginwindow Hide500Users -bool YES
fi

verbose "Creating folders"
sudo mkdir -p /var/log/puppet
sudo mkdir -p /var/lib/puppet
sudo mkdir -p /var/lib/puppet/cache
sudo mkdir -p /etc/puppet/manifests
sudo mkdir -p /etc/puppet/ssl
sudo chown -R puppet:puppet /var/lib/puppet
sudo chmod 750 /var/lib/puppet
sudo chown -R puppet:puppet /var/log/puppet
sudo chmod 750 /var/log/puppet
sudo chown -R puppet:puppet /etc/puppet
sudo chmod 750 /etc/puppet /etc/puppet/manifest
