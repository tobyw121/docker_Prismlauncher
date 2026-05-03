#!/usr/bin/env bash
set -e

# --- Start des originalen Skriptinhalts, aber die tput-Zeilen und Farbvariablen sind entfernt ---
# Die originalen tput-Aufrufe sind hier nicht enthalten.
# Die Farbvariablen werden als leer definiert, damit das Skript nicht abbricht.
color_normal=""
color_bold=""
color_green=""
color_orange=""
color_blue=""
color_red=""
color_purple=""
noninteractive_mode=0
apt_args=()

# Handy functions.
# Die Funktionen msg, error, question etc. bleiben erhalten, aber ohne Farb-Escape-Sequenzen.
msg() {
    echo "[>] ${1}"
}

error() {
    echo "[!] ${1}"
}

question() {
    echo "[?] ${1}"
}

die_cmd() {
    error "${1}"
    exit 1
}

answered_yes() {
    if [[ "${1}" == "" || "${1,,}" == "y" ]]; then
        return 0
    else
        return 1
    fi
}

# Pre-checks.
if [[ "${UID}" == "0" ]]; then
    die_cmd "This script is not allowed to be run under the root user. Please run as a normal user and try again."
fi

# Program start.
echo "-------------------------"
echo "[#] makedeb Installer [#]"
echo "-------------------------"
echo

if ! echo "${-}" | grep -q i; then
    msg "Running in noninteractive mode."
    noninteractive_mode=1
    export DEBIAN_FRONTEND=noninteractive
    apt_args+=('-y')
fi

msg "Ensuring needed packages are installed..."
# Sicherstellen, dass sudo im PATH ist, falls es nicht explizit enthalten ist
# und der sudoers Eintrag funktioniert.
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
if ! sudo apt-get update "${apt_args[@]}"; then
    die_cmd "Failed to update APT cache."
fi

missing_dependencies=()
dpkg-query -W 'wget' > /dev/null 2>&1 || missing_dependencies+=('wget')
dpkg-query -W 'gpg' > /dev/null 2>&1 || missing_dependencies+=('gpg')

if ! ( test -z "${missing_dependencies[*]}" || sudo apt-get install "${apt_args[@]}" --mark-auto "${missing_dependencies[@]}" ); then
    die_cmd "Failed to install needed packages."
fi

echo

# MAKEDEB_RELEASE handling (sicherstellen, dass es im nicht-interaktiven Modus gesetzt ist)
if (( "${noninteractive_mode}" )) && [[ "${MAKEDEB_RELEASE:+x}" == '' ]]; then
    # Hier geben wir einen Standardwert für den Build an, da wir nicht interaktiv sind
    MAKEDEB_RELEASE="makedeb"
    msg "MAKEDEB_RELEASE not specified in non-interactive mode. Defaulting to '${MAKEDEB_RELEASE}'."
elif [[ "${MAKEDEB_RELEASE:+x}" == '' ]]; then
    # Dieser Block wird im Docker Build nicht erreicht, da wir MAKEDEB_RELEASE setzen
    msg "Multiple releases of makedeb are available for installation."
    msg "Currently, you can install one of 'makedeb', 'makedeb-beta', or"
    msg "'makedeb-alpha'."

    while true; do
        read -p "$(question "Which release would you like? ")" MAKEDEB_RELEASE

        if ! echo "${MAKEDEB_RELEASE}" | grep -qE '^makedeb$|^makedeb-beta$|^makedeb-alpha$'; then
            error "Invalid response: ${MAKEDEB_RELEASE}"
            continue
        fi

        break
    done

    echo
fi

case "${MAKEDEB_RELEASE}" in
    makedeb|makedeb-alpha|makedeb-beta)
        ;;
    *)
        echo
        error "Invalid \$MAKEDEB_RELEASE: '${MAKEDEB_RELEASE}'"
        exit 1 ;;
esac

msg "Setting up makedeb APT repository..."
if ! wget -qO - "https://proget.makedeb.org/debian-feeds/makedeb.pub" | gpg --dearmor | sudo tee /usr/share/keyrings/makedeb-archive-keyring.gpg 1> /dev/null; then
    die_cmd "Failed to set up makedeb APT repository."
fi
echo "deb [signed-by=/usr/share/keyrings/makedeb-archive-keyring.gpg arch=all] https://proget.makedeb.org makedeb main" | sudo tee /etc/apt/sources.list.d/makedeb.list 1> /dev/null

msg "Updating APT cache..."
if ! sudo apt-get update "${apt_args[@]}"; then
    die_cmd "Failed to update APT cache."
fi

echo
msg "Installing '${MAKEDEB_RELEASE}'..."
if ! sudo apt-get install "${apt_args[@]}" -- "${MAKEDEB_RELEASE}"; then
    die_cmd "Failed to install package."
fi

msg "Finished! If you need help of any kind, feel free to reach out:"
echo
msg "makedeb Homepage:            https://makedeb.org"
msg "makedeb Package Repository:  https://mpr.makedeb.org"
msg "makedeb Documentation:       https://docs.makedeb.org"
msg "makedeb Support:             https://docs.makedeb.org/support/obtaining-support"
echo
msg "Enjoy makedeb!"
