#!/bin/bash
export PATH=$PATH:/sbin:/usr/sbin

# common functions #

function print_revision() {
    local revision="1.3"
    msg=$(printf 'common.sh script revision: %s\n' "${revision}")
    log -m "$msg" -n "INFO"
    return 0
}


function validate_params() {
    # -m "install"|"upgrade"
    # -p "/Applications"|"custom_path"
    # -f "/Firefox.app", for upgrade only
    # -s "error|kill|ignore", test process, default="kill" and stop deployment
    # -v "ERR|WARN|INFO|DBG|DBG2", logging level. Default="INFO"
    # -b "app.new.build.number"

    local msg
    local OPTIND
    local OPTSTRING="m:p:f:s:v:b:"
    local OPTERR=0
    local err_code=1
    local def_log_level="INFO"
    if [[ -z "$log_level" ]]; then
        log_level="$def_log_level"    # global variable
    fi

    while getopts ${OPTSTRING} opt; do
        case ${opt} in
            m)  m="${OPTARG}" ;;
            p)  p="${OPTARG}" ;;
            f)  f="${OPTARG}" ;;
            s)  s="${OPTARG}" ;;
            v)  v="${OPTARG}" ;;
            b)  b="${OPTARG}" ;;
        esac

        if [[ "${OPTARG}" == "-"* ]]; then
            msg=$(printf 'Argument %s has invalid value "%s". Exit code: %s.' "-${opt}" "${OPTARG}" "$err_code")
            echo "$msg" >&2; log -m "$msg" -n "ERR"
            return $err_code
        fi
    done

    if [[ $OPTIND -eq 1 || -z "$m" ]]; then
        msg=$(printf 'Mandatory option "-m" is not specified. Exit code: %s.' "$err_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $err_code
    fi

    if [[ "$m" != "install" && "$m" != "upgrade" ]]; then
        msg=$(printf 'Unknown deployment mode was specified as parameter value here: -m "%s"' "$m")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $err_code
    fi

    if [[ -z "$f" && "$m" == 'upgrade' ]]; then
        #msg=$(printf 'Argument %s is empty. Exit code %s.' "-f" "$err_code")
        msg=$(printf 'Target folder name was not specified for application update. Exit code: %s.' "$err_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $err_code
    fi

    p=${p:-"/Applications"}           # default value = "/Applications
    p=$(echo "$p" | sed 's/\/$//')    # remove last '/' if specified
    s=${s:-"kill"}                    # default value = "kill"
    v=${v:-"$def_log_level"}          # default value = $def_log_level ("INFO")

    return 0
}


function attach_dmg() {
    local setup_file="$1"
    local root_dmg_folder="$2"
    local app_folder="$3"
    local mount_point="$4"
    local exit_code=0
    local err_code=1
    local msg

    msg=$(printf 'params: setup_file="%s" root_dmg_folder="%s" app_folder="%s" mount_point="%s"' "$1" "$2" "$3" "$4")
    log -m "$msg" -n "DBG2"

    if [[ -z "$mount_point" || "$mount_point" == "." || "$mount_point" == "/" || "$mount_point" == "./" ]]; then
        msg=$(printf 'Using folder "%s" as a mount point for "%s" is not allowed. Exit code: %s.' "$mount_point" "$setup_file" "$err_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $err_code
    fi

    if [[ ! -d "$mount_point" ]]; then
        msg=$(echo mkdir "$mount_point")
        log -m "$msg" -n "INFO"
        mkdir "$mount_point"
        exit_code=$?
        if [[ $exit_code -ne 0 || ! -d "$mount_point" ]]; then
            msg=$(printf 'Failed to create a mount folder for "%s". Exit code: %s.' "$mount_point" "$exit_code")
            echo "$msg" >&2; log -m "$msg" -n "ERR"
            return $exit_code
        fi
    fi

    if [[ ! -f "$setup_file" ]]; then
        exit_code=1
        msg=$(printf 'Setup file "%s" does not exist. Exit code: %s.' "$setup_file" "$exit_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $exit_code
    fi

    # detach all images attached to mount_point, just in case
    detach_dmg "$mount_point"

    # attach dmg
    msg=$(echo hdiutil attach "$setup_file" -mountroot "$mount_point" -nobrowse -readonly -quiet)
    log -m "$msg" -n "INFO"
    hdiutil attach "$setup_file" -mountroot "$mount_point" -nobrowse -readonly -quiet
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        msg=$(printf 'Failed to mount dmg file "%s" to "%s". Exit code: %s' "$setup_file" "$mount_point" "$exit_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $exit_code
    fi

    local mounted_vol=$(ls -d "$mount_point"/* 2>/dev/null | head -1)
    if [[ -z "$mounted_vol" || ! -d "$mounted_vol" ]]; then
        exit_code=1
        msg=$(printf 'No valid mounted volume found in "%s". Exit code: %s' "$mount_point" "$exit_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $exit_code
    fi

    # Set result to the mounted volume path
    result="$mounted_vol"

    # Check if app folder exists
    local actual_app_folder
    if [[ -d "${mounted_vol}/Contents/MacOS" ]]; then
        actual_app_folder="$mounted_vol"
    else
        actual_app_folder="${mounted_vol}/VirtualBuddy.app"
    fi
    if [[ ! -d "$actual_app_folder" ]]; then
        exit_code=1
        msg=$(printf 'Mounted app folder "%s" does not exist. Exit code: %s' "$actual_app_folder" "$exit_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $exit_code
    fi
    return 0
}


function detach_dmg() {
    local root_dmg_folder="$1"
    local msg
    msg=$(printf 'params: root_dmg_folder="%s"' "$root_dmg_folder")
    log -m "$msg" -n "DBG2"

    local images=$(hdiutil info | grep "$(pwd)/local_mnt" | awk '{print $1}')
    if [[ ! -d "$root_dmg_folder" || -z "$images" ]]; then
        log -m "nothing to detach" -n "DBG"
        return 0
    fi

    # detach all dmg images in root folder
    log -m "$(printf 'unmount all dmg images mounted to "%s"' "$root_dmg_folder")" -n "DBG"
    log -m "attached images:" -n "DBG"
    log -m "$(hdiutil info | grep "$(pwd)/local_mnt")" -n "DBG"

    while IFS= read -r line; do
        log -m "$(printf 'hdiutil detach %s -force > /dev/null 2>&1' "$line")" -n "DBG"
        hdiutil detach "${line}" -force > /dev/null 2>&1
    done <<< "$images"     
    local images_left=$(hdiutil info | grep "$(pwd)/local_mnt" | awk '{print $1}')     
    if [[ -z "$images_left" ]]; then         
    log -m "all mounted dmg images have been successfully unmounted." -n "INFO"     
    else         
    log -m "failed to unmount images:" -n "WARN"         
    log -m "$images_left" -n "WARN"     
    fi     
    return 0 
    } 
    function copy_app_folder() {     
        local source_app_path="$1"     
        local target_path="$2"     
        local app_folder="$3"     
        local deploy_mode="$4"     
        local msg; 
        local owner     
        msg=$(printf 'params: source_app_path="%s" target_path="%s" app_folder="%s" deploy_mode="%s"' `     `"$source_app_path" "$target_path" "$app_folder" "$deploy_mode")     
        log -m "$msg" -n "DBG2"     
        local exit_code=0     
        local err_code=1     
        if [[ "$deploy_mode" == 'install' ]]; then         
        dest_folder="$target_path"                                
        # example for install (deploy software): dest_folder="/Applications"     
        else         
        dest_folder="${target_path}/${app_folder}"                  
        # example for upgrade (deploy update): dest_folder="/Applications/Firefox.app"     
        fi     
        # validate params     
        validate_dmg_deploy_params "$source_app_path" || return $?     
        validate_common_deploy_params "$target_path" "$app_folder" "$deploy_mode" "$dest_folder" || return $?     
        # get owner of target folder     
        if [[ "$deploy_mode" == 'upgrade' ]]; then         get_owner "$dest_folder" && owner="$result" || return $?     
        else         
        owner="root:wheel"     
        fi     
        # check if destination folder already exists but mode=install,     
        # f.e. Firefox ESR installation on EP with Firefox ("stable") installed. They have the same folder names     
        if [[ "$deploy_mode" == 'install' ]]; then         
        test_dest_folder "${dest_folder}/${app_folder}" || return $?     
        fi     
        # copy new app version folder     
        local sp="$source_app_path"     
        [[ "$deploy_mode" == "upgrade" ]] && sp="${source_app_path}/"     
        tmpf="${dest_folder}.tmp"     
        if [[ -d "$dest_folder" && "$deploy_mode" == 'upgrade' ]]; then         
        msg=$(printf 'mv "%s" "%s"' "$dest_folder" "$tmpf"); 
        log -m "$msg" -n "INFO"         
        mv "$dest_folder" "$tmpf"     
        # backup/rename current version folder before upgrade     
        fi     
        msg=$(printf 'rsync -a "%s" "%s"' "$sp" "$dest_folder"); 
        log -m "$msg" -n "INFO"     
        rsync -a "$sp" "${dest_folder}"     
        exit_code=$?     
        if [[ $exit_code -ne 0 || ! -d "$dest_folder" ]]; then         
        msg=$(printf 'Failed to copy the source path "%s" to "%s". Exit code: %s' "$source_app_path" "$dest_folder" "$exit_code")         
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        if [[ "$deploy_mode" == 'upgrade' ]]; then
            msg=$(printf 'start renaming the "%s" folder back to "%s"' "$tmpf" "$dest_folder"); 
            log -m "$msg" -n "INFO"
            # remove new version folder if exists
            [[ -d "$dest_folder" ]] && rm -rf "$dest_folder"
            # restore current version folder if upgrade failed and new version folder is removed                                
            [[ ! -d "$dest_folder" && -d "$tmpf" ]] && mv "$tmpf" "$dest_folder"            
        fi
        return $exit_code
    fi
    if [[ -d "$tmpf" && "$deploy_mode" == 'upgrade' ]]; then
        msg=$(printf 'rm -rf "%s"' "$tmpf"); log -m "$msg" -n "INFO"
        # remove backup folder
        rm -rf "$tmpf"                                                                      
    fi

    # set owner to app destination folder
    set_owner "${target_path}/${app_folder}" "$owner" || return $?

    return $exit_code
}


function test_dest_folder() {
    local folder="$1"
    local msg
    err_code=1
    msg=$(printf 'params: folder="%s"' "$1"); log -m "$msg" -n "DBG2"
    if [[ -d "$folder" ]]; then
        exit_code=$err_code
        msg=$(printf 'Destination folder "%s" already exists. Exit code: %s' "$folder" "$exit_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
    fi
    return $exit_code
}


function get_owner() {
    local folder="$1"
    result=""

    local usr; local grp; local msg
    err_code=1

    msg=$(printf 'params: folder="%s"' "$folder")
    log -m "$msg" -n "DBG2"

    usr=$(stat -f '%Su' "$folder")
    grp=$(stat -f '%Sg' "$folder")

    msg=$(printf 'owner:group="%s"' "$usr:$grp")
    log -m "$msg" -n "INFO"

    if [[ -z "$usr" ]]; then
        msg=$(printf 'Failed to retrieve the owner of "%s" folder. The "user" field is empty. Exit code: %s' "$folder" "$err_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        exit_code=$err_code
    fi

    if [[ -z "$grp" ]]; then
        msg=$(printf 'Failed to retrieve the owner of "%s" folder. The "group" field is empty. Exit code: %s' "$folder" "$err_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        exit_code=$err_code
    fi

    # test user is deleted
    userID=$(id -u "$usr" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        result="$usr:$grp"
    else
        result="root:wheel"
        msg=$(printf 'id: "%s": no such user. owner:group="%s"' "$usr" "$result")
        log -m "$msg" -n "INFO"
    fi

    log -m "return $exit_code" -n "DBG2"
    return $exit_code
}


function set_owner() {
    local folder="$1"
    local owner="$2"
    local msg

    msg=$(printf 'params: folder="%s" owner="%s"' "$folder" "$owner"); log -m "$msg" -n "DBG2"
    msg=$(printf 'setting "%s" as the owner for "%s" folder' "$owner" "$folder"); log -m "$msg" -n "INFO"

    log -m "$(printf 'chown -R "%s" "%s"' "$owner" "$folder")" -n "INFO"
    chown -R "$owner" "$folder"
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        msg=$(printf 'Failed to set "%s" as the owner for folder "%s". Exit code: %s' "$owner" "$folder" "$exit_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        # log -m "$(echo rm -rf "$folder")" -n "DBG"
        # rm -rf "$folder"
    fi
    log -m "return $exit_code" -n "DBG2"
    return $exit_code
}


function get_setup_by_ext() {
    local ext="$1"
    local search_paths=(".")
    local filename=''; local msg=''; local exit_code=0; result=""

    msg=$(printf 'params: ext="%s"' "$ext")
    log -m "$msg" -n "DBG2"

    for p in "${search_paths[@]}"; do
        filename=$(ls -1 "$p" | grep -i "\.$ext$" | head -n 1 )
        if [[ "$filename" != "" ]]; then
            break
        fi
    done

    if [[ "$filename" == "" ]]; then
        exit_code=1
        msg=$(printf 'Setup file "*.%s" was not found. Exit code: %s' "$ext" "$exit_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
    else
        log -m "Setup file: ${filename}" -n "INFO"
        result="$filename"
        exit_code=0
    fi
    log -m "return $exit_code" -n "DBG2"
    return $exit_code
}


function unzip_archive() {
    local zipfile="$1"
    local dest_fold="$2"
    local exit_code=0; local msg

    msg=$(printf 'params: zipfile="%s" dest_fold="%s"' "$zipfile" "$dest_fold")
    log -m "$msg" -n "DBG2"

    local file_ext=$(echo "$zipfile" | grep -i "\.zip$")
    if [[ -z "$file_ext" ]]; then
        exit_code=1
        msg=$(printf 'File "%s" is not a zip archive. Exit code: %s' "$zipfile" "$exit_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $exit_code
    fi

    if [[ ! -f "$zipfile" ]]; then
        exit_code=1
        msg=$(printf 'File "%s" does not exist. Exit code: %s' "$zipfile" "$exit_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $exit_code
    fi

    # [[ ! -d "$dest_fold" ]] && mkdir "$dest_fold"
    # unzip -qq -o "$zipfile" -d "$dest_fold"

    log -m "$(echo ditto -x -k "$zipfile" "$dest_fold")" -n "INFO"
    ditto -x -k "$zipfile" "$dest_fold"
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        msg=$(printf 'Failed to unzip file "%s". Exit code: %s.' "$zipfile" "$exit_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
    else
        msg=$(printf 'The content of "%s" file is successfully extracted to "%s"' "$zipfile" "$dest_fold")
        log -m "$msg" -n "INFO"
    fi
    log -m "return $exit_code" -n "DBG2"
    return $exit_code
}


function test_process() {
    local last_param="${!#}"
    local all_params=( "$@" )
    local exit_code=0; local procs; local msg

	if [[ $last_param = type:* ]]; then
		proc_names=("${all_params[@]:0:$#-1}")
    else
        proc_names=("${all_params[@]}")
	fi

    if [[ -z ${proc_names[*]} || ${#proc_names[@]} -eq 0 ]]; then
      log -m "$(printf 'The proc_names array is empty.')" -n "INFO"
      return 0
    fi

    for p in "${proc_names[@]}"; do
        log -m "$(printf 'checking that the "%s" process does not exist.' "$p")" -n "INFO"
        log -m "$(printf 'pgrep -i "%s"' "$p")" -n "DBG"
		[[ $last_param = type:pid ]] && procs=$(ps -o pid= -p "$p") || procs=$(pgrep -d "," -i "$p")

        if [[ -n $procs ]]; then
            exit_code=1
            msg=$(printf 'Cannot proceed while the process "%s" (pid: %s) is running.\nClose the process and try deploying again.\n' "$p" "$procs")
            echo "$msg" >&2; log -m "$msg" -n "ERR"
        else
            log -m "found: 0" -n "INFO"
        fi
    done
    log -m "return $exit_code" -n "DBG2"
    return $exit_code
}


function kill_process() {
	local last_param="${!#}"
    local all_params=( "$@" )
    local msg; local proc_found; local procs; local log_lv

	if [[ $last_param = type:* ]]; then
		proc_names=("${all_params[@]:0:$#-1}")
    else
        proc_names=("${all_params[@]}")
	fi

    if [[ -z ${proc_names[*]} || ${#proc_names[@]} -eq 0 ]]; then
      log -m "$(printf 'The proc_names array is empty.')" -n "INFO"
      return 0
    fi

    local timeout=$((60))  # Total duration to monitor in seconds (1 minute)
    local sleep_interval=1  # Interval between checks in seconds
    local iter=$((timeout / sleep_interval))

    for p in "${proc_names[@]}"; do
		[[ $last_param = type:pid ]] && procs=$(ps -o pid= -p "$p") || procs=$(pgrep -d "," -i "$p")

        if [[ -n "$procs" ]]; then
            log -m "$(printf 'found: "%s"' "$procs")" -n "$log_lv" -n "INFO"

			if [[ $last_param = type:pid ]]; then
                log -m "$(printf 'kill -SIGTERM "%s"' "$p")" -n "INFO"
				kill -SIGTERM "$p"
    		else
                log -m "$(printf 'pkill -SIGTERM -i "%s"' "$p")" -n "INFO"
				pkill -SIGTERM -i "$p"
    		fi
        fi
    done

    local i=0
    while [[ $i -lt $iter ]]; do
        proc_found="false"
        if [[ $i -eq 0 ]]; then log_lv="INFO"; else log_lv="DBG"; fi
        for p in "${proc_names[@]}"; do
            log -m "$(printf 'checking that the "%s" process does not exist.' "$p")" -n "$log_lv"

			[[ $last_param = type:pid ]] && procs=$(ps -o pid= -p "$p") || procs=$(pgrep -d "," -i "$p")

            if [[ -n "$procs" ]]; then
                log -m "$(printf 'Cannot proceed while the process "%s" (pid: %s) is running. Waiting for process termination.' "$p" "$procs")" -n "$log_lv"
                proc_found="true"
            else
                log -m "found: 0" -n "$log_lv"
            fi
        done

        if [[ "$proc_found" == "true" ]]; then
            log -m "$(printf 'testing for running process(es) every %s second(s). Timeout=%s seconds.' "$sleep_interval" "$timeout")" -n "$log_lv"
        else
            break
        fi

        sleep $sleep_interval
        i=$((i + 1))
    done

    if [[ "$proc_found" == "true" ]]; then
        for p in "${proc_names[@]}"; do
            if [[ $last_param = type:pid ]]; then
                log -m "$(printf 'kill -SIGKILL "%s"' "$p")" -n "INFO"
				kill -SIGKILL "$p" # hard kill
    		else
                log -m "$(printf 'pkill -SIGKILL -i "%s"' "$p")" -n "INFO"
				pkill -SIGKILL -i "$p" # hard kill
    		fi
        done
    fi
    return 0
}


function hardkill_process() {
    local proc_names=( "$@" )
    local msg; local proc_found; local procs; local log_lv

    for p in "${proc_names[@]}"; do
        procs=$(pgrep -l -d "," -i "$p")
        if [[ -n "$procs" ]]; then
            log -m "$(printf 'found: "%s"' "$procs")" -n "$log_lv" -n "INFO"
            log -m "$(printf 'pkill -SIGKILL -i "%s"' "$p")" -n "INFO"
            pkill -SIGKILL -i "$p" # hard kill
        fi
    done
    return 0
}


function test_binary_arch() {
    local file_path="$1"
    local err_code=1; local msg

    log -m "$(printf 'params: file_path="%s"' "$1")" -n "DBG2"
    if [[ ! -f "$file_path" ]]; then
        msg=$(printf 'Setup binary file "%s" was not found after unpacking the downloaded ZIP. Exit code %s' "$file_path" "$err_code")
        echo "$msg" 1>&2; log -m "$msg" -n "ERR"
        return $err_code
    fi

    local mac_arch=$(arch);
    log -m "$(printf 'mac_arch="%s"' "$mac_arch")" -n "INFO"

    local file_arch=$(file "$file_path" | head -n 1)
    log -m "$(printf 'file_arch="%s"' "$file_arch")" -n "INFO"
    local test_universal=$(echo "$file_arch" | grep -i "universal")
    if [[ -n "$test_universal" ]]; then return 0; fi

    local test_file_arm64=$(file "$file_path" | grep -i "arm64")  # Apple silicon
    local test_file_x64=$(file "$file_path" | grep -i "x86_64")   # Intel CPU
    local test_failed=0
    log -m "$(printf 'arm64="%s", x86_64="%s"' "$test_file_arm64" "$test_file_x64")" -n "DBG"

    if [[ -z "$test_file_arm64" && -z "$test_file_x64" ]]; then
        msg=$(printf 'Unable to detect the application target architecture. Setup binary path: "%s". Exit code: %s' "$file_path" "$err_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $err_code
    fi

    # test x86_64 binary on arm64
    if [[ "$mac_arch" == "arm64" && -z "$test_file_arm64" ]]; then test_failed=1; fi

    # test arm64 binary on x86_64
    if [[ -z "$test_file_x64" && -n "$(echo "$mac_arch" | grep -E -i 'i386|x86_64')" ]]; then test_failed=1; fi

    if [[ $test_failed -eq 1 ]]; then
        msg=$(printf 'Application is not supported on this Mac. Exit code: %s' "$err_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $err_code
    fi
    return 0
}


function get_loglevel() {
    local level="$1"
    local lv=''
    case "$level" in
        "ERR") lv=1 ;;
        "WARN") lv=2 ;;
        "INFO") lv=3 ;;
        "DBG") lv=4 ;;
        "DBG2") lv=5 ;;
        *) lv=3 ;;
    esac
    echo $lv
    return 0
}


function log() {
    # -m "message"
    # -n "message level: DBG|ERR|WARN|INFO, Default=INFO

    local OPTIND
    local OPTSTRING="m:n:"
    local OPTERR=0
    local mesg_out
    # $action_log - global variable for full log output to stdout on script exit
    # log_level is a global variable

    while getopts ${OPTSTRING} opt; do
        case ${opt} in
            m) local mesg="${OPTARG}" ;;
            n) local msg_lev="${OPTARG}" ;;
        esac
    done

    [[ -z "$log_level" ]] && log_level="INFO"

    llevel=$(get_loglevel "$log_level")
    mlevel=$(get_loglevel "$msg_lev")

    if [[ $mlevel -le $llevel ]]; then
        local time=$(date "+%Y/%m/%d %H:%M:%S%z")
        mesg_out=$(printf '%s [%-4s]: %s(): %s\n' "$time" "$msg_lev" "${FUNCNAME[1]}" "$mesg")
        action1_log=$(printf '%s\n%s' "$action1_log" "$mesg_out")
    fi
    return 0
}


function log_started() {
    local script_name="$1"
    local script_opts="$2"
    local msg=$(printf 'bash %s %s' "$script_name" "$script_opts")
    log -m "$msg" -n "INFO"
    print_revision
    print_diskspace
}


function log_finished() {
    local script_name="$1"
    local ex_code=$2
    local msg=$(printf '"%s" script is finished. Exit code: %s.' "$script_name" "$ex_code")
    log -m "$msg" -n "INFO"
}


function validate_common_deploy_params() {
    local target_path="$1"
    local app_folder="$2"
    local deploy_mode="$3"
    local dest_folder="$4"

    msg=$(printf 'params: target_path="%s" app_folder="%s" deploy_mode="%s" dest_folder="%s"' "$target_path" "$app_folder" "$deploy_mode" "$dest_folder")
    log -m "$msg" -n "DBG2"

    # test the app folder name is specified. Required as a separate value for set_owner() f.e.
    if [[ -z "$app_folder" ]]; then
        msg=$(printf 'Application folder name was not specified.')
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $err_code
    fi

    # test the destination folder is exist
    if ! [[ -d "$dest_folder" ]]; then
        msg=$(printf 'Destination folder "%s" does not exist. Exit code %s' "$dest_folder" "$err_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $err_code
    fi

    if [[ -z "$app_folder" ]]; then
	msg=$(printf 'Target folder name was not specified for application update. Exit code: %s.' "-f" "$err_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $err_code
    fi
    return 0
}


function validate_pkg_deploy_params() {
    local pkg_file="$1"
    local choices_xml="$2"
    # local err_code=1

    log -m "$(printf 'params: pkg_file="%s" choices_xml="%s"' "$pkg_file" "$choices_xml")" -n "DBG2"

    # test the setup file exists
    if ! [[ -f "$pkg_file" ]]; then
        msg=$(printf 'Setup file "%s" does not exist. Exit code: %s' "$pkg_file" "$err_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $err_code
    fi

    [[ -z "$choices_xml" ]] && return 0

    # test the choices_xml file exists
    if ! [[ -f "$choices_xml" ]]; then
        msg=$(printf 'Choices xml file "%s" does not exist. Exit code: %s' "$choices_xml" "$err_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $err_code
    fi
   
    return 0
}


function validate_dmg_deploy_params() {
    local src_folder="$1"
    # local err_code=1

    log -m "$(printf 'params: src_folder="%s"' "$src_folder")" -n "DBG2"

    # test the setup file exists
    if [[ ! -d "$src_folder" ]]; then
        msg=$(printf 'Source folder "%s" does not exist. Exit code: %s' "$src_folder" "$err_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $err_code
    fi
    return 0
}


function deploy_pkg() {
    local pkg_file="$1"
    local target_path="$2"
    local app_folder="$3"
    local deploy_mode="$4"
    local choices_xml="$5"

    local err_code=1  # default error code
    local exit_code; local dest_folder

    msg=$(printf 'params: pkg_file="%s" target_path="%s" app_folder_name="%s" deploy_mode="%s" choices_xml="%s"' "$pkg_file" "$target_path" "$app_folder_name" "$deploy_mode" "$choices_xml")
    log -m "$msg" -n "DBG2"

    if [[ "$deploy_mode" == 'install' ]]; then
        dest_folder="$target_path"                              # example for install (deploy software): dest_folder="/Applications"
    else
        dest_folder="$target_path/$app_folder"                  # example for upgrade (deploy update): dest_folder="/Applications/Firefox.app"
    fi

    # validate params
    validate_pkg_deploy_params "$pkg_file" "$choices_xml" || return $?
    validate_common_deploy_params "$target_path" "$app_folder" "$deploy_mode" "$dest_folder" || return $?

    msg=$(printf 'software installation has been started.\nInstalling "%s" to "%s"' "$pkg_file" "$dest_folder")
    log -m "$msg" -n "INFO"
    
    local deploy_result
    if [[ -z "$choices_xml" ]]; then
        deploy_result=$(installer -pkg "$pkg_file" -target "$dest_folder" 2>&1)
        exit_code=$?
    else 
        deploy_result=$(installer -pkg "$pkg_file" -applyChoiceChangesXML "$choices_xml" -target "$dest_folder" 2>&1)
        exit_code=$?
    fi

    log -m "$deploy_result" -n "INFO"
    log -m "$exit_code" -n "DBG2"

    if [[ $exit_code -ne 0 ]]; then
        msg=$(printf 'Installation failed. Exit code: %s' "$exit_code")
        echo "$msg" >&2; log -m "$msg" -n "ERR"
        return $exit_code
    fi

    return $exit_code
}


function print_diskspace() {
    disksize_Kb=$(df -k / | awk 'NR==2 {print $2}')
    disksize_Gb=$(echo "scale=2; $disksize_Kb / 1024 / 1024" | bc)
    freespace_Kb=$(df -k / | awk 'NR==2 {print $4}')
    freespace_Gb=$(echo "scale=2; $freespace_Kb / 1024 / 1024" | bc)
    msg=$(printf '%s GB of %s GB disk space is currently free.\n' "${freespace_Gb}" "${disksize_Gb}")
    log -m "$msg" -n "INFO"
    return 0
}


function finally_dmg() {
    local dmg_folder="$1"
    local exit_code="$2"
    log -m 'finalizing deployment...' -n "INFO"
    detach_dmg "$dmg_folder"
    log_finished "$inv_script" "$exit_code"
    echo "$action1_log"   # send script log to the agent log file
    unset LC_NUMERIC
}


function finally_zip() {
    local exit_code="$1"
    log -m 'finalizing deployment...' -n "INFO"
     # local appf="$2"
     # rm -rf "./$appf"
     # msg=$(printf 'folder "%s" removed' "./$appf"); log -m "$msg" -n "DBG"
     # log -m "$msg" -n "INFO"
    log_finished "$inv_script" "$exit_code"
    echo "$action1_log"   # send script log to the agent log file
    unset LC_NUMERIC
}


function finally_pkg() {
    local exit_code="$1"
    log -m 'finalizing deployment...' -n "INFO"
    log_finished "$inv_script" "$exit_code"
    echo "$action1_log"  # send script log to the agent log file
    unset LC_NUMERIC
}