#!/bin/bash

export PATH=$PATH:/sbin:/usr/sbin
source "common.sh"
trap 'finally_pkg $?' EXIT SIGINT
result=''

# external named parameters
# -m "install"|"upgrade"
# -p "/Applications"|"custom_path"
# -f "App folder name.app", for upgrade only
# -s "error|kill|ignore". Default="kill" and continue deployment
# -v "ERR|WARN|INFO|DBG"
# -b "app.new.build.number"

agruments="$@"
inv_script="$(basename "$0")"
log_started "$inv_script" "$agruments"

validate_params "$@" || exit $?
deploy_mode="$m"
inst_root_folder="$p"
app_process_mode="$s"
upgrade_app_folder="$f"
new_app_ver="$b"
log_level="$v"
#log_level="DBG"

### Microsoft Teams install\update

function main() {
  # internal parameters
    display_name='Microsoft Teams' # for messages only
    log -m "$(printf 'start deploying "%s"' "$display_name")" -n "INFO"

    proc_names=("MSTeams$") # array, f.e. ("process1" "process2")
    default_app_folder="Microsoft Teams.app"  # for install mode

    if [[ "$deploy_mode" == 'install' ]]; then
        app_folder_name="$default_app_folder"
    else
        app_folder_name="$upgrade_app_folder"
    fi

  # test setup file
    get_setup_by_ext "pkg" && setup_file="$result" || exit $?

  # test application binary architecture
  # test_binary_arch "$binary_path" || exit $?

  # test running processes
    if [[ "$app_process_mode" == 'kill' ]]; then
        kill_process "${proc_names[@]}"
    fi

    if [[ "$app_process_mode" != 'ignore' ]]; then
        test_process "${proc_names[@]}" || exit $?
    fi

  # deploy software\update
    deploy_pkg "$setup_file" "$inst_root_folder" "$app_folder_name" "$deploy_mode" || exit $?
    exit 0
}


main