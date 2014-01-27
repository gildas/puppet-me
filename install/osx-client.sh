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
  local url="$3"

  if [ "$version" = "*" ]; then
    verbose "Checking version numbers for ${module}"
    archive=$(curl --silent --list-only "${url}/" | grep --ignore-case "$module" | tail -1 | sed -e 's/.*href="\([^"]*\)".*/\1/')
  else
    verbose "Targetting version ${version} for module ${module}"
    archive="${module}-${version}.dmg"
  fi
  verbose "Downloading $archive"
  source="${url}/${archive}"
  target="$HOME/Downloads/${archive}"
  [ -f "${target}" ] && verbose "Deleting existing archive" && rm -f "$target"
#  curl --location --show-error --progress-bar --output "${target}" "${source}"

#  verbose "mounting ${target}"
#  local plist_path=$(mktemp -t $module)
#  hdiutil attach -plist ${target} > ${plist_path}
#  verbose "plist_path: ${plist_path}"
#  mount=$(grep -E -o '/Volumes/[-.a-zA-Z0-9]+' ${plist_path})
#  verbose "mounted on ${mount}"

#  #TODO: ERROR

#  verbose "Installing ${target}"
#  package=$(find ${mount} -name '*.pkg' -mindepth 1 -maxdepth 1)
#  verbose "  Package: ${package}"
#  sudo installer -pkg ${package} -target / > /dev/null

#  verbose "Unmounting ${target}"
#  hdiutil eject ${mount} > /dev/null
}

# Main
parse_args "$@"
install_dmg facter "*" http://downloads.puppetlabs.com/mac/
install_dmg hiera  "*" http://downloads.puppetlabs.com/mac/
install_dmg puppet "*" http://downloads.puppetlabs.com/mac/
