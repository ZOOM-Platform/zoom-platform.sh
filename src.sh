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
ULWGL_BIN=ulwgl-run

CAN_USE_DIALOGS=0
USE_ZENITY=1
(kdialog --version >/dev/null 2>&1 || zenity --version >/dev/null 2>&1) && [ -n "$DISPLAY" ] && CAN_USE_DIALOGS=1

if [ $CAN_USE_DIALOGS -eq 1 ] && ! zenity --version >/dev/null 2>&1; then USE_ZENITY=0; fi

# .shellcheck will consume ram trying to parse INNOEXTRACT_BINARY_B64
# when working developing, just load the bin from working dir
get_innoext_string() {
    if [ $INSTALLER_VERSION = "DEV" ]; then
        printf '%s' "$(base64 -w 0 innoextract)"
    else
        printf '%s' "$INNOEXTRACT_BINARY_B64"
    fi
}

fatal_error_no_exit() {
    printf "\033[31;1mERROR:\033[0m %s\n" "$*" >&2
}

fatal_error() {
    fatal_error_no_exit "$*"
    exit 1
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
    if expr "$_input" : "$_uuid_pattern" > /dev/null; then
        return 0
    fi
    return 1
}

trim_string() {
    awk '{$1=$1;print}'
}

get_desktop_value() {
    _key=$1
    _desktopfile=$2
    sed -n -e "/^$_key=/s/^$_key=//p" "$_desktopfile"
}

show_log_file_line() {
    _install_dir=$(printf '%s' "$2" | sed 's/\\/\\\\/g')
    _line=$(printf '%s' "$1" | sed -n "s/.*Dest filename: $_install_dir//p" | sed 's/^\\//;s/\\/\//g')
    printf "\r\e[KExtracting file: %s" "$_line"
}

dialog_installer_select() {
    if [ $USE_ZENITY -eq 1 ]; then
        zenity --file-selection --title="Select a ZOOM Platform installer"
        return $?
    else
        kdialog --getopenfilename . "ZOOM Platform installer (*.exe)" --title "Select a ZOOM Platform installer"
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

dialog_infobox() {
    _title=$1
    _msg=$2
    if [ $USE_ZENITY -eq 1 ]; then
        zenity --info --text="$_msg" --title="$_title"
        return $?
    else
        kdialog --msgbox "$_msg" --title "$_title"
        return $?
    fi
}

# Loose check if dir is a wine prefix
is_valid_prefix() {
    _wine_prefix="$1"

    # Check if the directory exists
    if [ ! -d "$_wine_prefix" ]; then return 1; fi

    # Check for some files and dirs
    _required_dirs="drive_c dosdevices"
    _required_files="system.reg user.reg"
    for dir in $_required_dirs; do
        if [ ! -d "$_wine_prefix/$dir" ]; then return 1; fi
    done

    for f in $_required_files; do
        if [ ! -f "$_wine_prefix/$f" ]; then return 1; fi
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

    printf '%s\n' "$_res" # the new line is required for while read
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
        if [ -d "$(PROTON_VERB=getnativepath "$ULWGL_BIN" "$line")" ]; then
            _r=0
            break
        fi
    done < "$_tmp"
    rm -f "$_tmp"
    return $_r
}

show_usage() {
    printf 'Usage: zoom-platform.sh [OPTIONS] INSTALLER DEST

Description:
  zoom-platform.sh - Install Windows games from ZOOM Platform using ULWGL and Proton.

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

Source & issues: %s
' "$REPO_PATH"
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

if [ -z "$INPUT_INSTALLER" ]; then
    INPUT_INSTALLER=$1
fi

if [ -z "$INSTALL_PATH" ]; then
    INSTALL_PATH=$2
fi

# Unpack innoextract into tmp
base64_dec "$(get_innoext_string)" > $INNOEXT_BIN
PAYLOAD_DECODED_STATUS=$?
if [ $PAYLOAD_DECODED_STATUS -ne 0 ]; then fatal_error "Could not decode base64."; fi
if [ -s "$INNOEXT_BIN" ]; then
    # Make it executable and test it
    chmod +x $INNOEXT_BIN
    $INNOEXT_BIN --version > /dev/null 2>&1 || fatal_error "Cannot launch $INNOEXT_BIN"
else
    fatal_error "Could not decode base64."
fi

# Check if ULWGL is installed
# TODO: Flatpak
if command -v ulwgl-run 2> /dev/null; then
    ULWGL_BIN=ulwgl-run
elif [ -f "$HOME/.local/share/ULWGL/ulwgl-run" ]; then
    ULWGL_BIN="$HOME/.local/share/ULWGL/ulwgl-run"
elif [ -f "/usr/bin/ulwgl-run" ]; then
    ULWGL_BIN="/usr/bin/ulwgl-run"
else
    fatal_error "ULWGL is not installed"
fi

# If dialogs are usable and installer wasn't specified, show a dialog
if [ $CAN_USE_DIALOGS -eq 1 ] && [ -z "$INPUT_INSTALLER" ]; then
    INPUT_INSTALLER=$(dialog_installer_select)
    case $? in
        0)
            printf '"%s" selected.\n' "$INPUT_INSTALLER";;
        1)
            fatal_error "No installer chosen.";;
        *)
            fatal_error "An unexpected error occurred when trying to choose an installer.";;
    esac
fi

# Show usage if can't use dialogs and no paths passed
if [ $CAN_USE_DIALOGS -eq 0 ]; then
    if [ -z "$INPUT_INSTALLER" ] || [ -z "$INSTALL_PATH" ]; then
        fatal_error_no_exit "Cannot use dialogs, please specify INSTALLER and DEST."
        show_usage
        exit 1
    fi
fi

# Validate and get some info from installer
ZOOM_GUID=$($INNOEXT_BIN -s --zoom-game-id "$INPUT_INSTALLER" 2> /dev/null | trim_string)
ZOOM_GUID_EXIT=$?
# GUID can be wrong for very old installers, make sure it's a valid string
if [ $ZOOM_GUID_EXIT -gt 0 ] || ! validate_uuid "$ZOOM_GUID"; then
   fatal_error "This doesn't seem to be a ZOOM Platform installer.
If you think this is an error, please submit a bug report:
$REPO_PATH"
fi

INSTALLER_INFO=$($INNOEXT_BIN -s --print-headers "$INPUT_INSTALLER")
get_header_val () {
    printf '%s' "$INSTALLER_INFO" | sed -n "s/$1: \"\(.*\)\"/\1/p; s/$1: \(.*\)/\1/p" # Handles with and without quotes
}

INNO_APPID=$(get_header_val 'app_id' | sed 's/[{}]//g') # Strip {{}

# Check if installer is for DLC
IS_DLC=0
if [ "$(get_header_val 'default_dir_name')" = "{code:GetInstallationPath}" ]; then IS_DLC=1; fi

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
            dialog_infobox "DLC Installer Chosen" \
                "$(get_header_val 'app_name')\n\nSelect the same directory you chose when you installed the base game in the next prompt."
        fi

        printf "Select an installation directory\n"
        INSTALL_PATH=$(dialog_install_dir_select)
        case $? in
            0)
                printf '"%s" selected.\n' "$INSTALL_PATH";;
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
        printf "Same game installed on this prefix!\n"
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

    "$ULWGL_BIN" start "C:\\zoom_regkeys.bat"
fi

printf '\n' > "$INSTALL_PATH/drive_c/zoom_installer.log"

# If installer doesn't have custom components then it can be installed silently
# Disabling for now, need to figure out how to reliably check this
VERYSILENT=0
# if [ -z "$(get_header_val 'component_count')" ] || [ "$(get_header_val 'component_count')" -eq 0 ]; then VERYSILENT=1; fi

# Launch installer in a subprocess
# Only important stuff like the EULA and configurable items should show.
"$ULWGL_BIN" "$INPUT_INSTALLER" \
    /NORESTART \
    /SP- \
    /LOADINF=C:\\zoom_installer.inf \
    /LOG=C:\\zoom_installer.log \
    "$([ "$VERYSILENT" -eq 1 ] && printf "/VERYSILENT")" &

# Watch the install log
INSTALLER_FILENAME=$(basename "$INPUT_INSTALLER")

_readlog=1
while [ $_readlog -eq 1 ]; do
    while read -r line || [ -n "$line" ]; do
        if [ "$VERYSILENT" -eq 1 ]; then
            case $line in
                *"Dest filename: "*)
                    show_log_file_line "$line" "$(get_header_val 'default_dir_name')"
                    ;;
                *"Log closed."*)
                    printf "\nInstallation complete!\n"
                    _readlog=0
                    ;;
            esac
        else
            case $line in
                *"Dest filename: "*)
                    show_log_file_line "$line" "$(get_header_val 'default_dir_name')"
                    ;;
                *"Installation process succeeded."*) # User shouldn't launch the game through the option supplied by Inno, kill installer asap
                    printf '\nInstallation completed! Force closing installer.\n'
                    PROTON_VERB=runinprefix "$ULWGL_BIN" taskkill /IM "$INSTALLER_FILENAME" /T /F >/dev/null 2>&1
                    _readlog=0
                    ;;
                *"Log closed."*) # Shouldn't be able to get to this point if killed by above
                    _readlog=0
                    fatal_error "Installation failed or canceled."
                    ;;
            esac
        fi
        case $line in
            *"Exception message"* | *"Got EAbort exception"*)
                _readlog=0
                fatal_error "Unknown installation error occured."
                ;;
        esac
    done
done < "$INSTALL_PATH/drive_c/zoom_installer.log"

# Create shortcuts using the shortcuts and icons in C:\proton_shortcuts\
# https://github.com/ValveSoftware/wine/commit/0a02c50a20ddc8f4a4c540c43a8b8a686023d422
# https://github.com/ValveSoftware/wine/commit/d0109f6ce75e13a4972371d7ef5819d2614c6d61
# https://github.com/ValveSoftware/wine/commit/7c040c3c0f837278e2ef3bb55fc9770f61444b36
PROTON_SHORTCUTS_PATH="$INSTALL_PATH/drive_c/proton_shortcuts/"
mkdir -p "$INSTALL_PATH/drive_c/zoom_shortcuts/" # temp dir
for file in "$PROTON_SHORTCUTS_PATH"/*.desktop; do
    _filename=$(basename "$file")
    case $_filename in
        "Uninstall "*)
            ;;
        *)
            _zoomdesktopfile="$INSTALL_PATH/drive_c/zoom_shortcuts/$_filename"

            # Get some values from the .desktop
            _name="$(get_desktop_value "Name" "$file")"
            _lnkpathwin="$(get_desktop_value "Exec" "$file")"
            _wmclass="$(get_desktop_value "StartupWMClass" "$file")"
            _iconname="$(get_desktop_value "Icon" "$file")"

            # Win -> Linux path
            _lnkpathlinux=$(PROTON_VERB=getnativepath "$ULWGL_BIN" "$(printf '%s' "$_lnkpathwin" | sed 's/\\\\/\\/g; s/\\ / /g')" 2> /dev/null)
            # Get absolute path to largest icon
            _iconpath="$PROTON_SHORTCUTS_PATH/icons/$(find "$PROTON_SHORTCUTS_PATH/icons" -type f -name "*$_iconname.png" -printf '%P\n' | sort -n -tx -k1 -r | head -n 1)"
            cat >"$_zoomdesktopfile" <<EOL
[Desktop Entry]
Name=$_name
Exec=/bin/sh -c "WINEPREFIX='$INSTALL_PATH' GAMEID='ulwgl-$ZOOM_GUID' '$ULWGL_BIN' '$_lnkpathlinux'"
Icon=$_iconpath
StartupWMClass=$_wmclass
Terminal=false
Type=Application
Categories=Game
X-KDE-RunOnDiscreteGpu=true
EOL
            _desktoppath="$HOME/.local/share/applications/"
            printf "Creating: %s\n" "$_desktoppath$_name.desktop"
            desktop-file-install --delete-original --dir="$_desktoppath" "$_zoomdesktopfile"
            ;;
    esac
done