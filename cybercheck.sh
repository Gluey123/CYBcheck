#!/bin/bash
# verify_cyb102.sh
# Checks whether the CodePath CYB102 install_tool.sh setup actually worked,
# unit by unit, based on what each unit's script is documented to install
# (see codepath/cyb102-vm-setup README).
#
# Usage:
#   chmod +x verify_cyb102.sh
#   ./verify_cyb102.sh            # check everything
#   ./verify_cyb102.sh 3          # check only unit 3 (+ RDP)
#
# Exit code: 0 if nothing failed, 1 if any hard check failed.

none='\033[0m'
green='\033[0;32m'
red='\033[0;31m'
yellow='\033[33m'
bold='\033[1m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${green}[OK]${none}   $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${red}[FAIL]${none} $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${yellow}[WARN]${none} $1"; WARN=$((WARN+1)); }
section() { echo -e "\n${bold}== $1 ==${none}"; }

has_cmd() { command -v "$1" &> /dev/null; }
has_deb() { dpkg -s "$1" &> /dev/null; }
svc_active() { systemctl is-active --quiet "$1" 2>/dev/null; }

only_unit="$1"   # optional: pass a number 1-5 to check just that unit (RDP always checked)

check_unit() {
    [ -z "$only_unit" ] || [ "$only_unit" == "$1" ]
}

# ---------------------------------------------------------------------------
section "RDP (xrdp, xfce4)"
if [ -z "$only_unit" ] || [ "$only_unit" == "0" ] || [ "$only_unit" == "rdp" ]; then
    has_deb xrdp && pass "xrdp package installed" || fail "xrdp package not found"
    svc_active xrdp && pass "xrdp service is running" || warn "xrdp service not active (may just need a reboot/start)"
    has_cmd startxfce4 && pass "xfce4 (startxfce4) found" || fail "xfce4 not found"
fi

# ---------------------------------------------------------------------------
section "Unit 1 (Wireshark)"
if check_unit 1; then
    has_deb wireshark || has_deb wireshark-common && pass "wireshark package installed" || fail "wireshark package not found"
    has_cmd tshark && pass "tshark CLI found" || warn "tshark not found (odd if wireshark is installed)"
fi

# ---------------------------------------------------------------------------
section "Unit 2 (no tools installed by design)"
if check_unit 2; then
    echo -e "  ${yellow}N/A${none} — Unit 2 doesn't install anything; files are downloaded during the lab/project itself."
fi

# ---------------------------------------------------------------------------
section "Unit 3 Lab (Snort)"
if check_unit 3; then
    if has_cmd snort; then
        pass "snort binary found ($(snort -V 2>&1 | head -n1 | tr -d '\r'))"
    else
        fail "snort binary not found"
    fi

    section "Unit 3 Project (node, npm, hftp)"
    has_cmd node && pass "node found ($(node -v))" || fail "node not found"
    has_cmd npm && pass "npm found ($(npm -v))" || fail "npm not found"

    # hftp is typically a project-local dependency, not global — look for it
    hftp_hit=$(find "$HOME" -maxdepth 6 -type d -iname "hftp" 2>/dev/null | head -n1)
    ftp_project_hit=$(find "$HOME" -maxdepth 6 -type d -iname "ftp_project" 2>/dev/null | head -n1)
    if [ -n "$hftp_hit" ]; then
        pass "hftp found at: $hftp_hit"
    else
        warn "hftp not found under \$HOME — check inside your ftp_project's node_modules if the project script placed it elsewhere"
    fi
    if [ -n "$ftp_project_hit" ]; then
        pass "ftp_project directory found at: $ftp_project_hit"
    else
        warn "ftp_project directory not found under \$HOME — confirm where unit3_project.sh placed it"
    fi
fi

# ---------------------------------------------------------------------------
section "Unit 4 Lab (mitmproxy — installed in-lab, not by the setup script)"
if check_unit 4; then
    has_cmd mitmproxy && pass "mitmproxy found" || warn "mitmproxy not found (expected — it's installed during the lab itself, not by install_tool.sh)"

    section "Unit 4 Project (nginx, slowloris)"
    has_deb nginx && pass "nginx package installed" || fail "nginx package not found"
    svc_active nginx && pass "nginx service is running" || warn "nginx installed but not currently running"
    slowloris_hit=$(find / -maxdepth 6 \( -iname "slowloris*" \) -not -path "*/proc/*" 2>/dev/null | head -n1)
    has_cmd slowloris || pip show slowloris &>/dev/null || [ -n "$slowloris_hit" ] \
        && pass "slowloris found${slowloris_hit:+ at: $slowloris_hit}" \
        || fail "slowloris not found (checked PATH, pip, and common dirs)"
fi

# ---------------------------------------------------------------------------
section "Unit 5 Lab (Splunk)"
if check_unit 5; then
    if [ -d /opt/splunk ]; then
        pass "/opt/splunk directory exists"
        if [ -x /opt/splunk/bin/splunk ]; then
            pass "splunk binary present"
            /opt/splunk/bin/splunk status 2>/dev/null | grep -qi "running" \
                && pass "splunkd is running" \
                || warn "splunkd installed but not currently running (try: sudo /opt/splunk/bin/splunk start)"
        else
            fail "splunk binary missing under /opt/splunk/bin"
        fi
    else
        fail "/opt/splunk not found — Splunk does not appear installed"
    fi
    echo -e "  ${yellow}Note:${none} netflix_titles.csv, 'Top Video Game sales.csv', and webauth.csv are loaded"
    echo -e "        directly into Splunk indexes during setup, so they may not persist as loose files."
    echo -e "        Confirm via Splunk's web UI (Settings > Indexes, or run a search) rather than 'find'."

    section "Unit 5 Project (data loaded into Splunk)"
    echo -e "  ${yellow}Note:${none} webserver02.csv, uploadedhashes.csv, failedlogins64.csv, BlueCoatProxy01.csv"
    echo -e "        are also ingested into Splunk rather than left on disk — check inside Splunk."
fi

# ---------------------------------------------------------------------------
section "Units 6-8 (no VM install required)"
if check_unit 6 || check_unit 7 || check_unit 8; then
    echo -e "  ${yellow}N/A${none} — these units run in-browser or are group projects; nothing to verify here."
fi

# ---------------------------------------------------------------------------
section "Summary"
echo -e "  ${green}Passed:${none} $PASS   ${red}Failed:${none} $FAIL   ${yellow}Warnings:${none} $WARN"
if [ "$FAIL" -gt 0 ]; then
    echo -e "\n${red}Some checks failed.${none} Easiest fix: re-run install_tool.sh and choose the specific"
    echo -e "unit that failed (option 2 in its menu) rather than reinstalling everything."
    exit 1
else
    echo -e "\n${green}Everything checked out (or only has non-fatal warnings).${none}"
    exit 0
fi
