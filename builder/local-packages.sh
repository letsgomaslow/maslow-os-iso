#!/bin/bash

# One list drives local builds, network exclusions, and mirror retention.
# Bitwarden is supplied by Arch; these CLI recipes are built from our checkout.
omarchy_local_packages() {
  printf '%s\n' \
    "${OMARCHY_SETTINGS_PACKAGE:-omarchy-settings-dev}" \
    "${OMARCHY_RUNTIME_PACKAGE:-omarchy-dev}" \
    "${OMARCHY_NVIM_PACKAGE:-omarchy-nvim}" \
    openai-codex-bin \
    claude-code \
    hermes-agent
}

# Local packages bypass the online resolver, but their external runtime
# dependencies still belong in the offline mirror (for example Hermes' Node).
omarchy_local_dependencies() {
  local mirror=$1 package artifact dependency name local_name is_local metadata line
  local -a names artifacts
  mapfile -t names < <(omarchy_local_packages)
  for package in "${names[@]}"; do
    artifacts=("$mirror/$package-"*.pkg.tar.zst)
    if (( ${#artifacts[@]} != 1 )) || [[ ! -f ${artifacts[0]} ]]; then
      echo "ERROR: expected one local artifact for $package" >&2
      return 1
    fi
    artifact=${artifacts[0]}
    metadata=$(bsdtar -xOf "$artifact" .PKGINFO) || return 1
    while IFS= read -r line; do
      [[ $line == "depend = "* ]] || continue
      dependency=${line#depend = }
      name=${dependency%%[<>=]*}
      is_local=false
      for local_name in "${names[@]}"; do
        [[ $name == "$local_name" ]] && is_local=true
      done
      if [[ $is_local == "false" ]]; then
        printf '%s\n' "$dependency"
      fi
    done <<< "$metadata"
  done
}
