#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_CTRL_ROOT="${SCRIPT_DIR}"
BUILD_DIR="${VM_CTRL_ROOT}/build"
EXECUTABLE_PATH="${BUILD_DIR}/vm_ctrl"
REQUIRED_ROS_DISTRO_FILE="${VM_CTRL_ROOT}/.ros_distro"
RELEASE_USE_ROS2_FILE="${VM_CTRL_ROOT}/.release_use_ros2"

read_file_trimmed() {
  local f="$1" default="${2:-}"
  [ -f "$f" ] && tr -d '[:space:]' < "$f" || echo "$default"
}

REQUIRED_ROS_DISTRO="$(read_file_trimmed "${REQUIRED_ROS_DISTRO_FILE}")"
RELEASE_USE_ROS2="$(read_file_trimmed "${RELEASE_USE_ROS2_FILE}" "ON")"

# ── executable check ────────────────────────────────────────────────────────
test -x "${EXECUTABLE_PATH}" || {
  echo "Missing executable: ${EXECUTABLE_PATH}"
  exit 1
}

# ── LD_LIBRARY_PATH ─────────────────────────────────────────────────────────
append_lib_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+${LD_LIBRARY_PATH}:}${dir}"
}

# Keep host/ROS paths ahead of bundled fallback libs.
append_lib_dir "${VM_CTRL_ROOT}/lib"
append_lib_dir "${VM_CTRL_ROOT}/third_party/onnx_runtime/lib"

# ── ROS 2 sourcing ───────────────────────────────────────────────────────────
source_bash() {
  # Source a bash setup file with -u temporarily relaxed (ROS scripts use unbound vars)
  local f="$1"
  [ -f "$f" ] || return 0
  set +u
  # shellcheck disable=SC1090
  source "$f"
  set -u
}

if [ "${RELEASE_USE_ROS2}" = "ON" ]; then
  if [ -z "${REQUIRED_ROS_DISTRO}" ]; then
    echo "Missing runtime ROS distro metadata: ${REQUIRED_ROS_DISTRO_FILE}"
    exit 1
  fi

  if [ -n "${ROS_DISTRO:-}" ] && [ "${ROS_DISTRO}" != "${REQUIRED_ROS_DISTRO}" ]; then
    echo "This vm_ctrl bundle was built for ROS 2 ${REQUIRED_ROS_DISTRO}, but the current shell uses ${ROS_DISTRO}."
    echo "Source /opt/ros/${REQUIRED_ROS_DISTRO}/setup.bash and rebuild/source the matching ros2_ws first."
    exit 1
  fi

  source_bash "/opt/ros/${REQUIRED_ROS_DISTRO}/setup.bash"

  if [ "${ROS_DISTRO:-}" != "${REQUIRED_ROS_DISTRO}" ]; then
    echo "Unable to load ROS 2 ${REQUIRED_ROS_DISTRO} from /opt/ros/${REQUIRED_ROS_DISTRO}/setup.bash"
    exit 1
  fi

  DEFAULT_ROS2_SETUP="$(realpath -m "${VM_CTRL_ROOT}/../ros2_ws")/install/setup.bash"
  ROS2_SETUP="${VM_CTRL_ROS2_SETUP:-${DEFAULT_ROS2_SETUP}}"

  case "${ROS2_SETUP}" in
    /*) ;;
    *)
      echo "ROS setup path must be absolute: ${ROS2_SETUP}"
      echo "Set VM_CTRL_ROS2_SETUP to an absolute setup.bash path."
      exit 1
      ;;
  esac

  if [ ! -f "${ROS2_SETUP}" ]; then
    echo "Missing ROS workspace setup: ${ROS2_SETUP}"
    echo "Default is ../ros2_ws/install/setup.bash relative to vm_ctrl."
    echo "Override with VM_CTRL_ROS2_SETUP=/absolute/path/to/install/setup.bash when needed."
    exit 1
  fi

  source_bash "${ROS2_SETUP}"
fi

cd "${BUILD_DIR}"
exec "${EXECUTABLE_PATH}" "$@"
