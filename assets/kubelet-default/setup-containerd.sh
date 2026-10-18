#!/bin/bash
set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

# PORKADOT_CONTAINERD_CONFIG_DIR is only meant to be overridden by tests.
CONFIG_DIR=${PORKADOT_CONTAINERD_CONFIG_DIR:-/etc/containerd}
CONFIG=${CONFIG_DIR}/config.toml

# runc options section of the CRI plugin.
# config version 2 (containerd 1.x) and config version 3 (containerd 2.x) use different paths.
# config version 4 (containerd 2.3+) uses the same path as config version 3.
V1_RUNC_OPTIONS='plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options'
V2_RUNC_OPTIONS='plugins."io.containerd.cri.v1.runtime".containerd.runtimes.runc.options'

# Prints the version of containerd without the leading `v` (e.g. 2.4.2).
containerd_version() {
  containerd --version | awk '{print $3}' | sed 's/^v//'
}

generate_default_config() {
  containerd config default > "${CONFIG}.default"
  mv "${CONFIG}.default" "${CONFIG}"
}

# Prints the top-level `version` of the config. Keys after the first table header are ignored.
config_version() {
  awk '
    /^[ \t]*\[/ { exit }
    /^[ \t]*version[ \t]*=/ {
      sub(/^[^=]*=[ \t]*/, "")
      sub(/[ \t]*(#.*)?$/, "")
      print
      exit
    }
  ' "${CONFIG}"
}

# Sets `SystemdCgroup = true` directly under the given section.
# The existing SystemdCgroup line is replaced, or a new line is inserted after the section header.
# Comments at the end of section headers are ignored.
# Returns 3 without changing the config if the section does not exist.
set_systemd_cgroup() {
  local section=$1
  local tmp
  local rc=0

  tmp=$(mktemp "${CONFIG_DIR}/config.toml.XXXXXX")
  awk -v section="[${section}]" '
    function normalize(s) {
      sub(/[ \t]*#.*$/, "", s)
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      gsub(/\047/, "\"", s)
      return s
    }
    {
      lines[NR] = $0
      if ($0 ~ /^[ \t]*\[/) {
        if (start && !end) { end = NR }
        if (normalize($0) == section) { start = NR }
      } else if (start && !end && !key && $0 ~ /^[ \t]*SystemdCgroup[ \t]*=/) {
        key = NR
      }
    }
    END {
      if (!start) { exit 3 }
      header_indent = lines[start]
      sub(/[^ \t].*$/, "", header_indent)
      for (i = 1; i <= NR; i++) {
        if (i == key) {
          indent = lines[i]
          sub(/[^ \t].*$/, "", indent)
          print indent "SystemdCgroup = true"
          continue
        }
        print lines[i]
        if (i == start && !key) { print header_indent "  SystemdCgroup = true" }
      }
    }
  ' "${CONFIG}" > "${tmp}" || rc=$?

  if [[ ${rc} == 0 ]]; then
    cat "${tmp}" > "${CONFIG}"
  fi
  rm -f "${tmp}"
  return ${rc}
}

configure_systemd_cgroup() {
  local major=$1
  local minor=$2
  local version
  local section
  local rc=0
  version=$(config_version)

  case "${version}" in
    2)
      # containerd 2.x also reads config version 2 and migrates it on load.
      section=${V1_RUNC_OPTIONS}
      ;;
    3)
      if [[ ${major} == 1 ]]; then
        echo "${CONFIG} is config version 3, but containerd ${major}.x does not support it" >&2
        exit 1
      fi
      section=${V2_RUNC_OPTIONS}
      ;;
    4)
      if [[ ${major} == 1 ]] || (( minor < 3 )); then
        echo "${CONFIG} is config version 4, but containerd ${major}.${minor} does not support it (2.3 or later is required)" >&2
        exit 1
      fi
      section=${V2_RUNC_OPTIONS}
      ;;
    *)
      echo "Unsupported containerd config version in ${CONFIG}: '${version}'" >&2
      exit 1
      ;;
  esac

  set_systemd_cgroup "${section}" || rc=$?
  if [[ ${rc} == 3 ]]; then
    # Do not create the runc options section.
    # A section defined without runtime_type replaces the default runc runtime of containerd.
    # Stop here because kubelet uses the systemd cgroup driver and containerd would keep cgroupfs.
    cat >&2 <<EOF
ERROR: [${section}] is not found in ${CONFIG}.
SystemdCgroup cannot be set, and containerd would not match the systemd cgroup driver of kubelet.
Fix it in one of the following ways, then run setup-containerd again:
  - Add the [${section}] section with SystemdCgroup = true to ${CONFIG}.
    If the runc options are written as an inline table (options = { ... }), rewrite them as this section.
  - Move ${CONFIG} aside (e.g. to ${CONFIG}.porkadot-bak) so that setup-containerd creates it from containerd config default.
EOF
    exit 1
  elif [[ ${rc} != 0 ]]; then
    exit 1
  fi
}

VERSION=$(containerd_version)
MAJOR=$(echo "${VERSION}" | cut -d. -f1)
MINOR=$(echo "${VERSION}" | cut -d. -f2)
case "${MAJOR}" in
  1|2)
    ;;
  *)
    echo "Unsupported containerd major version: $(containerd --version)" >&2
    exit 1
    ;;
esac

mkdir -p "${CONFIG_DIR}"

if [[ -f ${ROOT}/containerd/config.toml ]]; then
  # A user provided config overrides everything as is.
  cp -rp "${ROOT}/containerd/config.toml" "${CONFIG}"
else
  # Do not regenerate an existing config, which may contain settings added by others (e.g. NVIDIA Container Toolkit).
  # A config without version (e.g. the one shipped by Docker's containerd.io package) is regenerated after a backup.
  if [[ ! -f ${CONFIG} ]]; then
    generate_default_config
  elif [[ -z $(config_version) ]]; then
    backup=${CONFIG}.porkadot-bak.$(date +%Y%m%d%H%M%S)
    cp -p "${CONFIG}" "${backup}"
    echo "Regenerating ${CONFIG} because it has no version. The original is saved as ${backup}."
    generate_default_config
  fi
  configure_systemd_cgroup "${MAJOR}" "${MINOR}"
fi

systemctl restart containerd
