#!/bin/sh
# shellcheck enable=avoid-nullary-conditions,check-unassigned-uppercase

#__LICENSE_HERE__

#set -x

#__INNOEXTRACT_BINARY_START__
INNOEXTRACT_BINARY_B64=0
#__INNOEXTRACT_BINARY_END__

INSTALLER_VERSION="DEV"
REPO_PATH="https://github.com/ZOOM-Platform/zoom-platform.sh"
INNOEXT_BIN="/tmp/innoextract_zoom"
LAUNCH_SCRIPTS_PATH="$HOME"/.local/share/zoom-platform
UMU_BIN=umu-run

# Check if dialogs can be used and set tool
CAN_USE_DIALOGS=0
USE_ZENITY=1
(command -v kdialog >/dev/null || command -v zenity >/dev/null) && [ -n "$DISPLAY" ] && CAN_USE_DIALOGS=1
[ $CAN_USE_DIALOGS -eq 1 ] && ! command -v zenity >/dev/null && USE_ZENITY=0

# .shellcheck will consume ram trying to parse INNOEXTRACT_BINARY_B64
# when developing, just load the bin from working dir
get_innoext_string() {
    if [ $INSTALLER_VERSION = "DEV" ]; then
        printf '%s' "$(base64 -w 0 innoextract)"
    else
        printf '%s' "$INNOEXTRACT_BINARY_B64"
    fi
}

dialog_installer_select() {
    if [ $USE_ZENITY -eq 1 ]; then
        zenity --file-selection --title="Select a ZOOM Platform installer"
        return $?
    else
        kdialog --getopenfilename . "ZOOM Platform Windows installer (*.exe)" --title "Select a ZOOM Platform installer"
        return $?
    fi
}

dialog_install_dir_select() {
    if [ $USE_ZENITY -eq 1 ]; then
        zenity --file-selection --directory --title="Select an installation directory"
        return $?
    else
        kdialog --getexistingdirectory . --title "Select an installation directory"
        return $?
    fi
}

dialog_msgbox() {
    _type=$1
    _title=$2
    _msg=$3

    [ -z "$_title" ] && _title=""

    _param=''
    case $_type in
        "info") [ $USE_ZENITY -eq 1 ] && _param='info' || _param='msgbox' ;;
        "warning") [ $USE_ZENITY -eq 1 ] && _param='warning' || _param='sorry' ;;
        "error") _param='error' ;;
    esac

    if [ $USE_ZENITY -eq 1 ]; then
        zenity --no-wrap --$_param --text="$_msg" --title="$_title"
        return $?
    else
        kdialog --$_param "$_msg" --title "$_title"
        return $?
    fi
}

log_error() {
    printf "\033[31;1mERROR:\033[0m %s\n" "$*" >&2
}

# Shows an error dialog and an error message then exits
# $1: Error message
# $2: Msgbox title (optional)
fatal_error() {
    [ $CAN_USE_DIALOGS -eq 1 ] && dialog_msgbox error "$2" "$1"
    log_error "$1"
    exit 1
}

log_info() {
    printf "\033[33m[\033[35mzoom-platform.sh\033[33m]\033[0m: %s\n" "$*"
}

base64_dec() {
    _input="$1"
    if command -v base64 > /dev/null; then
        printf '%s' "$_input" | base64 -d 2>/dev/null || return 1
    elif command -v openssl > /dev/null; then
        printf '%s' "$_input" | openssl enc -d -base64 -A 2>/dev/null || return 1
    elif command -v python3 > /dev/null; then
        printf '%s' "$_input" | python3 -m base64 -d 2>/dev/null || return 1
    else
        return 1
    fi
}

validate_uuid() {
    _input="$1"
    _uuid_pattern="^[0-9a-fA-F]\{8\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{12\}$"
    expr "$_input" : "$_uuid_pattern" > /dev/null && return 0
    return 1
}

trim_string() {
    awk '{$1=$1;print}'
}

get_umu_id() {
    _guid="$1"
    _api_resp=$(curl -Ls -H "User-Agent: zoom-platform.sh/$INSTALLER_VERSION (+https://zoom-platform.sh/)" \
                    "https://umu.openwinecomponents.org/umu_api.php?store=zoomplatform&codename=$_guid")
    _api_exit=$?
    if [ $_api_exit -eq 0 ]; then
        _parsed_str="$(printf '%s' "$_api_resp" | awk -F'"umu_id":"' '{print substr($2, 1, index($2, "\"")-1)}')"
        # Validate parsed output
        case $_parsed_str in
            "umu-"*)
                printf '%s' "$_parsed_str"
                exit 0
                ;;
            *)
                exit 1
                ;;
        esac
    fi
    exit 1
}

get_desktop_value() {
    _key=$1
    _desktopfile=$2
    sed -n -e "/^$_key=/s/^$_key=//p" "$_desktopfile"
}

show_log_file_line() {
    _install_dir=$(printf '%s' "$2" | sed 's/\\/\\\\/g')
    _line=$(printf '%s' "$1" | sed -n "s/.*Dest filename: $_install_dir//p" | sed 's/^\\//;s/\\/\//g')
    printf "\r\e[K\033[33m[\033[35mzoom-platform.sh\033[33m]\033[0m: Extracting: %s" "$_line"
}

# Generate command to launch umu with
umu_launch_command() {
    if [ "$UMU_BIN" = "FLATPAK" ]; then
        # shellcheck disable=SC2016
        printf '%s' 'flatpak run --env=GAMEID="$GAMEID" --env=WINEPREFIX="$WINEPREFIX" --env=STORE="$STORE" org.openwinecomponents.umu.umu-launcher'
    else
        printf '%s' "$UMU_BIN"
    fi
}

umu_launch() {
    if [ "$UMU_BIN" = "FLATPAK" ]; then
        [ -z "$PROTON_VERB" ] && PROTON_VERB=waitforexitandrun
        flatpak run --env=GAMEID="$GAMEID" --env=WINEPREFIX="$WINEPREFIX" --env=PROTON_VERB="$PROTON_VERB" org.openwinecomponents.umu.umu-launcher "$@"
    else
        "$UMU_BIN" "$@"
    fi
}

# Check permissions for path or file
# Runs check from within the flatpak if umu flatpak is being used
test_file_perms() {
    _mode=$1 # r or w
    _target=$2

    case $_mode in
        "r" | "w") ;;
        *)
            fatal_error "Invalid test_file_perms pararm: $_mode. Must be r or w"
    esac

    if [ "$UMU_BIN" = "FLATPAK" ]; then
        flatpak run --command=sh org.openwinecomponents.umu.umu-launcher -c "test -$_mode \"$_target\""
        return $?
    else
        test -"$_mode" "$_target"
        return $?
    fi
}

# Loose check if dir is a wine prefix
is_valid_prefix() {
    _wine_prefix="$1"

    # Check if the directory exists
    [ ! -d "$_wine_prefix" ] && return 1

    # Check for some files and dirs
    _required_dirs="drive_c dosdevices"
    _required_files="system.reg user.reg"
    for dir in $_required_dirs; do
        [ ! -d "$_wine_prefix/$dir" ] && return 1
    done

    for f in $_required_files; do
        [ ! -f "$_wine_prefix/$f" ] && return 1
    done

    return 0
}

# Get values from the zoom keys in the registry
# Warning:
#   This is very loose query on purpose!
#   It'll return multi lines if more than 1 game is installed.
get_prefix_reg_val() {
    _wine_prefix="$1"
    _key="$2"
    _res="$(awk -v key="$_key" '
        BEGIN { in_section = 0; }
        {
            if ($0 ~ ("^\\[Software\\\\\\\\ZOOM PLATFORM\\\\\\\\")) {
                in_section = 1;
            } else if (in_section && match($0, "^\"" key "\"=")) {
                print $0;
            }
        }
    ' "$_wine_prefix/system.reg" | awk -F'"' '{print $4}')"

    printf '%s\n' "$_res" # the line break is required for while read
}

# Check if wine prefix has a specific zoom game installed
prefix_has_game() {
    _wine_prefix="$1"
    _guid="$2"

    # Check if the directory exists
    if ! is_valid_prefix "$_wine_prefix"; then
        return 1
    else
        _r=1
        _tmp=$(mktemp)
        get_prefix_reg_val "$_wine_prefix" "Site GUID" > "$_tmp"
        while read -r line; do
            # Validate the paths, stop on first success
            if [ "$line" = "$_guid" ]; then
                _r=0
                break
            fi
        done < "$_tmp"
        rm -f "$_tmp"
        return $_r
    fi
}

# Check if wine prefix has any zoom game installed
prefix_has_any_game() {
    _wine_prefix="$1"

    _r=1
    _tmp=$(mktemp)
    get_prefix_reg_val "$_wine_prefix" "InstallPath" > "$_tmp"

    # normally there should only be one game installed, but multiple is valid if dlc is installed
    while read -r line; do
        # Validate the paths, stop on first success
        if [ -d "$(PROTON_VERB=getnativepath umu_launch "$line")" ]; then
            _r=0
            break
        fi
    done < "$_tmp"
    rm -f "$_tmp"
    return $_r
}

_lnk_read_block() {
    _lnkpath=$1
    _offset=$2
    _length=$3
    od --endian=little -tdI -An -j "$_offset" -N "$_length" "$_lnkpath" | tr -d '\n '
}

_lnk_readstr_utf16() {
    _lnkpath=$1
    _offset=$2
    _length=$3
    _unicode=$4
    _result=''
    if [ "$_unicode" = 1 ]; then
        # stop at first \0 by getting offset and overriding _length
        _nul_offset=$(od -w2 -v -t x2 -Ad -j "$_offset" -N "$_length" "$_lnkpath" | awk '$2 == "0000" {print $1+0;exit}')
        [ -n "$_nul_offset" ] && _length=$((_nul_offset-_offset))

        _result=$(dd skip="$_offset" count="$_length" if="$_lnkpath" bs=1 status=none | iconv -f UTF-16LE -t UTF-8)
    else
        _result=$(od -S1 -An -j "$_offset" -N "$_length" "$_lnkpath")
    fi
    printf '%s' "$_result" | sed 's/\\/\\\\/g'
}

# Parse Windows .lnk for data
# Based on these documentation: 
# - https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/16cb4ca1-9339-4d0c-a68d-bf1d6cc0f943
# - https://github.com/libyal/liblnk/tree/main/documentation
parse_lnk() {
    _lnkpath="$1"

    # https://github.com/libyal/liblnk/blob/main/documentation/Windows%20Shortcut%20File%20(LNK)%20format.asciidoc#21-data-flags
    _flags_oct=$(od -An -j 20 -N 1 "$_lnkpath" | tr -d '\n ')
    _flags=$(printf '%s\n' "$_flags_oct" | dd status=none)

    # https://github.com/libyal/liblnk/blob/main/documentation/Windows%20Shortcut%20File%20(LNK)%20format.asciidoc#3-link-target-identifier
    _itemlist_count=$(_lnk_read_block "$_lnkpath" 76 2)

    # LinkInfo
    # https://github.com/libyal/liblnk/blob/main/documentation/Windows%20Shortcut%20File%20(LNK)%20format.asciidoc#4-location-information
    _location_offset=$((_itemlist_count+78)) # skip guid
    _link_info_length=$(_lnk_read_block "$_lnkpath" $_location_offset 4)            # LinkInfoSize
    _link_info_header_size=$(_lnk_read_block "$_lnkpath" $((_location_offset+4)) 4) # LinkInfoHeaderSize
    _link_info_flags=$(_lnk_read_block "$_lnkpath" $((_location_offset+8)) 4)       # LinkInfoFlags
    _basepath_offset=$(_lnk_read_block "$_lnkpath" $((_location_offset+16)) 4)      # LocalBasePathOffset

    _basepath_is_unicode=0
    # Use unicode offset instead
    if [ "$_link_info_header_size" -gt 28 ]; then
        _basepath_offset=$(_lnk_read_block "$_lnkpath" $((_location_offset+28)) 4) # LocalBasePathOffsetUnicode
        _basepath_is_unicode=1
    fi

    _localpath_offset=$((_location_offset+_basepath_offset))
    _localpath_end=$((_location_offset+_link_info_length))
    _localpath_length=$((_localpath_end-_localpath_offset))

    _localpath=$(_lnk_readstr_utf16 "$_lnkpath" $_localpath_offset $_localpath_length $_basepath_is_unicode) # LocalBasePath or LocalBasePathUnicode

    printf 'LocalBasePath:%s\n' "$_localpath"

    # StringData
    # STRING_DATA = [NAME_STRING] [RELATIVE_PATH] [WORKING_DIR] [COMMAND_LINE_ARGUMENTS] [ICON_LOCATION]
    # https://github.com/libyal/liblnk/blob/main/documentation/Windows%20Shortcut%20File%20(LNK)%20format.asciidoc#5-data-strings
    
    _stringdata_is_unicode=0
    # IsUnicode
    [ "$((_flags & 0x00000080))" -ne 0 ] && _stringdata_is_unicode=1

    _stringdata_offset=$_localpath_end
    # HasName HasRelativePath HasWorkingDir HasArguments HasIconLocation
    for i in 0x00000004 0x00000008 0x00000010 0x00000020 0x00000040 ; do
        if [ "$((_flags & i))" -ne 0 ]; then
            _stringdata_length=$(_lnk_read_block "$_lnkpath" "$_stringdata_offset" 2) # CountCharacters
            [ "$_stringdata_is_unicode" = 1 ] && _stringdata_length=$((_stringdata_length*2))

            _stringdata_value=''
            [ "$_stringdata_length" -gt 0 ] && \
                _stringdata_value="$(_lnk_readstr_utf16 "$_lnkpath" $((_stringdata_offset+2)) "$_stringdata_length" "$_stringdata_is_unicode")"

            _stringdata_offset=$((_stringdata_offset+_stringdata_length))
            [ $_stringdata_is_unicode = 1 ] && _stringdata_offset=$((_stringdata_offset+2))

            if [ -n "$_stringdata_value" ]; then
                case "$i" in
                    0x00000004) printf 'NAME_STRING:';;
                    0x00000008) printf 'RELATIVE_PATH:';;
                    0x00000010) printf 'WORKING_DIR:';;
                    0x00000020) printf 'COMMAND_LINE_ARGUMENTS:';;
                    0x00000040) printf 'ICON_LOCATION:';;
                esac
                printf '%s\n' "$_stringdata_value"
            fi
        fi
    done
}

show_usage() {
    printf 'Usage: zoom-platform.sh [OPTIONS] INSTALLER DEST

Description:
  zoom-platform.sh - Install Windows games from ZOOM Platform using umu and Proton.

Options:
  -h, --help           Display this help message and exit.
  -v, --version        Display the version information and exit.
  -i, --installer      Path to a ZOOM Platform installer .exe.
  -d, --dest           Path to where you want the game to install to.
  -o, --output         Alias for -d.

Arguments:
  INSTALLER            Path to a ZOOM Platform installer .exe.
  DEST                 Path to where you want the game to install to.

Examples:
  zoom-platform.sh "Game-English-Setup-1.33.7.exe" ~/Games/new_game_dir
  zoom-platform.sh -i "Game-English-Setup-1.33.7.exe" -d ~/Games/new_game_dir

Note:
  - INSTALLER and DEST are optional if your environment can use KDialog or Zenity.
  - When the -i or -d options are used, they take priority over the arguments.
  - If updating a game or installing DLC, DEST should be the same path that the
    base game was installed in.
  - If you tick "Create a desktop shortcut" during setup, Desktop entries will be
    placed in: %s

Source & issues: %s
' "$(xdg-user-dir DESKTOP)" "$REPO_PATH"
}

INPUT_INSTALLER=""
INSTALL_PATH=""

options=$(getopt -o hvi:d:o: --long help,version,installer:,dest:,output: -n 'zoom-platform.sh' -- "$@")

eval set -- "$options"

while true; do
  case "$1" in
    -h | --help )
        show_usage
        exit 0
        ;;
    -v | --version )
        printf '%s\n' $INSTALLER_VERSION
        exit 0
        ;;
    -i | --installer )
        INPUT_INSTALLER="$2" 
        shift 2
        ;;
    -d | --dest | -o | --output )
        INSTALL_PATH="$2"
        shift 2
        ;;
    --) shift; break ;;
    *)
        fatal_error "Invalid option: $1"
    ;;
  esac
done

[ -z "$INPUT_INSTALLER" ] && INPUT_INSTALLER=$1

[ -z "$INSTALL_PATH" ] && INSTALL_PATH=$2

# Unpack innoextract into tmp
base64_dec "$(get_innoext_string)" > $INNOEXT_BIN
PAYLOAD_DECODED_STATUS=$?
[ $PAYLOAD_DECODED_STATUS -ne 0 ] && fatal_error "Could not decode base64." "Error unpacking innoextract"
if [ -s "$INNOEXT_BIN" ]; then
    # Make it executable and test it
    chmod +x $INNOEXT_BIN
    $INNOEXT_BIN --version > /dev/null 2>&1 || fatal_error "Cannot launch $INNOEXT_BIN"
else
    fatal_error "Could not decode base64." "Error unpacking innoextract"
fi

# Check if UWU is installed
if command -v umu-run > /dev/null; then
    UMU_BIN=umu-run
elif command -v "$HOME"/.local/share/umu/umu-run > /dev/null; then
    UMU_BIN="$HOME"/.local/share/umu/umu-run
elif command -v /usr/bin/umu-run > /dev/null; then
    UMU_BIN=/usr/bin/umu-run
elif flatpak info org.openwinecomponents.umu.umu-launcher >/dev/null 2>&1; then
    UMU_BIN="FLATPAK"
    log_info "Using umu Flatpak"
else
    fatal_error "umu is not installed"
fi

# If dialogs are usable and installer wasn't specified, show a dialog
if [ $CAN_USE_DIALOGS -eq 1 ] && [ -z "$INPUT_INSTALLER" ]; then
    INPUT_INSTALLER=$(dialog_installer_select)
    case $? in
        0)
            log_info "Selected \"$INPUT_INSTALLER\"";;
        1)
            fatal_error "No installer chosen.";;
        *)
            fatal_error "An unexpected error occurred when trying to choose an installer.";;
    esac
fi

# Show usage if can't use dialogs and no paths passed
if [ $CAN_USE_DIALOGS -eq 0 ]; then
    if [ -z "$INPUT_INSTALLER" ] || [ -z "$INSTALL_PATH" ]; then
        log_error "Cannot use dialogs, please specify INSTALLER and DEST."
        show_usage
        exit 1
    fi
fi

# Show an error if can't read installer
if ! test_file_perms r "$INPUT_INSTALLER" ; then
    _msg="Installer either does not exist or $([ "$UMU_BIN" = "FLATPAK" ] && printf "umu Flatpak does not have" || printf "no") read permissions."
    fatal_error "$_msg"
fi

# Validate and get some info from installer
ZOOM_GUID=$($INNOEXT_BIN -s --zoom-game-id "$INPUT_INSTALLER" 2> /dev/null | trim_string)
ZOOM_GUID_EXIT=$?
# GUID can be wrong for very old installers, make sure it's a valid string
if [ $ZOOM_GUID_EXIT -gt 0 ] || ! validate_uuid "$ZOOM_GUID"; then
    fatal_error "This doesn't seem to be a ZOOM Platform installer.
If you think this is an error, please submit a bug report:
$REPO_PATH/issues" "Invalid ZOOM Platform Installer"
fi

INSTALLER_INFO=$($INNOEXT_BIN -s --print-headers "$INPUT_INSTALLER")
get_header_val () {
    printf '%s' "$INSTALLER_INFO" | sed -n "s/$1: \"\(.*\)\"/\1/p; s/$1: \(.*\)/\1/p" # Handles with and without quotes
}

INNO_APPID=$(get_header_val 'app_id' | sed 's/[{}]//g') # Strip {{}

# Check if installer is for DLC
IS_DLC=0
[ "$(get_header_val 'default_dir_name')" = "{code:GetInstallationPath}" ] && IS_DLC=1

# Show installer info
printf "
Title: \033[32;1m%s\033[0m 
Publisher: \033[39;49;1m%s\033[0m
ZOOM Platform Version: \033[39;49;1m%s\033[0m
ZOOM Platform UUID: \033[39;49;1m%s\033[0m
IS DLC: \033[39;49;1m%s\033[0m
\n" \
"$(get_header_val 'app_name')" \
"$(get_header_val 'app_publisher')" \
"$(get_header_val 'app_version')" \
"$ZOOM_GUID" \
"$([ "$IS_DLC" -eq 1 ] && printf "yes" || printf "no")"

# Open file selector if DEST wasn't given
if [ -z "$INSTALL_PATH" ]; then
    if [ $CAN_USE_DIALOGS -eq 1 ]; then
        # If DLC, ask user to select prefix where base game was installed
        if [ $IS_DLC -eq 1 ]; then
            dialog_msgbox info "DLC Installer Chosen" \
                "$(get_header_val 'app_name')\n\nSelect the same directory you chose when you installed the base game in the next prompt."
        fi

        printf "Select an installation directory\n"
        INSTALL_PATH=$(dialog_install_dir_select)
        case $? in
            0)
                log_info "Selected \"$INSTALL_PATH\"";;
            1)
                fatal_error "No install directory chosen.";;
            *)
                fatal_error "An unexpected error has occurred.";;
        esac
    else
        show_usage
        fatal_error 'No install directory specified'
    fi
fi

# Show an error if install destination isn't writable, only do this for the Flatpak
if [ "$UMU_BIN" = "FLATPAK" ] && ! test_file_perms w "$INSTALL_PATH"; then
    _msg="The umu Flatpak does not have write permissions to the install directory."
    if [ $CAN_USE_DIALOGS -eq 1 ]; then
        dialog_msgbox error "No permissions" "$_msg\n$INSTALL_PATH"
        exit 1
    else
        fatal_error "$_msg"
    fi
fi

export WINEPREFIX="$INSTALL_PATH"
export GAMEID="zoominstall"

# Safety checks to save users from themselves
# - Don't allow dirs that are NOT empty
# - Don't let user choose existing prefix
# - Allow existing prefix only if it's updating the same game OR installing DLC
# If DLC, must be a wine prefix and a zoom game needs to exist already
# Only checking existence, let the DLC installer itself run checks to see if it's the right game or not
if is_valid_prefix "$INSTALL_PATH"; then
    # Same game is installed on this prefix, must be updating or reinstalling
    if prefix_has_game "$INSTALL_PATH" "$ZOOM_GUID"; then
        log_info "Detected the same game installed in this prefix! [$ZOOM_GUID]"
    else
        if prefix_has_any_game "$INSTALL_PATH"; then
            # Don't let user put different games in a prefix
            if [ $IS_DLC -eq 0 ]; then
                fatal_error "Invalid install directory. A different game is already installed here."
            fi
        else
            # Dont allow installing DLC if no other game is here
            if [ $IS_DLC -eq 1 ]; then
                fatal_error "Invalid install directory. When installing DLC, choose the directory you installed the base game in."
            fi
        fi
    fi
# must be empty or not exist
elif [ -d "$INSTALL_PATH" ] && [ -n "$(ls -A "$INSTALL_PATH")" ]; then
    fatal_error "Install directory must either be empty or an existing wine prefix if updating a game."
fi

# Write Inno inf to C drive
# This hides some stuff the user shouldn't change
mkdir -p "$INSTALL_PATH/drive_c"
cat >"$INSTALL_PATH/drive_c/zoom_installer.inf" <<EOL
[Setup]
Lang=english
Tasks=desktopicon
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
EOL

# These reg values need to preexist in the registry before the installer
# runs to skip the option to change the directory and remove windows shortcuts.

# DLC's don't need this since main game should already be installed.
# Also don't need to do this if game is already installed
if [ $IS_DLC -eq 0 ] && ! prefix_has_game "$INSTALL_PATH" "$ZOOM_GUID"; then
    cat >"$INSTALL_PATH/drive_c/zoom_regkeys.bat" <<EOL
@echo off
REM We do a check cause we don't want to overwrite in case of an update that changes the default installation directory.
reg query "HKLM\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{$INNO_APPID}_is1" >nul
if %errorlevel% neq 0 (
    reg add "HKLM\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{$INNO_APPID}_is1" /v "Inno Setup: Icon Group" /t REG_SZ /d "$(get_header_val 'default_group_name')"
    reg add "HKLM\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{$INNO_APPID}_is1" /v "Inno Setup: App Path" /t REG_SZ /d "$(get_header_val 'default_dir_name')"
)
EOL

    log_info "Creating installer reg keys..."
    umu_launch start "C:\\zoom_regkeys.bat"
fi

printf "\n" > "$INSTALL_PATH/drive_c/zoom_installer.log"

# If installer doesn't have custom components then it can be installed silently
# Disabling for now, need to figure out how to reliably check this
VERYSILENT=0
# [ -z "$(get_header_val 'component_count')" ] || [ "$(get_header_val 'component_count')" -eq 0 ] && VERYSILENT=1

# Launch installer in a subprocess
# Only important stuff like the EULA and configurable items should show.
# "/ZOOMINSTALLERGUID=" is only used so we can easily find the process with pkill -f
log_info "Launching installer..."
umu_launch "$INPUT_INSTALLER" \
    /NORESTART \
    /SP- \
    /LOADINF=C:\\zoom_installer.inf \
    /LOG=C:\\zoom_installer.log \
    /ZOOMINSTALLERGUID="$ZOOM_GUID" \
    "$([ "$VERYSILENT" -eq 1 ] && printf "/VERYSILENT")" &

# Watch the install log
_currentfile=0
_filecount=$(("$(get_header_val 'file_count')"+"$(get_header_val 'icon_count')"))
_readlog=1
while [ $_readlog -eq 1 ]; do
    sleep 0.010
    while read -r line || [ -n "$line" ]; do
        case $line in
            *"Dest filename: "*)
                # show_log_file_line "$line" "$(get_header_val 'default_dir_name')" # too slow
                _currentfile=$((_currentfile+1))
                printf "\r\e[K\033[33m[\033[35mzoom-platform.sh\033[33m]\033[0m: Extracting: %d/%d" $_currentfile $_filecount
            ;;
            *"Exception message"* | *"Got EAbort exception"*)
                _readlog=0
                fatal_error "Unknown installation error occured."
                ;;
        esac

        # Handle killing process based on if silent install chosen
        if [ "$VERYSILENT" -eq 1 ]; then
            case $line in
                *"Log closed."*)
                    printf "\n"
                    log_info "Installer finished!"
                    _readlog=0
                    ;;
            esac
        else
            case $line in
                *"Need to restart Windows?"*) # User shouldn't launch the game through the option supplied by Inno, kill installer asap
                    printf "\n\r"
                    log_info "Installer finished! Force closing."
                    printf "\r"
                    pkill -f "/ZOOMINSTALLERGUID=$ZOOM_GUID"
                    printf "\r"
                    _readlog=0
                    ;;
                *"Log closed."*) # Shouldn't be able to get to this point if killed by above
                    _readlog=0
                    printf "\n\r"
                    pkill -f "/ZOOMINSTALLERGUID=$ZOOM_GUID"
                    printf "\r"
                    fatal_error "Installer failed or canceled."
                    ;;
            esac
        fi
    done
done < "$INSTALL_PATH/drive_c/zoom_installer.log"

# Query API for UMU ID
UMU_ID="$(get_umu_id "$ZOOM_GUID")"
UMU_ID_EXIT=$?
[ $UMU_ID_EXIT -gt 0 ] && UMU_ID="0"


CREATE_DESKTOP_ENTRIES=1
if ! command -v desktop-file-install > /dev/null; then
    log_error "desktop-file-install is not available. Skipping desktop entry creation."
    CREATE_DESKTOP_ENTRIES=0
fi

# Create shortcuts using the shortcuts and icons in C:\proton_shortcuts\
# https://github.com/ValveSoftware/wine/commit/0a02c50a20ddc8f4a4c540c43a8b8a686023d422
# https://github.com/ValveSoftware/wine/commit/d0109f6ce75e13a4972371d7ef5819d2614c6d61
# https://github.com/ValveSoftware/wine/commit/7c040c3c0f837278e2ef3bb55fc9770f61444b36
GAME_NAME_SAFE=$(get_header_val 'default_group_name')
PROTON_SHORTCUTS_PATH="$INSTALL_PATH/drive_c/proton_shortcuts"
APPLICATIONS_PATH="$HOME/.local/share/applications/zoom-platform/$GAME_NAME_SAFE"
ZOOM_SHORTCUTS_PATH="$INSTALL_PATH/drive_c/zoom_shortcuts"
log_info "Creating desktop entries..."
mkdir -p "$ZOOM_SHORTCUTS_PATH"
sleep 2 # should be enough time for wine to create shortcuts
for file in "$PROTON_SHORTCUTS_PATH"/*.desktop; do
    [ ! -f "$file" ] && continue # safety check if .desktop exists

    _filename=$(basename "$file" ".desktop")
    # Get some values from the .desktop
    _name="$(get_desktop_value "Name" "$file")"
    _lnkpathwin="$(get_desktop_value "Exec" "$file")"
    _wmclass="$(get_desktop_value "StartupWMClass" "$file")"
    _iconname="$(get_desktop_value "Icon" "$file")"

    # Skip certain shortcuts
    case $_wmclass in
        # Skip uninstaller and PDFs
        "unins000.exe" | *".pdf")
            continue
            ;;
        # Skip HTML manuals
        *".html" | *".htm")
            case $_name in
                *"Manual"*)
                    continue
                    ;;
            esac
            ;;
    esac

    # Unescape windows path
    _lnkpathlinux=$(PROTON_VERB=getnativepath umu_launch "$(printf '%s' "$_lnkpathwin" | sed 's/\\\\/\\/g; s/\\ / /g; s/\\\([^\\]\)/\1/g')" 2> /dev/null)
    # Get values from .lnk
    _lnk="$(parse_lnk "$_lnkpathlinux")"
    _lnk_exe=$(printf '%s' "$_lnk" | sed -n 's/LocalBasePath://p')
    _lnk_workingdir=$(printf '%s' "$_lnk" | sed -n 's/WORKING_DIR://p')
    _lnk_args=$(printf '%s' "$_lnk" | sed -n 's/COMMAND_LINE_ARGUMENTS://p')

    # Get absolute path to largest icon
    _iconpath="$PROTON_SHORTCUTS_PATH/icons/$(find "$PROTON_SHORTCUTS_PATH/icons" -type f -name "*$_iconname.png" -printf '%P\n' | sort -n -tx -k1 -r | head -n 1)"

    cat >"$ZOOM_SHORTCUTS_PATH/$_filename.sh" <<EOL
#!/bin/sh
export GAMEID="$UMU_ID"
export WINEPREFIX="$INSTALL_PATH"
export STORE="zoomplatform"
$(umu_launch_command) start /b /d "$_lnk_workingdir" "$_lnk_exe" $_lnk_args
EOL
    chmod +x "$ZOOM_SHORTCUTS_PATH/$_filename.sh"

    # Desktop entries do not play well with special characters, and each distro handles them
    # different enough to be annoyingly problematic.
    # So we create a script in a location with no special characters (hopefully) that launches umu.
    if [ $CREATE_DESKTOP_ENTRIES -eq 1 ]; then
        _zoomdesktopfile="$ZOOM_SHORTCUTS_PATH/$_filename.desktop"
        _fsum=$(printf '%s' "$_filename" | cksum | cut -d ' ' -f1)

        # Place script in $XDG_DATA_HOME/zoom-platform/
        mkdir -p "$LAUNCH_SCRIPTS_PATH/$ZOOM_GUID/"
        ln -sf "$ZOOM_SHORTCUTS_PATH/$_filename.sh" "$LAUNCH_SCRIPTS_PATH/$ZOOM_GUID/$_fsum.sh"

        # Now create .desktop and point to script
        cat >"$_zoomdesktopfile" <<EOL
[Desktop Entry]
Name=$_name
Exec=$LAUNCH_SCRIPTS_PATH/$ZOOM_GUID/$_fsum.sh
Icon=$_iconpath
StartupWMClass=$_wmclass
Terminal=false
Type=Application
Categories=Game
X-KDE-RunOnDiscreteGpu=true
EOL
        log_info "Creating \"$APPLICATIONS_PATH/$_name.desktop\""
        desktop-file-install --delete-original --dir="$APPLICATIONS_PATH" "$_zoomdesktopfile"
        chmod +x "$APPLICATIONS_PATH/$_name.desktop"
    fi
done

# If user chose to create Desktop shortcuts in the installer, symlink to XDG desktop
# Shortcut names placed on the Desktop are always the same as what was made in the Start Menu
if [ $CREATE_DESKTOP_ENTRIES -eq 1 ]; then
    for file in "$INSTALL_PATH/drive_c/users/Public/Desktop"/*.lnk; do
        _filename=$(basename "$file" ".lnk")
        _existingdesktoppath="$APPLICATIONS_PATH/$_filename.desktop"
        if [ -f "$_existingdesktoppath" ] && [ -f "$file" ]; then
            log_info "Creating \"$(xdg-user-dir DESKTOP)/$_filename.desktop\""
            ln -sf "$_existingdesktoppath" "$(xdg-user-dir DESKTOP)/$_filename.desktop"
        fi
    done
    printf "\n"
    log_info "Installation complete! You can now launch your games from the applications launcher."
    log_info "To add to your Steam library, from within Steam go to \"Games\" -> \"Add a Non-Steam Game to My Library\" then select it from the popup."
else
    printf "\n"
    log_info "Installation complete! Desktop entry creation was skipped, the launch scripts are in \"$ZOOM_SHORTCUTS_PATH\""
fi
