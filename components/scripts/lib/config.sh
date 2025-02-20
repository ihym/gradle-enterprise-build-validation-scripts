#!/usr/bin/env bash

# shellcheck disable=SC2034 # not all of the variables set in this function are used by all scripts
process_arguments() {
  parse_commandline "$@"

  if [ -n "${_arg_git_repo+x}" ]; then
    git_repo="${_arg_git_repo}"
    project_name="$(basename -s .git "${git_repo}")"
  fi

  if [ -n "${_arg_git_branch+x}" ]; then
    git_branch="${_arg_git_branch}"
  fi

  if [ -n "${_arg_git_commit_id+x}" ]; then
    git_commit_id="${_arg_git_commit_id}"
  fi

  if [ -n "${_arg_git_options+x}" ]; then
    git_options="${_arg_git_options}"
  fi

  if [ -n "${_arg_project_dir+x}" ]; then
    project_dir="${_arg_project_dir}"
  fi

  # shellcheck disable=SC2154
  if [ -n "${_arg_tasks+x}" ]; then
    tasks="${_arg_tasks}"
    remove_clean_from_tasks
  fi

  # shellcheck disable=SC2154
  if [ -n "${_arg_goals+x}" ]; then
    tasks="${_arg_goals}"
    remove_clean_from_tasks
  fi

  if [ -n "${_arg_args+x}" ]; then
    extra_args="${_arg_args}"
  fi

  #shellcheck disable=SC2154
  if [ -n "${_arg_mapping_file+x}" ]; then
    mapping_file="${_arg_mapping_file}"
  fi

  if [ -n "${_arg_gradle_enterprise_server+x}" ]; then
    ge_server="${_arg_gradle_enterprise_server}"
  fi

  #shellcheck disable=SC2154
  if [ -n "${_arg_enable_gradle_enterprise+x}" ]; then
    enable_ge="${_arg_enable_gradle_enterprise}"
  fi

  build_scan_publishing_mode=on
  if [ -n "${_arg_disable_build_scan_publishing+x}" ]; then
    if [[ "${_arg_disable_build_scan_publishing}" == "on" ]]; then
      build_scan_publishing_mode=off
    fi
  fi

  if [ -n "${_arg_fail_if_not_fully_cacheable+x}" ]; then
    fail_if_not_fully_cacheable="${_arg_fail_if_not_fully_cacheable}"
  fi

  if [ -n "${_arg_interactive+x}" ]; then
    interactive_mode="${_arg_interactive}"
  fi
}

validate_required_config() {
  if [ -z "${git_repo}" ]; then
    _PRINT_HELP=yes die "ERROR: Missing required argument: --git-repo" "${INVALID_INPUT}"
  fi

  if [ -z "${tasks}" ]; then
    if [[ "${BUILD_TOOL}" == "Maven" ]]; then
      _PRINT_HELP=yes die "ERROR: Missing required argument: --goals" "${INVALID_INPUT}"
    else
      _PRINT_HELP=yes die "ERROR: Missing required argument: --tasks" "${INVALID_INPUT}"
    fi
  fi

  if [[ "${enable_ge}" == "on" && -z "${ge_server}" && "${build_scan_publishing_mode}" == "on" ]]; then
    _PRINT_HELP=yes die "ERROR: --gradle-enterprise-server is required when using --enable-gradle-enterprise." "${INVALID_INPUT}"
  fi
}

prompt_for_setting() {
  local prompt primary_default secondary_default default variable defaultDisplay
  prompt="$1"
  primary_default="$2"
  secondary_default="$3"
  variable="$4"

  if [ -n "$primary_default" ]; then
    default="${primary_default}"
  else
    default="${secondary_default}"
  fi

  if [ -n "$default" ]; then
    defaultDisplay="(${default}) "
  fi

  while :; do
    read -r -p "${USER_ACTION_COLOR}${prompt} ${DIM}${defaultDisplay}${RESTORE}" "${variable?}"

    UP_ONE_LINE="\033[1A"
    ERASE_LINE="\033[2K"
    echo -en "${UP_ONE_LINE}${ERASE_LINE}"

    if [ -z "${!variable}" ]; then
      if [ -n "${default}" ]; then
        eval "${variable}=\${default}"
        break
      fi
    else
      break
    fi
  done

  echo "${USER_ACTION_COLOR}${prompt} ${CYAN}${!variable}${RESTORE}"
}

collect_git_details() {
  collect_git_repo
  collect_git_branch
  collect_git_commit_id
  collect_git_options
}

collect_git_repo() {
  prompt_for_setting "What is the URL for the Git repository that contains the project to validate?" "${git_repo}" '' git_repo
  project_name=$(basename -s .git "${git_repo}")
}

collect_git_branch() {
  local default_branch="<the repository's default branch>"
  prompt_for_setting "What is the branch for the Git repository that contains the project to validate?" "${git_branch}" "${default_branch}" git_branch

  if [[ "${git_branch}" == "${default_branch}" ]]; then
    git_branch=''
  fi
}

collect_git_commit_id() {
  local default_commit_id="<the branch's head>"
  prompt_for_setting "What is the commit id for the Git repository that contains the project to validate?" "${git_commit_id}" "${default_commit_id}" git_commit_id

    if [[ "${git_commit_id}" == "${default_commit_id}" ]]; then
      git_commit_id=''
    fi
}

collect_git_options() {
   local default_git_options="--depth=1"
   prompt_for_setting "What are additional options to use when cloning the Git repository?" "${git_options}" "${default_git_options}" git_options
 }

collect_gradle_details() {
  collect_root_project_directory
  collect_gradle_tasks
  collect_extra_args
}

collect_maven_details() {
  collect_root_project_directory
  collect_maven_goals
  collect_extra_args
}

collect_root_project_directory() {
  local default_project_dir="<the repository's root directory>"
  prompt_for_setting "What is the directory to invoke the build from?" "${project_dir}" "${default_project_dir}" project_dir
  if [[ "${project_dir}" == "${default_project_dir}" ]]; then
    project_dir=''
  fi
}

collect_gradle_tasks() {
  prompt_for_setting "What are the Gradle tasks to invoke?" "${tasks}" "assemble" tasks
  remove_clean_from_tasks
}

collect_maven_goals() {
  prompt_for_setting "What are the Maven goals to invoke?" "${tasks}" "package" tasks
  remove_clean_from_tasks
}

collect_extra_args() {
  local default_extra_args="<none>"
  prompt_for_setting "What are additional cmd line arguments to pass to the build invocation?" "${extra_args}" "${default_extra_args}" extra_args
  if [[ "${extra_args}" == "${default_extra_args}" ]]; then
    extra_args=''
  fi
}

collect_mapping_file() {
  local default_mapping_file="<use default mapping>"
  prompt_for_setting "What custom value mapping file should be used?" "${mapping_file}" "${default_mapping_file}" mapping_file
  if [[ "${mapping_file}" == "${default_mapping_file}" ]]; then
    mapping_file=''
  fi
}

remove_clean_from_tasks() {
  tasks=$(remove_clean_task "${tasks}")
}

remove_clean_task() {
  local t
  IFS=' ' read -r -a t <<< "$1"
  for i in "${!t[@]}"; do
    if [[ "${t[i]}" == "clean" ]]; then
      unset 't[i]'
    fi
  done

  echo -n "${t[@]}"
}

print_extra_args() {
  if [ -n "${extra_args}" ]; then
    echo " ${extra_args}"
  fi
}

generate_command_to_repeat_experiment() {
  local cmd
  cmd=("./${SCRIPT_NAME}" "-r" "${git_repo}")

  if [ -n "${git_branch}" ]; then
    cmd+=("-b" "${git_branch}")
  fi

  if [ -n "${git_commit_id}" ]; then
    cmd+=("-c" "${git_commit_id}")
  fi

  if [ "${git_options}" != "--depth=1" ]; then
    cmd+=("-o" "${git_options}")
  fi

  if [ -n "${project_dir}" ]; then
    cmd+=("-p" "${project_dir}")
  fi

  if [[ "${BUILD_TOOL}" == "Gradle" ]]; then
    cmd+=("-t" "${tasks}")
  fi

  if [[ "${BUILD_TOOL}" == "Maven" ]]; then
    cmd+=("-g" "${tasks}")
  fi

  if [ -n "${extra_args}" ]; then
    cmd+=("-a" "${extra_args}")
  fi

  if [ -n "${ge_server}" ]; then
    cmd+=("-s" "${ge_server}")
  fi

  if [[ "${enable_ge}" == "on" ]]; then
    cmd+=("-e")
  fi

  if [[ "${build_scan_publishing_mode}" == "off" ]]; then
    cmd+=("-x")
  fi

  if [[ "${fail_if_not_fully_cacheable}" == "on" ]]; then
    cmd+=("-f")
  fi

  if [[ "${_arg_debug}" == "on" ]]; then
    cmd+=("--debug")
  fi

  printf '%q ' "${cmd[@]}"
}

