#!/bin/bash

set -e

PROFILE_DIR="${1%/}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

calc() { awk "BEGIN {printf \"%.2f\", $*}"; }
calc_precise() { awk "BEGIN {printf \"%.6f\", $*}"; }
calc_int() { awk "BEGIN {printf \"%.0f\", $*}"; }

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}$(printf '=%.0s' {1..80})${NC}"
    echo -e "${BOLD}${WHITE}$1${NC}"
    echo -e "${BOLD}${CYAN}$(printf '=%.0s' {1..80})${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BOLD}${BLUE}>>> $1${NC}"
    echo -e "${GRAY}$(printf '─%.0s' {1..80})${NC}"
}

print_metric() {
    printf "${GRAY}%-50s${NC} ${2}%-30s${NC}\n" "$1" "$3"
}

# Smart value combiner: takes aic and aiv values, returns the best one
# Usage: combine_values "$aic_val" "$aiv_val"
combine_values() {
    local aic="$1"
    local aiv="$2"
    
    # Convert N/A or empty to 0
    [ -z "$aic" ] || [ "$aic" = "N/A" ] && aic="0"
    [ -z "$aiv" ] || [ "$aiv" = "N/A" ] && aiv="0"
    
    # Check if both are zero
    local aic_zero=$(awk -v val="$aic" 'BEGIN{print (val == 0 || val == 0.0)}')
    local aiv_zero=$(awk -v val="$aiv" 'BEGIN{print (val == 0 || val == 0.0)}')
    
    if [ "$aic_zero" = "1" ] && [ "$aiv_zero" = "1" ]; then
        echo ""
        return
    elif [ "$aic_zero" = "1" ]; then
        echo "$aiv"
    elif [ "$aiv_zero" = "1" ]; then
        echo "$aic"
    else
        # Both have data - sum them
        awk -v a="$aic" -v b="$aiv" 'BEGIN{printf "%.6f", a+b}'
    fi
}

# ==============================================================================
# INPUT VALIDATION
# ==============================================================================

if [ -z "$PROFILE_DIR" ]; then
    echo "Usage: bash $0 <profiling_folder>"
    exit 1
fi

if [ ! -d "$PROFILE_DIR" ]; then
    echo -e "${RED}Error: Directory not found: $PROFILE_DIR${NC}"
    exit 1
fi

# ==============================================================================
# FIND METRIC DIRECTORIES AND FILES
# ==============================================================================

clear
print_header "NPU KERNEL PROFILING ANALYSIS"

echo -e "${BOLD}Profile Directory:${NC} ${PROFILE_DIR}"
echo -e "${BOLD}Analysis Time:${NC}     $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

find_latest_file() {
    local dir=$1
    local pattern=$2
    find "$dir" -name "$pattern" 2>/dev/null | sort -t'_' -k2 -r | head -1
}

# Find metric directories
MEMORY_DIR=$(find ${PROFILE_DIR} -type d -name "*metric_Memory" 2>/dev/null | head -1)
MEMACCESS_DIR=$(find ${PROFILE_DIR} -type d -name "*metric_MemoryAccess" 2>/dev/null | head -1)
PIPE_DIR=$(find ${PROFILE_DIR} -type d -name "*metric_PipeUtilization" 2>/dev/null | head -1)
L2_DIR=$(find ${PROFILE_DIR} -type d -name "*metric_L2Cache" 2>/dev/null | head -1)

# Get op_summary files from each metric
PIPE_OP_FILE=""
MEMACCESS_OP_FILE=""
MEMORY_OP_FILE=""
L2_OP_FILE=""

[ ! -z "$PIPE_DIR" ] && PIPE_OP_FILE=$(find_latest_file "$PIPE_DIR" "op_summary_*.csv")
[ ! -z "$MEMACCESS_DIR" ] && MEMACCESS_OP_FILE=$(find_latest_file "$MEMACCESS_DIR" "op_summary_*.csv")
[ ! -z "$MEMORY_DIR" ] && MEMORY_OP_FILE=$(find_latest_file "$MEMORY_DIR" "op_summary_*.csv")
[ ! -z "$L2_DIR" ] && L2_OP_FILE=$(find_latest_file "$L2_DIR" "op_summary_*.csv")

HBM_FILE=""
[ ! -z "$MEMORY_DIR" ] && HBM_FILE=$(find_latest_file "$MEMORY_DIR" "hbm_*.csv")

API_FILE=$(find ${PROFILE_DIR} -name "api_statistic_*.csv" 2>/dev/null | sort -t'_' -k2 -r | head -1)

# Use any available op_summary for kernel detection
OP_FILE=""
if [ ! -z "$PIPE_OP_FILE" ]; then
    OP_FILE="$PIPE_OP_FILE"
elif [ ! -z "$MEMACCESS_OP_FILE" ]; then
    OP_FILE="$MEMACCESS_OP_FILE"
elif [ ! -z "$MEMORY_OP_FILE" ]; then
    OP_FILE="$MEMORY_OP_FILE"
else
    OP_FILE=$(find ${PROFILE_DIR} -name "op_summary_*.csv" 2>/dev/null | sort -t'_' -k2 -r | head -1)
fi

# ==============================================================================
# KERNEL DETECTION 
# ==============================================================================

print_header "KERNEL DETECTION"

if [ ! -f "$OP_FILE" ]; then
    echo -e "${RED}Error: No op_summary file found${NC}"
    exit 1
fi

echo "Available kernels:"
tail -n +2 "$OP_FILE" | cut -d',' -f5 | sort -u | nl -w2 -s'. '
echo ""

TRITON_LINE=$(tail -n +2 "$OP_FILE" | grep -i "triton" | head -n 1)

if [ -z "$TRITON_LINE" ]; then
    TRITON_LINE=$(tail -n +2 "$OP_FILE" | awk -F',' '$10 > 1000 {print; exit}')
    if [ -z "$TRITON_LINE" ]; then
        echo -e "${RED}Error: No kernel with significant execution time found${NC}"
        exit 1
    fi
fi

KERNEL_NAME=$(echo "$TRITON_LINE" | cut -d',' -f5)
echo -e "${GREEN}Selected kernel: ${BOLD}${KERNEL_NAME}${NC}"

# ==============================================================================
# TIMING ANALYSIS
# ==============================================================================

print_header "KERNEL TIMING ANALYSIS"

STREAM_ID=$(echo "$TRITON_LINE" | cut -d',' -f4)
TASK_DURATION=$(echo "$TRITON_LINE" | cut -d',' -f10)
WAIT_TIME=$(echo "$TRITON_LINE" | cut -d',' -f11)
BLOCK_DIM=$(echo "$TRITON_LINE" | cut -d',' -f12)

EXEC_MS=$(calc "$TASK_DURATION / 1000")
EXEC_S=$(calc_precise "$TASK_DURATION / 1000000")
WAIT_MS=$(calc "$WAIT_TIME / 1000")
TOTAL_US=$(calc "$TASK_DURATION + $WAIT_TIME")
TOTAL_MS=$(calc "$TOTAL_US / 1000")

EXEC_PERCENT=$(calc "($TASK_DURATION / $TOTAL_US) * 100")
WAIT_PERCENT=$(calc "($WAIT_TIME / $TOTAL_US) * 100")

echo -e "${BOLD}Kernel:${NC}     ${KERNEL_NAME}"
echo -e "${BOLD}Stream ID:${NC}  ${STREAM_ID}"
echo -e "${BOLD}Block Dim:${NC}  ${BLOCK_DIM}"
echo ""

print_section "Timing Breakdown"

print_metric "Task Duration (Execution)" "$GREEN" "${TASK_DURATION} μs (${EXEC_MS} ms)"
print_metric "Wait Time (Scheduling/Overhead)" "$YELLOW" "${WAIT_TIME} μs (${WAIT_MS} ms)"
print_metric "Total Time" "$CYAN" "${TOTAL_US} μs (${TOTAL_MS} ms)"
echo ""
print_metric "Execution Efficiency" "$GREEN" "${EXEC_PERCENT}%"
print_metric "Overhead Percentage" "$YELLOW" "${WAIT_PERCENT}%"

# ==============================================================================
# MTE TIMING - FROM PIPEUTILIZATION
# ==============================================================================

print_header "MEMORY TRANSFER ENGINE (MTE) TIMING"

echo "MTE operations move data between Global Memory (GM/DDR) and Unified Buffer (UB)."
echo "Source: PipeUtilization metric - Table 2 (mte2_time, mte3_time)"
echo ""

MTE2_TIME_US=""
MTE3_TIME_US=""
MTE2_RATIO=""
MTE3_RATIO=""

if [ ! -z "$PIPE_OP_FILE" ] && [ -f "$PIPE_OP_FILE" ]; then
    PIPE_KERNEL_LINE=$(tail -n +2 "$PIPE_OP_FILE" | grep "$KERNEL_NAME" | head -n 1)
    
    if [ ! -z "$PIPE_KERNEL_LINE" ]; then
        PIPE_HEADER=$(head -n 1 "$PIPE_OP_FILE")
        TOTAL_COLS=$(echo "$PIPE_HEADER" | awk -F',' '{print NF}')
        
        # Find both aic_ and aiv_ columns
        AIC_MTE2_TIME_COL=0
        AIV_MTE2_TIME_COL=0
        AIC_MTE3_TIME_COL=0
        AIV_MTE3_TIME_COL=0
        AIC_MTE2_RATIO_COL=0
        AIV_MTE2_RATIO_COL=0
        AIC_MTE3_RATIO_COL=0
        AIV_MTE3_RATIO_COL=0
        
        for i in $(seq 1 $TOTAL_COLS); do
            COL_NAME=$(echo "$PIPE_HEADER" | cut -d',' -f$i | tr -d ' \r\n' | tr '[:upper:]' '[:lower:]')
            
            [[ "$COL_NAME" =~ ^aic_mte2.*time ]] && AIC_MTE2_TIME_COL=$i
            [[ "$COL_NAME" =~ ^aiv_mte2.*time ]] && AIV_MTE2_TIME_COL=$i
            [[ "$COL_NAME" =~ ^aic_mte3.*time ]] && AIC_MTE3_TIME_COL=$i
            [[ "$COL_NAME" =~ ^aiv_mte3.*time ]] && AIV_MTE3_TIME_COL=$i
            [[ "$COL_NAME" =~ ^aic_mte2.*ratio ]] && AIC_MTE2_RATIO_COL=$i
            [[ "$COL_NAME" =~ ^aiv_mte2.*ratio ]] && AIV_MTE2_RATIO_COL=$i
            [[ "$COL_NAME" =~ ^aic_mte3.*ratio ]] && AIC_MTE3_RATIO_COL=$i
            [[ "$COL_NAME" =~ ^aiv_mte3.*ratio ]] && AIV_MTE3_RATIO_COL=$i
        done
        
        # Extract both values
        AIC_MTE2_TIME=""
        AIV_MTE2_TIME=""
        AIC_MTE3_TIME=""
        AIV_MTE3_TIME=""
        AIC_MTE2_RATIO=""
        AIV_MTE2_RATIO=""
        AIC_MTE3_RATIO=""
        AIV_MTE3_RATIO=""
        
        [ $AIC_MTE2_TIME_COL -gt 0 ] && AIC_MTE2_TIME=$(echo "$PIPE_KERNEL_LINE" | cut -d',' -f$AIC_MTE2_TIME_COL | tr -d ' \r\n')
        [ $AIV_MTE2_TIME_COL -gt 0 ] && AIV_MTE2_TIME=$(echo "$PIPE_KERNEL_LINE" | cut -d',' -f$AIV_MTE2_TIME_COL | tr -d ' \r\n')
        [ $AIC_MTE3_TIME_COL -gt 0 ] && AIC_MTE3_TIME=$(echo "$PIPE_KERNEL_LINE" | cut -d',' -f$AIC_MTE3_TIME_COL | tr -d ' \r\n')
        [ $AIV_MTE3_TIME_COL -gt 0 ] && AIV_MTE3_TIME=$(echo "$PIPE_KERNEL_LINE" | cut -d',' -f$AIV_MTE3_TIME_COL | tr -d ' \r\n')
        [ $AIC_MTE2_RATIO_COL -gt 0 ] && AIC_MTE2_RATIO=$(echo "$PIPE_KERNEL_LINE" | cut -d',' -f$AIC_MTE2_RATIO_COL | tr -d ' \r\n')
        [ $AIV_MTE2_RATIO_COL -gt 0 ] && AIV_MTE2_RATIO=$(echo "$PIPE_KERNEL_LINE" | cut -d',' -f$AIV_MTE2_RATIO_COL | tr -d ' \r\n')
        [ $AIC_MTE3_RATIO_COL -gt 0 ] && AIC_MTE3_RATIO=$(echo "$PIPE_KERNEL_LINE" | cut -d',' -f$AIC_MTE3_RATIO_COL | tr -d ' \r\n')
        [ $AIV_MTE3_RATIO_COL -gt 0 ] && AIV_MTE3_RATIO=$(echo "$PIPE_KERNEL_LINE" | cut -d',' -f$AIV_MTE3_RATIO_COL | tr -d ' \r\n')
        
        # Combine values intelligently
        MTE2_TIME_US=$(combine_values "$AIC_MTE2_TIME" "$AIV_MTE2_TIME")
        MTE3_TIME_US=$(combine_values "$AIC_MTE3_TIME" "$AIV_MTE3_TIME")
        MTE2_RATIO=$(combine_values "$AIC_MTE2_RATIO" "$AIV_MTE2_RATIO")
        MTE3_RATIO=$(combine_values "$AIC_MTE3_RATIO" "$AIV_MTE3_RATIO")
    fi
fi

if [ ! -z "$MTE2_TIME_US" ]; then
    print_section "MTE Operation Times"
    
    echo "MTE2: GM → UB (Read from Global Memory to Unified Buffer)"
    print_metric "  Time" "$GREEN" "${MTE2_TIME_US} μs"
    [ ! -z "$MTE2_RATIO" ] && print_metric "  Cycle Ratio" "$GREEN" "${MTE2_RATIO}"
    echo ""
    
    echo "MTE3: UB → GM (Write from Unified Buffer to Global Memory)"
    print_metric "  Time" "$CYAN" "${MTE3_TIME_US} μs"
    [ ! -z "$MTE3_RATIO" ] && print_metric "  Cycle Ratio" "$CYAN" "${MTE3_RATIO}"
    echo ""
    
    TOTAL_MTE_US=$(awk -v m2="$MTE2_TIME_US" -v m3="$MTE3_TIME_US" 'BEGIN{printf "%.3f", m2+m3}')
    print_metric "Total MTE Time" "$WHITE" "${TOTAL_MTE_US} μs"
    
    MTE_EXEC_PERCENT=$(awk -v mte="$TOTAL_MTE_US" -v exec="$TASK_DURATION" \
        'BEGIN{printf "%.2f", (mte/exec)*100}')
    print_metric "MTE / Execution Time" "$WHITE" "${MTE_EXEC_PERCENT}%"
else
    echo -e "${YELLOW}MTE timing not available${NC}"
    echo "Run profiling with: --aic-metrics=PipeUtilization"
fi

# ==============================================================================
# MTE DATA VOLUMES - FROM MEMORYACCESS
# ==============================================================================

print_header "MTE DATA TRANSFER VOLUMES"

echo "Data volumes moved by MTE operations."
echo "Source: MemoryAccess metric - Table 8 (GM_to_UB_datas, UB_to_GM_datas in KB)"
echo ""

GM_TO_UB_KB=""
UB_TO_GM_KB=""

if [ ! -z "$MEMACCESS_OP_FILE" ] && [ -f "$MEMACCESS_OP_FILE" ]; then
    MEMACCESS_KERNEL_LINE=$(tail -n +2 "$MEMACCESS_OP_FILE" | grep "$KERNEL_NAME" | head -n 1)
    
    if [ ! -z "$MEMACCESS_KERNEL_LINE" ]; then
        MEMACCESS_HEADER=$(head -n 1 "$MEMACCESS_OP_FILE")
        TOTAL_COLS=$(echo "$MEMACCESS_HEADER" | awk -F',' '{print NF}')
        
        # Find both aic_ and aiv_ columns
        AIC_GM_TO_UB_COL=0
        AIV_GM_TO_UB_COL=0
        AIC_UB_TO_GM_COL=0
        AIV_UB_TO_GM_COL=0
        
        for i in $(seq 1 $TOTAL_COLS); do
            COL_NAME=$(echo "$MEMACCESS_HEADER" | cut -d',' -f$i | tr -d ' \r\n' | tr '[:upper:]' '[:lower:]')
            
            [[ "$COL_NAME" =~ ^aic_gm_to_ub_datas ]] && AIC_GM_TO_UB_COL=$i
            [[ "$COL_NAME" =~ ^aiv_gm_to_ub_datas ]] && AIV_GM_TO_UB_COL=$i
            [[ "$COL_NAME" =~ ^aic_ub_to_gm_datas ]] && AIC_UB_TO_GM_COL=$i
            [[ "$COL_NAME" =~ ^aiv_ub_to_gm_datas ]] && AIV_UB_TO_GM_COL=$i
        done
        
        # Extract both values
        AIC_GM_TO_UB=""
        AIV_GM_TO_UB=""
        AIC_UB_TO_GM=""
        AIV_UB_TO_GM=""
        
        [ $AIC_GM_TO_UB_COL -gt 0 ] && AIC_GM_TO_UB=$(echo "$MEMACCESS_KERNEL_LINE" | cut -d',' -f$AIC_GM_TO_UB_COL | tr -d ' \r\n')
        [ $AIV_GM_TO_UB_COL -gt 0 ] && AIV_GM_TO_UB=$(echo "$MEMACCESS_KERNEL_LINE" | cut -d',' -f$AIV_GM_TO_UB_COL | tr -d ' \r\n')
        [ $AIC_UB_TO_GM_COL -gt 0 ] && AIC_UB_TO_GM=$(echo "$MEMACCESS_KERNEL_LINE" | cut -d',' -f$AIC_UB_TO_GM_COL | tr -d ' \r\n')
        [ $AIV_UB_TO_GM_COL -gt 0 ] && AIV_UB_TO_GM=$(echo "$MEMACCESS_KERNEL_LINE" | cut -d',' -f$AIV_UB_TO_GM_COL | tr -d ' \r\n')
        
        # Combine values intelligently
        GM_TO_UB_KB=$(combine_values "$AIC_GM_TO_UB" "$AIV_GM_TO_UB")
        UB_TO_GM_KB=$(combine_values "$AIC_UB_TO_GM" "$AIV_UB_TO_GM")
    fi
fi

if [ ! -z "$GM_TO_UB_KB" ] && (( $(awk -v k="$GM_TO_UB_KB" 'BEGIN{print (k > 0)}') )); then
    print_section "Data Transfer Volumes"
    
    GM_TO_UB_MB=$(calc "$GM_TO_UB_KB / 1024")
    GM_TO_UB_GB=$(calc_precise "$GM_TO_UB_KB / 1048576")
    UB_TO_GM_MB=$(calc "$UB_TO_GM_KB / 1024")
    UB_TO_GM_GB=$(calc_precise "$UB_TO_GM_KB / 1048576")
    TOTAL_TRANSFER_KB=$(awk -v r="$GM_TO_UB_KB" -v w="$UB_TO_GM_KB" 'BEGIN{printf "%.2f", r+w}')
    TOTAL_TRANSFER_MB=$(calc "$TOTAL_TRANSFER_KB / 1024")
    
    echo "GM → UB (Read)"
    print_metric "  Data transferred" "$GREEN" "${GM_TO_UB_KB} KB (${GM_TO_UB_MB} MB)"
    echo ""
    
    echo "UB → GM (Write)"
    print_metric "  Data transferred" "$CYAN" "${UB_TO_GM_KB} KB (${UB_TO_GM_MB} MB)"
    echo ""
    
    print_metric "Total Data Transferred" "$WHITE" "${TOTAL_TRANSFER_KB} KB (${TOTAL_TRANSFER_MB} MB)"
    
    # Calculate read:write ratio
    if (( $(awk -v w="$UB_TO_GM_KB" 'BEGIN{print (w > 0)}') )); then
        DATA_RATIO=$(calc "$GM_TO_UB_KB / $UB_TO_GM_KB")
        print_metric "Read:Write Ratio" "$WHITE" "${DATA_RATIO}:1"
    fi
    
    # Calculate effective bandwidth if we have timing
    if [ ! -z "$MTE2_TIME_US" ] && (( $(awk -v t="$MTE2_TIME_US" 'BEGIN{print (t > 0)}') )); then
        echo ""
        print_section "Effective Transfer Bandwidth"
        
        MTE2_BW=$(awk -v kb="$GM_TO_UB_KB" -v us="$MTE2_TIME_US" \
            'BEGIN{printf "%.2f", (kb / us) * 1000 / 1024}')
        print_metric "GM → UB Bandwidth" "$GREEN" "${MTE2_BW} GB/s"
        
        if (( $(awk -v t="$MTE3_TIME_US" 'BEGIN{print (t > 0)}') )); then
            MTE3_BW=$(awk -v kb="$UB_TO_GM_KB" -v us="$MTE3_TIME_US" \
                'BEGIN{printf "%.2f", (kb / us) * 1000 / 1024}')
            print_metric "UB → GM Bandwidth" "$CYAN" "${MTE3_BW} GB/s"
        fi
    fi
else
    echo -e "${YELLOW}MTE data volumes not available${NC}"
    echo "Run profiling with: --aic-metrics=MemoryAccess"
fi

# ==============================================================================
# UB BANDWIDTH - FROM MEMORY METRIC
# ==============================================================================

print_header "UNIFIED BUFFER (UB) BANDWIDTH"

echo "Bandwidth between compute engines and Unified Buffer."
echo "Source: Memory metric - Table 4 (ub_read_bw, ub_write_bw in GB/s)"
echo ""

UB_READ_BW=""
UB_WRITE_BW=""

if [ ! -z "$MEMORY_OP_FILE" ] && [ -f "$MEMORY_OP_FILE" ]; then
    MEMORY_KERNEL_LINE=$(tail -n +2 "$MEMORY_OP_FILE" | grep "$KERNEL_NAME" | head -n 1)
    
    if [ ! -z "$MEMORY_KERNEL_LINE" ]; then
        MEMORY_HEADER=$(head -n 1 "$MEMORY_OP_FILE")
        TOTAL_COLS=$(echo "$MEMORY_HEADER" | awk -F',' '{print NF}')
        
        # Find both aic_ and aiv_ columns
        AIC_UB_READ_COL=0
        AIV_UB_READ_COL=0
        AIC_UB_WRITE_COL=0
        AIV_UB_WRITE_COL=0
        
        for i in $(seq 1 $TOTAL_COLS); do
            COL_NAME=$(echo "$MEMORY_HEADER" | cut -d',' -f$i | tr -d ' \r\n' | tr '[:upper:]' '[:lower:]')
            
            [[ "$COL_NAME" =~ ^aic_ub_read_bw ]] && AIC_UB_READ_COL=$i
            [[ "$COL_NAME" =~ ^aiv_ub_read_bw ]] && AIV_UB_READ_COL=$i
            [[ "$COL_NAME" =~ ^aic_ub_write_bw ]] && AIC_UB_WRITE_COL=$i
            [[ "$COL_NAME" =~ ^aiv_ub_write_bw ]] && AIV_UB_WRITE_COL=$i
        done
        
        # Extract both values
        AIC_UB_READ=""
        AIV_UB_READ=""
        AIC_UB_WRITE=""
        AIV_UB_WRITE=""
        
        [ $AIC_UB_READ_COL -gt 0 ] && AIC_UB_READ=$(echo "$MEMORY_KERNEL_LINE" | cut -d',' -f$AIC_UB_READ_COL | tr -d ' \r\n')
        [ $AIV_UB_READ_COL -gt 0 ] && AIV_UB_READ=$(echo "$MEMORY_KERNEL_LINE" | cut -d',' -f$AIV_UB_READ_COL | tr -d ' \r\n')
        [ $AIC_UB_WRITE_COL -gt 0 ] && AIC_UB_WRITE=$(echo "$MEMORY_KERNEL_LINE" | cut -d',' -f$AIC_UB_WRITE_COL | tr -d ' \r\n')
        [ $AIV_UB_WRITE_COL -gt 0 ] && AIV_UB_WRITE=$(echo "$MEMORY_KERNEL_LINE" | cut -d',' -f$AIV_UB_WRITE_COL | tr -d ' \r\n')
        
        # Combine values intelligently
        UB_READ_BW=$(combine_values "$AIC_UB_READ" "$AIV_UB_READ")
        UB_WRITE_BW=$(combine_values "$AIC_UB_WRITE" "$AIV_UB_WRITE")
    fi
fi

if [ ! -z "$UB_READ_BW" ]; then
    print_section "UB Bandwidth"
    
    print_metric "UB Read Bandwidth" "$GREEN" "${UB_READ_BW} GB/s"
    print_metric "UB Write Bandwidth" "$CYAN" "${UB_WRITE_BW} GB/s"
    
    TOTAL_UB_BW=$(awk -v r="$UB_READ_BW" -v w="$UB_WRITE_BW" 'BEGIN{printf "%.2f", r+w}')
    print_metric "Total UB Bandwidth" "$WHITE" "${TOTAL_UB_BW} GB/s"
else
    echo -e "${YELLOW}UB bandwidth not available${NC}"
    echo "Run profiling with: --aic-metrics=Memory"
fi

# ==============================================================================
# HBM BANDWIDTH
# ==============================================================================

print_header "HBM BANDWIDTH MEASUREMENT"

echo "Hardware-measured bandwidth at Global Memory interface."
echo "Source: Memory metric (hbm_*.csv)"
echo ""

TOTAL_BW=""
UTILIZATION=""

if [ -f "$HBM_FILE" ]; then
    HBM_DATA=$(tail -n +2 "$HBM_FILE" | awk -F',' '
        BEGIN { read_sum=0; write_sum=0; count=0; read_max=0; write_max=0 }
        {
            for (i=1; i<=NF; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i)
            
            read_mb = $3+0
            write_mb = $4+0
            read_gb = read_mb / 1024.0
            write_gb = write_mb / 1024.0
            
            if (read_gb > 0 || write_gb > 0) {
                read_sum += read_gb
                write_sum += write_gb
                count++
                if (read_gb > read_max) read_max = read_gb
                if (write_gb > write_max) write_max = write_gb
            }
        }
        END {
            if (count > 0) {
                printf "%.6f|%.6f|%d|%.6f|%.6f\n", 
                       read_sum/count, write_sum/count, count, read_max, write_max
            }
        }
    ')
    
    if [ ! -z "$HBM_DATA" ]; then
        AVG_READ=$(echo $HBM_DATA | cut -d'|' -f1)
        AVG_WRITE=$(echo $HBM_DATA | cut -d'|' -f2)
        SAMPLES=$(echo $HBM_DATA | cut -d'|' -f3)
        MAX_READ=$(echo $HBM_DATA | cut -d'|' -f4)
        MAX_WRITE=$(echo $HBM_DATA | cut -d'|' -f5)
        
        print_section "Bandwidth Statistics"
        
        printf "%-35s %18s %18s\n" "Metric" "Read" "Write"
        echo "$(printf '─%.0s' {1..72})"
        printf "%-35s %15.3f GB/s %15.3f GB/s\n" "Average Bandwidth" "$AVG_READ" "$AVG_WRITE"
        printf "%-35s %15.3f GB/s %15.3f GB/s\n" "Peak Bandwidth" "$MAX_READ" "$MAX_WRITE"
        echo ""
        
        TOTAL_BW=$(calc "$AVG_READ + $AVG_WRITE")
        THEORETICAL_PEAK=1200
        UTILIZATION=$(calc "($TOTAL_BW * 100.0) / $THEORETICAL_PEAK")
        
        print_metric "Total Bandwidth" "$WHITE" "${TOTAL_BW} GB/s"
        print_metric "Theoretical Peak (910B)" "$GRAY" "${THEORETICAL_PEAK} GB/s"
        print_metric "Utilization" "$WHITE" "${UTILIZATION}%"
    fi
else
    echo -e "${YELLOW}HBM bandwidth data not available${NC}"
    echo "Run profiling with: --aic-metrics=Memory"
fi

# ==============================================================================
# L2 CACHE - FROM L2CACHE METRIC OP_SUMMARY
# ==============================================================================

print_header "L2 CACHE PERFORMANCE"

echo "L2 cache between UB and GM - reduces memory access latency."
echo "Source: L2Cache metric op_summary - Table 9 (write_cache_hit, read_cache_hit, etc.)"
echo ""

HIT_RATE=""
TOTAL_CACHE_HITS=0
TOTAL_CACHE_MISSES=0

if [ ! -z "$L2_OP_FILE" ] && [ -f "$L2_OP_FILE" ]; then
    L2_KERNEL_LINE=$(tail -n +2 "$L2_OP_FILE" | grep "$KERNEL_NAME" | head -n 1)
    
    if [ ! -z "$L2_KERNEL_LINE" ]; then
        L2_HEADER=$(head -n 1 "$L2_OP_FILE")
        L2_COLS=$(echo "$L2_HEADER" | awk -F',' '{print NF}')
        
        # Sum both aic_ and aiv_ cache hits/misses
        for i in $(seq 1 $L2_COLS); do
            COL_NAME=$(echo "$L2_HEADER" | cut -d',' -f$i | tr -d ' \r\n' | tr '[:upper:]' '[:lower:]')
            COL_VALUE=$(echo "$L2_KERNEL_LINE" | cut -d',' -f$i | tr -d ' \r\n')
            
            # Match patterns for both aic_ and aiv_
            if [[ "$COL_NAME" =~ (aic|aiv)_(write|r[0-9]+_read)_cache_hit$ ]]; then
                [ ! -z "$COL_VALUE" ] && [ "$COL_VALUE" != "N/A" ] && \
                    TOTAL_CACHE_HITS=$(awk -v h="$TOTAL_CACHE_HITS" -v v="$COL_VALUE" 'BEGIN{printf "%.0f", h+v}')
            fi
            
            if [[ "$COL_NAME" =~ (aic|aiv)_(write|r[0-9]+_read)_cache_miss ]]; then
                [ ! -z "$COL_VALUE" ] && [ "$COL_VALUE" != "N/A" ] && \
                    TOTAL_CACHE_MISSES=$(awk -v m="$TOTAL_CACHE_MISSES" -v v="$COL_VALUE" 'BEGIN{printf "%.0f", m+v}')
            fi
        done
        
        if [ $TOTAL_CACHE_HITS -gt 0 ] || [ $TOTAL_CACHE_MISSES -gt 0 ]; then
            print_section "Cache Statistics"
            
            [ $TOTAL_CACHE_HITS -gt 0 ] && print_metric "Cache Hits" "$GREEN" "$(printf "%'d" $TOTAL_CACHE_HITS) accesses"
            [ $TOTAL_CACHE_MISSES -gt 0 ] && print_metric "Cache Misses" "$YELLOW" "$(printf "%'d" $TOTAL_CACHE_MISSES) accesses"
            
            TOTAL_ACCESSES=$(awk -v h="$TOTAL_CACHE_HITS" -v m="$TOTAL_CACHE_MISSES" 'BEGIN{printf "%.0f", h+m}')
            [ $TOTAL_ACCESSES -gt 0 ] && print_metric "Total Accesses" "$WHITE" "$(printf "%'d" $TOTAL_ACCESSES)"
            
            if [ $TOTAL_ACCESSES -gt 0 ]; then
                HIT_RATE=$(calc "($TOTAL_CACHE_HITS * 100.0) / $TOTAL_ACCESSES")
                print_metric "Hit Rate" "$GREEN" "${HIT_RATE}%"
            fi
        else
            echo -e "${YELLOW}No L2 cache hit/miss data for this kernel${NC}"
        fi
    else
        echo -e "${YELLOW}Kernel not found in L2Cache op_summary${NC}"
    fi
else
    echo -e "${YELLOW}L2 cache data not available${NC}"
    echo "Run profiling with: --aic-metrics=L2Cache"
fi

# ==============================================================================
# DMA
# ==============================================================================

print_header "HOST-DEVICE DMA"

echo "Data transfers between host CPU memory and device Global Memory."
echo ""

if [ -f "$API_FILE" ]; then
    MEMCPY_LINE=$(grep "MemcpyAsync" "$API_FILE" 2>/dev/null)
    
    if [ ! -z "$MEMCPY_LINE" ]; then
        MEM_TIME=$(echo "$MEMCPY_LINE" | cut -d',' -f4)
        MEM_COUNT=$(echo "$MEMCPY_LINE" | cut -d',' -f5)
        MEM_AVG=$(echo "$MEMCPY_LINE" | cut -d',' -f6)
        
        print_metric "DMA Operations" "$GREEN" "${MEM_COUNT} transfers"
        print_metric "Total DMA Time" "$CYAN" "${MEM_TIME} μs"
        print_metric "Average per Transfer" "$WHITE" "${MEM_AVG} μs"
    else
        echo "No DMA operations detected"
    fi
fi

# ==============================================================================
# SUMMARY
# ==============================================================================

print_header "SUMMARY"

echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║${NC}  ${BOLD}KERNEL EFFICIENCY SUMMARY${NC}                                           ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}╠════════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${CYAN}║${NC}  ${BOLD}KERNEL${NC}                                                              ${BOLD}${CYAN}║${NC}"
printf "${BOLD}${CYAN}║${NC}    %-66s ${BOLD}${CYAN}║${NC}\n" "${KERNEL_NAME:0:66}"
echo -e "${BOLD}${CYAN}║${NC}                                                                        ${BOLD}${CYAN}║${NC}"

# Timing
echo -e "${BOLD}${CYAN}║${NC}  ${BOLD}TIMING${NC}                                                              ${BOLD}${CYAN}║${NC}"
printf "${BOLD}${CYAN}║${NC}    Execution Time:       %15s μs  (%6.2f ms)          ${BOLD}${CYAN}║${NC}\n" "$TASK_DURATION" "$EXEC_MS"
printf "${BOLD}${CYAN}║${NC}    Wait Time:            %15s μs  (%6.2f ms)          ${BOLD}${CYAN}║${NC}\n" "$WAIT_TIME" "$WAIT_MS"
printf "${BOLD}${CYAN}║${NC}    Execution Efficiency: %15.2f%%                           ${BOLD}${CYAN}║${NC}\n" "$EXEC_PERCENT"

# MTE Timing
if [ ! -z "$MTE2_TIME_US" ]; then
    echo -e "${BOLD}${CYAN}║${NC}                                                                        ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${BOLD}MTE TIMING${NC}                                                         ${BOLD}${CYAN}║${NC}"
    printf "${BOLD}${CYAN}║${NC}    GM → UB (MTE2):       %15s μs                        ${BOLD}${CYAN}║${NC}\n" "$MTE2_TIME_US"
    printf "${BOLD}${CYAN}║${NC}    UB → GM (MTE3):       %15s μs                        ${BOLD}${CYAN}║${NC}\n" "$MTE3_TIME_US"
    [ ! -z "$TOTAL_MTE_US" ] && printf "${BOLD}${CYAN}║${NC}    Total MTE:            %15s μs                        ${BOLD}${CYAN}║${NC}\n" "$TOTAL_MTE_US"
fi

# Data Volumes
if [ ! -z "$GM_TO_UB_KB" ] && (( $(awk -v k="$GM_TO_UB_KB" 'BEGIN{print (k > 0)}') )); then
    echo -e "${BOLD}${CYAN}║${NC}                                                                        ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${BOLD}DATA VOLUMES${NC}                                                       ${BOLD}${CYAN}║${NC}"
    printf "${BOLD}${CYAN}║${NC}    GM → UB (Read):       %15s KB  (%6.2f MB)          ${BOLD}${CYAN}║${NC}\n" "$GM_TO_UB_KB" "$GM_TO_UB_MB"
    printf "${BOLD}${CYAN}║${NC}    UB → GM (Write):      %15s KB  (%6.2f MB)          ${BOLD}${CYAN}║${NC}\n" "$UB_TO_GM_KB" "$UB_TO_GM_MB"
fi

# UB Bandwidth
if [ ! -z "$UB_READ_BW" ]; then
    echo -e "${BOLD}${CYAN}║${NC}                                                                        ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${BOLD}UB BANDWIDTH${NC}                                                       ${BOLD}${CYAN}║${NC}"
    printf "${BOLD}${CYAN}║${NC}    Read:                 %15s GB/s                       ${BOLD}${CYAN}║${NC}\n" "$UB_READ_BW"
    printf "${BOLD}${CYAN}║${NC}    Write:                %15s GB/s                       ${BOLD}${CYAN}║${NC}\n" "$UB_WRITE_BW"
fi

# HBM Bandwidth
if [ ! -z "$TOTAL_BW" ]; then
    echo -e "${BOLD}${CYAN}║${NC}                                                                        ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${BOLD}HBM BANDWIDTH${NC}                                                      ${BOLD}${CYAN}║${NC}"
    printf "${BOLD}${CYAN}║${NC}    Total Bandwidth:      %15.2f GB/s                       ${BOLD}${CYAN}║${NC}\n" "$TOTAL_BW"
    printf "${BOLD}${CYAN}║${NC}    Utilization:          %15.2f%%                            ${BOLD}${CYAN}║${NC}\n" "$UTILIZATION"
fi

# L2 Cache
if [ ! -z "$HIT_RATE" ]; then
    echo -e "${BOLD}${CYAN}║${NC}                                                                        ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${BOLD}L2 CACHE${NC}                                                           ${BOLD}${CYAN}║${NC}"
    printf "${BOLD}${CYAN}║${NC}    Hit Rate:             %15s%%                            ${BOLD}${CYAN}║${NC}\n" "$HIT_RATE"
    [ $TOTAL_CACHE_HITS -gt 0 ] && printf "${BOLD}${CYAN}║${NC}    Cache Hits:           %'18d accesses                 ${BOLD}${CYAN}║${NC}\n" "$TOTAL_CACHE_HITS"
    [ $TOTAL_CACHE_MISSES -gt 0 ] && printf "${BOLD}${CYAN}║${NC}    Cache Misses:         %'18d accesses                 ${BOLD}${CYAN}║${NC}\n" "$TOTAL_CACHE_MISSES"
fi

echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════════════╝${NC}"

echo ""
echo -e "${BOLD}Analysis complete.${NC}"
echo ""
