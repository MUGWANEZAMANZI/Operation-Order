#!/bin/bash
# Digital Forensics Automation Script
# Student Name: MUGWANEZA MANZO Audace
# Student Code: s39
# Class Code: RW-University-II
# Lecturer: DOMINIQUE

# Exit if not run as root
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run as root. Exiting..."
    exit 1
fi

# Create necessary directories
OUTPUT_DIR="forensic_output"
VOLATILITY_DIR="/opt/volatility"
LOG_FILE="$OUTPUT_DIR/forensic_report.txt"
VOLATILITY_LOG="$OUTPUT_DIR/volatility_install.log"
FORENSIC_LOG="$OUTPUT_DIR/forensic_log.txt"
mkdir -p "$OUTPUT_DIR"

# Append logs instead of overwriting
exec &> >(tee -a "$FORENSIC_LOG")

echo "[INFO] Script execution started at $(date)"

# Function to install missing forensic tools (except Volatility)
tools=(bulk_extractor binwalk foremost strings)
install_tools() {
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            echo "[INFO] Installing $tool..."
            apt-get install -y "$tool"
        else
            echo "[INFO] $tool is already installed."
        fi
    done
}
install_tools

# Install and Set Up Volatility from GitHub
install_volatility() {
    if [[ ! -d "$VOLATILITY_DIR" ]]; then
        echo "[INFO] Installing Volatility from GitHub..."
        script -q -c "
            git clone https://github.com/volatilityfoundation/volatility.git $VOLATILITY_DIR &&
            cd $VOLATILITY_DIR &&
            chmod +x vol
        " "$VOLATILITY_LOG"
    else
        echo "[INFO] Volatility is already installed in $VOLATILITY_DIR"
    fi
}
install_volatility

# Get user input for file to analyze
read -p "Enter the full path of the file to analyze: " FILE_PATH
if [[ ! -f "$FILE_PATH" ]]; then
    echo "[ERROR] File does not exist! Exiting..."
    exit 1
fi

# Perform data carving
echo "[INFO] Extracting data using Bulk Extractor, Binwalk, and Foremost..."
bulk_extractor -o "$OUTPUT_DIR/bulk" "$FILE_PATH"
binwalk -e "$FILE_PATH" --run-as=root -C "$OUTPUT_DIR/binwalk" 2>/dev/null
foremost -T -o "$OUTPUT_DIR/foremost" "$FILE_PATH"

# Check for human-readable data
echo "[INFO] Searching for readable content..."
strings "$FILE_PATH" | grep -E "(password|username|exe)" > "$OUTPUT_DIR/strings.txt"

# Network Traffic Extraction
echo "[INFO] Checking for network traffic..."
tcpdump -r "$FILE_PATH" > "$OUTPUT_DIR/network_traffic.pcap" 2>/dev/null
if [[ -s "$OUTPUT_DIR/network_traffic.pcap" ]]; then
    echo "[INFO] Network traffic found and saved."
else
    rm "$OUTPUT_DIR/network_traffic.pcap"
    echo "[INFO] No network traffic detected."
fi

# Memory Analysis with Volatility
VOLATILITY_CMD="$VOLATILITY_DIR/vol"
if [[ -x "$VOLATILITY_CMD" ]]; then
    if $VOLATILITY_CMD -f "$FILE_PATH" imageinfo &> /dev/null; then
        echo "[INFO] Performing memory analysis with Volatility..."
        PROFILE=$($VOLATILITY_CMD -f "$FILE_PATH" imageinfo | grep Profile | awk -F ":" '{print $2}')
        $VOLATILITY_CMD -f "$FILE_PATH" --profile="$PROFILE" pslist > "$OUTPUT_DIR/processes.txt"
        $VOLATILITY_CMD -f "$FILE_PATH" --profile="$PROFILE" connections > "$OUTPUT_DIR/network_connections.txt"
        $VOLATILITY_CMD -f "$FILE_PATH" --profile="$PROFILE" hivelist > "$OUTPUT_DIR/registry_info.txt"
    else
        echo "[ERROR] Volatility cannot analyze this file. Skipping..."
    fi
else
    echo "[ERROR] Volatility executable not found. Check installation."
fi

# Generate report
echo "[INFO] Generating forensic report..."
{
    echo "Forensic Analysis Report"
    echo "Date: $(date)"
    echo "Analyzed File: $FILE_PATH"
    echo "Extracted Data: $(ls -l $OUTPUT_DIR | wc -l) files"
} >> "$LOG_FILE"

# Compress results
zip -r "$OUTPUT_DIR/forensic_results.zip" "$OUTPUT_DIR"
echo "[INFO] Analysis complete! Results saved in $OUTPUT_DIR/forensic_results.zip"

# Final log entry
echo "[INFO] Script execution completed at $(date)"
