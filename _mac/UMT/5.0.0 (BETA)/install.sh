#!/bin/bash
# UMT 4.7.5 installation script
# https://github.com/utmapp/UTM/releases/tag/v4.7.5

export PATH=$PATH:/sbin:/usr/sbin
source "common.sh"
trap 'finally_dmg "$dmg_mount_point" $?' EXIT SIGINT
result=''

# external named parameters
# -m "install"|"upgrade"
# -p "/Applications"|"custom_path"
# -f "App folder name.app", for upgrade only
# -s "error|kill|ignore". Default="kill" and continue deployment
# -v "ERR|WARN|INFO|DBG". Default="INFO"
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

### VirtualBuddy install\update

function main() {
  # internal parameters
    display_name='UTM' # for messages only
    log -m "$(printf 'start deploying "%s"' "$display_name")" -n "INFO"

    proc_names=("UTM")  # array, f.e. ("process1" "process2")
    dmg_mount_point='./local_mnt'
    default_app_folder="UTM.app"
    dmg_root_folder="${dmg_mount_point}/UTM"
    src_app_folder="${dmg_root_folder}/${default_app_folder}"
    binary_path="./${src_app_folder}/Contents/MacOS/UTM"
    get_setup_by_ext "dmg" && setup_file="$result" || exit $?

  # attach dmg file
    attach_dmg "$setup_file" "$dmg_root_folder" "$src_app_folder" "$dmg_mount_point" || exit $?

    dmg_root_folder="$result"
    if [[ -d "${result}/Contents/MacOS" ]]; then
        src_app_folder="$result"
    else
        src_app_folder="${result}/${default_app_folder}"
    fi
    binary_path="${src_app_folder}/Contents/MacOS/VirtualBuddy"

    if [[ "$deploy_mode" == 'install' ]]; then
        app_folder_name="$(basename "$src_app_folder")"
    else
        app_folder_name="$upgrade_app_folder"
    fi

  # test application binary architecture
    test_binary_arch "$binary_path" || exit $?

  # test running processes
    if [[ "$app_process_mode" == 'kill' ]]; then
        kill_process "${proc_names[@]}"
    fi

    if [[ "$app_process_mode" != 'ignore' ]]; then
        test_process "${proc_names[@]}" || exit $?
    fi

  # deploy software\update
    copy_app_folder "$src_app_folder" "$inst_root_folder" "$app_folder_name" "$deploy_mode" || exit $?

  # detach_dmg, see in trap (finally_dmg)
    exit 0
}

main