#!/bin/sh
# d01_exe.sh -- aka the downloader

ahr_stamp() { date +"%Y%m%d%H%M%S%N" | cut -c 1-23; }
rSke=$(cd "$(dirname "$0")" && pwd)
serial="$(ahr_stamp)${D_TME}"

D_KV="Ⓥ"  # key/value replaces = for safe eval
D_SPC="Ⓣ" # \txtdlm,  replaces blank/white spaces
D_ROW="Ⓐ" # row delimiter
D_FLD="↔"  # field delimiter (plain, semiotics-friendly)
D_TME="⧖" # \tmedlm, tme (Time Machine Efficiency)

bkp_arg="${rSke}/INV"  # repository directory
rep_arg="${rSke}/RPT"  # Stamp file directory (reports)
[ ! -d "$bkp_arg" ] && mkdir -p "$bkp_arg"
[ ! -d "$rep_arg" ] && mkdir -p "$rep_arg"

show_prompt() { printf "$1 "; }
read_pause() { echo ""; show_prompt "Press Enter..."; read dummy; }

ck_internet() {
    DEB_DIR="${bkp_arg}/zzTop"
    [ ! -d "${DEB_DIR}" ] && mkdir -p "${DEB_DIR}"
    cd "$DEB_DIR" || { echo "ERR: Cannot cd to Test ${DEB_DIR}"; exit 1; }

    GATEWAY=$(ip route | awk '/default/ {print $3; exit}')
    [ -z "$GATEWAY" ] && { echo "ERR: No default gateway found"; exit 1; }

    DEB_test="iftop"
    ping -c 2 "$GATEWAY" >/dev/null 2>&1 || { echo "ERR: Gateway unreachable"; exit 1; }

    apt download "$DEB_test" >/dev/null 2>&1
    sleep 0.1

    if ! ls "${DEB_test}"_*.deb >/dev/null 2>&1; then
        echo "error critical your sys cannot download.deb/s"
        rm -r "$DEB_DIR"
        exit 1
    fi

    echo "      ... G: $GATEWAY"
    (rm -f "${DEB_test}"_*.deb && rm -r "$DEB_DIR")
}

pro_input() {
    clear
    echo "————————————————————————————————————————————————————————————————"
    printf '%s\n' \
    "The Profile Name for this download"
    printf '%s\n' \
    "     - is used to create repository subdir and final tarball"
    printf '%s\n' ""
    printf '%s\n' \
    "  Enter a short identifier (e.g., o1SSH)."
    printf '%s\n' \
    "  Allowed characters: letters, digits, hyphen, underscore. No spaces."
    printf '%s\n' \
    "  If left empty or invalid, files will be downloaded into:"
    printf '%s\n' "     - ${bkp_arg}/"
    printf '%s\n' "     - (no subdir) and no tarball will be created."
    printf '%s\n' ""
    printf '%s' "Please type profile name and press enter: "
    read -r profile_input
    echo "————————————————————————————————————————————————————————————————"
    if [ -n "profile_input" ] && printf '%s\n' "profile_input" \
      | grep -Eq '^[A-Za-z0-9_-]{1,64}$'; then

      profile="$profile_input"
      echo ""
      printf '%s\n' \
      "Enter one or many package names for $profile_input profile"
      printf '%s\n' "     - separate each name by space e.g."
      printf '%s\n' "     - openssl_server iftop tree openssl"
      printf '%s\n' \
      "or just press enter and create a default sys-base repository"
      echo ""
      printf '%s' \
      "Enter stack for this profile $profile_input and press enter: "
      read -r package_inp
      echo "————————————————————————————————————————————————————————————————"
    fi
}

cre_depend() {
    # create data dump
    inp_tmp=$(mktemp)
    trap 'rm -f "$inp_tmp"' EXIT

    if [ -z "$package_inp" ]; then
        pkd="\n"
        # package_inp=$(dpkg --get-selections \
    #| awk -v d="$pkd" '!/deinstall/{printf "%s%s", $1, d}')
    package_inp="apt-offline apt-utils apt-file apt-listchanges apt-show-version zip"
    fi

    for inp in $(echo "$package_inp" | tr ' ' '\n'); do
        # here we can check if input is correct
        printf '%s\n' "$inp" >>"$inp_tmp"
    done

    # settle the reports path default or profile
    if [ -z "$profile_input" ]; then
        path_dir="$rep_arg"
        dir_dnld="${bkp_arg}"
        profile_input="base"
    else
        path_dir="${rep_arg}/${profile_input}"
        dir_dnld="${bkp_arg}/${profile_input}"
        [ ! -d "$path_dir" ] && mkdir -p "$path_dir"
        [ ! -d "$dir_dnld" ] && mkdir -p "$dir_dnld"
    fi

    # build depend w/depend_v07.sh
    inp=""
    for inp in $(cat "$inp_tmp"); do
        printf '%s\n' "Building Dependencies: $inp to: $path_dir"
        ./d01_dep.sh "$inp" "$path_dir"
    done
}

dnld_report() {
    v1_out="${path_dir}/${serial}.dnld"
    v1_tmp=$(mktemp) || exit 1
    trap 'rm -f "$v1_tmp"' EXIT

    for fle in "${path_dir}"/*.depends; do
        [ -f "$fle" ] || continue
        echo "Processing Dependencies: $fle"
        # simply cat all .depends files into temp
        cat "$fle" >> "$v1_tmp"
    done

    # deduplicate, sort, and save
    LC_ALL=C sort -u "$v1_tmp" > "$v1_out"

    line_count=$(wc -l < "$v1_out" | tr -d ' ')
    echo "Saved download list: $v1_out (lines: $line_count)"

    rm -f /tmp/tmp.* 2>/dev/null
    rm -f "${path_dir}"/*.depends
}

# --- srcFS - search directory for pattern by file/dir type
srcFS() {
    local dir="$1"; local ptrn="$2"; local mod="$3"; local results="";

    [ "$mod" = "D" ] && results=$(ls -l "$dir" 2>/dev/null \
        | awk -v pattern="$ptrn" '$1 ~ /^d/ && $NF ~ pattern {print $NF}' \
        | tail -n1)

    [ "$mod" = "F" ] && results=$(ls -l "$dir" 2>/dev/null \
        | awk -v pattern="$ptrn" '$1 ~ /^-/ && $NF ~ pattern {print $NF}' \
        | tail -n1)

    echo "$results"
}

downloader() {
    debs_inv="${path_dir}/${serial}${D_TME}debs.inv"
    ghost_inv="${path_dir}/${serial}${D_TME}ghost.inv"
    (touch "$debs_inv" && touch "$ghost_inv")

    [ -z "$v1_out" ] && { echo "ERR: v1_out not set"; return 1; }
    [ ! -f "$v1_out" ] && { echo "ERR: $v1_out not found"; return 1; }
    cd "$dir_dnld" || { echo "ERR: Cannot cd to $dir_dnld"; return 1; }

    echo ""
    echo "————————————————————————————————————————————————————————————————"
    echo "Downloading packages from: $v1_out"
    echo "Target directory: $dir_dnld"
    echo "————————————————————————————————————————————————————————————————"

    total=$(wc -l < "$v1_out" | tr -d ' ')
    count=0
    failed=0
    success=0

    while read -r pkg; do
        [ -z "$pkg" ] && continue
        count=$((count + 1))

        printf "[%3d/%3d] Downloading: %-40s " "$count" "$total" "$pkg"
        (cd "$dir_dnld")
        if apt-get download "$pkg" >/dev/null 2>&1; then
            echo "✓"
            success=$((success + 1))

            # Find the downloaded .deb file (search in CURRENT dir, not path_dir)
            v1_deb=$(srcFS "$dir_dnld" "$pkg" "F")
            if [ -n "$v1_deb" ]; then
                echo "${count}${D_FLD}${pkg}${D_FLD}${v1_deb}" >> "$debs_inv"
            fi
        else
            echo "✗ FAILED"
            failed=$((failed + 1))
            echo "${count}${D_FLD}${pkg}${D_FLD}ghost" >> "$ghost_inv"
        fi

    done < "$v1_out"

    echo "————————————————————————————————————————————————————————————————"
    echo "Download Summary:"
    echo "  Total packages: $total"
    echo "  Successful: $success"
    echo "  Failed: $failed"
    echo "  Inventory: $debs_inv"
    echo "  Ghosts: $ghost_inv"
    echo "————————————————————————————————————————————————————————————————"

    # Show preview of inventories
    echo ""
    echo "First 5 successful downloads:"
    head -5 "$debs_inv" | sed 's/^/    /'

    if [ -s "$ghost_inv" ]; then
        echo ""
        echo "Missing packages (ghosts):"
        head -5 "$ghost_inv" | sed 's/^/    /'
    fi
}

runtime() {
    # ck_internet
    pro_input
    cre_depend
    dnld_report
    downloader
    tar_dir="${rSke}/TAR"
    [ ! -d "$tar_dir" ] && mkdir -p "$tar_dir"
    cd "$dir_dnld" || { echo "ERR: Cannot cd to $dir_dnld"; exit 1; }
    tar -czf "${tar_dir}/${serial}${D_TME}${profile_input}.tar.gz" .
}

runtime
