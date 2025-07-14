#!/bin/bash

# Gremlin Configuration
export GREMLIN_TEAM_ID="438c58ec-03db-47ac-8c58-ec03db67ac42"
export GREMLIN_TEAM_SECRET="cb9beaeb-d22b-4008-9bea-ebd22b70086c"
export GREMLIN_SCENARIO_ID="d6e344d9-d632-4d86-a344-d9d632ad8664"

# Check if Gremlin CLI is installed
if ! command -v gremlin &> /dev/null; then
    echo "Gremlin CLI is not installed. Please install it first."
    exit 1
fi

# Authenticate with Gremlin CLI
gremlin auth login --token "$GREMLIN_TEAM_ID:$GREMLIN_TEAM_SECRET"
if [ $? -ne 0 ]; then
    echo "Failed to authenticate with Gremlin CLI"
    exit 1
fi

# Script Configuration
OUTPUT_DIR="blackhole_metrics_$(date +%Y%m%d_%H%M%S)"
DURATION_MINUTES=3
INTERVAL_SECONDS=15

# Target configuration
TARGET_NAMESPACE="otel-demo"
TARGET_DEPLOYMENT="frontend"

# Prometheus instances configuration
PROMETHEUS_INSTANCES=("monitoring" "otel-demo" "istio-system")
PROMETHEUS_URLS=("localhost:9090" "localhost:9091" "localhost:9092")

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Initialize metrics files
METRICS_FILE="$OUTPUT_DIR/metrics.csv"
METRICS_SUMMARY="$OUTPUT_DIR/summary.csv"

# Initialize CSV headers if files don't exist
[ ! -f "$METRICS_FILE" ] && echo "phase,instance,metric,labels,value" > "$METRICS_FILE"
[ ! -f "$METRICS_SUMMARY" ] && echo "phase,instance,query,result_count" > "$METRICS_SUMMARY"

get_prometheus_url() {
    local instance="$1"
    for i in "${!PROMETHEUS_INSTANCES[@]}"; do
        if [ "${PROMETHEUS_INSTANCES[$i]}" = "$instance" ]; then
            echo "${PROMETHEUS_URLS[$i]}"
            return 0
        fi
    done
    return 1
}

mkdir -p "$OUTPUT_DIR"
EXPERIMENT_LOG="$OUTPUT_DIR/experiment.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local level=${2:-INFO}
    local color="\033[0m"
    local reset="\033[0m"
    
    case "${level}" in
        "ERROR") color="\033[0;31m" ;;
        "WARN") color="\033[0;33m" ;;
        "INFO") color="\033[0;36m" ;;
        "SUCCESS") color="\033[0;32m" ;;
    esac
    
    # Only log if we have a message
    if [ -n "$1" ]; then
        echo -e "[${timestamp}] ${color}[${level}]${reset} $1" >> "$EXPERIMENT_LOG"
        echo -e "[${timestamp}] ${color}[${level}]${reset} $1"
    fi
}

collect_metrics() {
    local phase=$1
    local instance=$2
    local prometheus_url=$(get_prometheus_url "$instance")
    
    if [ -z "$prometheus_url" ]; then
        log "No URL found for $instance" "ERROR"
        return 1
    fi
    
    log "=== Collecting $phase metrics from $instance ===" "INFO"
    
    # Define queries based on instance
    local queries=()
    case "$instance" in
        "monitoring")
            queries=("up" "container_memory_usage_bytes" "container_cpu_usage_seconds_total")
            ;;
        "otel-demo")
            queries=("up" "process_cpu_seconds_total" "process_resident_memory_bytes")
            ;;
        "istio-system")
            queries=(
                "up" 
                "istio_requests_total" 
                "istio_request_duration_milliseconds_count"
                "histogram_quantile(0.95, sum(rate(istio_request_duration_milliseconds_bucket[1m])) by (le, destination_service))"
                "sum(rate(istio_requests_total{response_code=~'5..'}[1m])) by (source_workload, destination_workload)"
            )
            ;;
        *)
            log "No queries defined for instance: $instance" "WARN"
            return 0
            ;;
    esac
    
    # Run each query
    local success=true
    for query in "${queries[@]}"; do
        if ! run_prometheus_query "$instance" "$query" "$phase"; then
            log "Query failed: $query" "ERROR"
            success=false
        fi
    done
    
    if ! $success; then
        log "Some queries failed for $instance" "WARN"
        return 1
    fi
    
    return 0
}

run_prometheus_query() {
    local prometheus_instance=$1
    local query=$2
    local phase=$3
    local retry_count=0
    local max_retries=2
    local response=""
    local http_status=0
    local result=0
    local tmpfile=$(mktemp)
    
    # Get the Prometheus URL for this instance
    local prometheus_url=$(get_prometheus_url "$prometheus_instance")
    if [ -z "$prometheus_url" ]; then
        log "No URL found for instance: $prometheus_instance" "ERROR"
        return 1
    fi
    
    # Sanitize query for filename
    local query_sanitized=$(echo "$query" | tr -dc 'a-zA-Z0-9_' | head -c 20)
    local ts=$(date +%s)
    
    # Clean the query
    query=$(echo "$query" | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # URL encode the query
    local encoded_query=$(echo -n "$query" | jq -sRr @uri)
    local prom_url="http://$prometheus_url/api/v1/query?query=${encoded_query}"
    
    log "Querying ${prometheus_instance}: ${query}" "INFO"
    
    while [ $retry_count -le $max_retries ]; do
        # Use a temporary file to capture both response and status code
        local curl_cmd="curl -v -s -o \"$tmpfile\" -w \"%{http_code}\" --connect-timeout 5 --max-time 10 \"$prom_url\""
        log "   Running: $curl_cmd"
        
        # Run curl and capture response
        http_status=$(eval $curl_cmd 2>/dev/null)
        response=$(cat "$tmpfile" 2>/dev/null)
        
        # Save response for debugging with timestamp and sanitized query
        local debug_file="${OUTPUT_DIR}/${ts}_${prometheus_instance}_${query_sanitized}_${retry_count}.json"
        echo "$response" > "$debug_file"
        log "Debug output: $debug_file" "DEBUG"
        
        if [[ "$http_status" == "200" ]]; then
            local result_count=$(echo "$response" | jq '.data.result | length' 2>/dev/null || echo 0)
            echo "$phase,$prometheus_instance,$query,$result_count" >> "$METRICS_SUMMARY"
            
            # Process results if any
            if [[ $result_count -gt 0 ]]; then
                # First extract all metrics to a temporary file
                local tmp_metrics=$(mktemp)
                echo "$response" | jq -c '.data.result[]' 2>/dev/null > "$tmp_metrics"
                
                # Process each metric using a simpler jq approach
                while read -r metric_data; do
                    # Extract metric name
                    local metric_name=$(echo "$metric_data" | jq -r '.metric.__name__ // empty' 2>/dev/null)
                    # Extract labels as a simple JSON object
                    local labels=$(echo "$metric_data" | jq -c '.metric | del(.__name__)' 2>/dev/null)
                    # Extract the metric value
                    local value=$(echo "$metric_data" | jq -r '.value[1] // empty' 2>/dev/null)
                    
                    if [ -n "$metric_name" ] && [ -n "$value" ]; then
                        echo "$phase,$prometheus_instance,$metric_name,$labels,$value" >> "$METRICS_FILE"
                    fi
                done < "$tmp_metrics"
                rm -f "$tmp_metrics"
                
                log "✓ Found $result_count metrics" "SUCCESS"
                rm -f "$tmpfile"
                return 0
            else
                log "No results found" "WARN"
                rm -f "$tmpfile"
                return 2
            fi
        else
            log "HTTP $http_status: ${response:0:100}..." "WARN"
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -le $max_retries ]; then
            sleep 1
        fi
    done

    # Process the successful response
    local result_count=$(echo "$response" | jq -r '.data.result | length' 2>/dev/null || echo "0")

    # Extract and log the results
    local result
    local parse_attempt=0
    
    # Try different parsing approaches
    while [ $parse_attempt -lt 2 ]; do
        if [ $parse_attempt -eq 0 ]; then
            # Try the original parsing approach first
            result=$(echo "$response" | jq -r '.data.result[] | 
                [.metric.__name__ + "{" + 
                (.metric | to_entries | map(select(.key != "__name__" and .value != "")) | 
                map("\(.key)=\\"\(.value)\\"") | join(",")) + "}", 
                .value[1]] | @tsv' 2>/dev/null)
        else
            # Fallback to a simpler approach if the first one fails
            result=$(echo "$response" | jq -r '.data.result[] | 
                [.metric.__name__, .value[1]] | @tsv' 2>/dev/null)
        fi
        
        if [ $? -eq 0 ] && [ -n "$result" ]; then
            break
        fi
        parse_attempt=$((parse_attempt + 1))
    done
    
    if [ -n "$result" ]; then
        while IFS=$'\t' read -r labels value; do
            # Format the display
            local metric_name="${labels%%\{*}"  # Get everything before the first {
            local display_labels="{${labels#*\{}}"  # Get everything after the first {
            
            # Clean up display labels if they're empty
            if [ "$display_labels" = "{}" ]; then
                display_labels="{}"
            fi
            
            # Format the value (handle both integers and floats)
            local display_value
            if [[ "$value" =~ ^[0-9]+$ ]]; then
                display_value="$value"  # Integer
            elif [[ "$value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                display_value=$(printf "%.2f" "$value" 2>/dev/null || echo "$value")
            else
                display_value="$value"  # Non-numeric value
            fi
            
            # Set color based on phase
            case "$phase" in
                baseline*) phase_color="${GREEN}" ;;
                blackhole*) phase_color="${RED}" ;;
                recovery*) phase_color="${YELLOW}" ;;
                *) phase_color="${NC}" ;;
            esac
            
            # Log to console and file
            printf "${phase_color}%-40s %-30s %12s${NC}\n" "$metric_name" "${display_labels:0:30}" "$display_value"
            echo "$phase,$prometheus_instance,$metric_name,$display_labels,$display_value" >> "$METRICS_FILE"
        done <<< "$result"
        
        # Log summary to file
        echo "$phase,$prometheus_instance,$query,$result_count" >> "$METRICS_SUMMARY"
        log "✅ Successfully processed $result_count results"
        return 0
    else
        log "WARN: Failed to parse query results after $parse_attempt attempts" "WARN"
        log "Sample response: $(echo "$response" | head -c 200)..." "WARN"
        return 1
    fi
}

generate_summary_report() {
    echo -e "\n${BOLD}=== METRICS SUMMARY ===${NC}\n"

    # Read metrics from the summary CSV file
    local summary_file="$OUTPUT_DIR/summary.csv"
    if [ ! -f "$summary_file" ]; then
        log "No summary file found at $summary_file" "ERROR"
        return 1
    fi

    # Print header
    echo -e "${BOLD}PHASE${NC}\t${BOLD}INSTANCE${NC}\t${BOLD}QUERY${NC}\t${BOLD}RESULT_COUNT${NC}"
    echo -e "${BOLD}-----${NC}\t${BOLD}--------${NC}\t${BOLD}-----${NC}\t${BOLD}------------${NC}"

    # Skip header line and process each line
    tail -n +2 "$summary_file" | while IFS=, read -r phase instance query result_count; do
        # Remove quotes if present
        phase=$(echo "$phase" | tr -d '"')
        instance=$(echo "$instance" | tr -d '"')
        query=$(echo "$query" | tr -d '"')
        result_count=$(echo "$result_count" | tr -d '"')
        
        # Color code based on result count
        if [[ "$result_count" -gt 0 ]]; then
            echo -e "${GREEN}$phase\t$instance\t$query\t$result_count${NC}"
        else
            echo -e "${RED}$phase\t$instance\t$query\t$result_count${NC}"
        fi
    done
}

print_human_time() {
    local t=$1
    if date -j -f "%s" "$t" "+%H:%M:%S" >/dev/null 2>&1; then
        date -j -f "%s" "$t" "+%H:%M:%S"
    else
        date -r "$t" "+%H:%M:%S"
    fi
}

main() {
    # Initialize variables
    local baseline_start
    baseline_start=$(date +%s)
    
    # Validate required environment variables
    if [ -z "$GREMLIN_TEAM_ID" ] || [ -z "$GREMLIN_TEAM_SECRET" ]; then
        log "Error: GREMLIN_TEAM_ID and GREMLIN_TEAM_SECRET must be set" "ERROR"
        exit 1
    fi
    
    # Create output directory if it doesn't exist
    mkdir -p "$OUTPUT_DIR"
    
    # Initialize output files
    echo "phase,instance,metric,labels,value" > "$METRICS_FILE"
    echo "phase,instance,query,result_count" > "$METRICS_SUMMARY"
    
    log "=== Starting Prometheus Metrics Collection ===" "INFO"
    log "Output directory: $OUTPUT_DIR" "INFO"
    log "Target namespace: $TARGET_NAMESPACE" "INFO"
    log "Target deployment: $TARGET_DEPLOYMENT" "INFO"
    
    # Collect baseline metrics from each instance
    local success=true
    for instance in "${PROMETHEUS_INSTANCES[@]}"; do
        log "\nCollecting baseline metrics from $instance..." "INFO"
        if ! collect_metrics "baseline" "$instance"; then
            log "Failed to collect baseline metrics from $instance" "ERROR"
            success=false
        fi
    done
    
    # Report baseline collection status
    if ! $success; then
        log "\n⚠️  Some baseline metrics could not be collected. Check logs above for details." "WARN"
    else
        log "\n✅ Successfully collected all baseline metrics" "SUCCESS"
    fi
    
    # Run Gremlin latency experiment
    log "\n=== Starting Gremlin Latency Experiment ===" "INFO"
    local gremlin_attack_id
    gremlin_attack_id=$(run_gremlin_scenario)
    
    if [ -n "$gremlin_attack_id" ]; then
        log "✅ Started Gremlin attack with ID: $gremlin_attack_id" "SUCCESS"
        
        # Wait for experiment duration
        log "⏳ Running experiment for $DURATION_MINUTES minutes..." "INFO"
        sleep $((DURATION_MINUTES * 60))
        
        # Collect metrics during attack
        log "\n=== Collecting metrics during attack ===" "INFO"
        for instance in "${PROMETHEUS_INSTANCES[@]}"; do
            log "\nCollecting attack metrics from $instance..." "INFO"
            collect_metrics "attack" "$instance"
        done
        
        # Stop the Gremlin attack
        log "\n=== Stopping Gremlin attack ===" "INFO"
        stop_gremlin_attack "$gremlin_attack_id"
        
        # Wait for recovery period
        log "\n=== Waiting for recovery period ($DURATION_MINUTES minutes) ===" "INFO"
        sleep $((DURATION_MINUTES * 60))
        
        # Collect recovery metrics
        log "\n=== Collecting recovery metrics ===" "INFO"
        for instance in "${PROMETHEUS_INSTANCES[@]}"; do
            log "\nCollecting recovery metrics from $instance..." "INFO"
            collect_metrics "recovery" "$instance"
        done
    else
        log "❌ Failed to start Gremlin attack. Cannot proceed with experiment." "ERROR"
    fi
    
    # Generate final report
    log "\n=== Experiment Complete ===" "INFO"
    log "Results saved to: $OUTPUT_DIR" "INFO"
    log "📊 Metrics CSV: $PWD/$METRICS_FILE" "INFO"
    log "📊 Summary CSV: $PWD/$METRICS_SUMMARY" "INFO"
    log "📜 Log file: $PWD/$EXPERIMENT_LOG" "INFO"
    log ""
    log "=== Experiment Summary ===" "INFO"
    log "Start time: $(print_human_time $baseline_start)" "INFO"
    log "End time:   $(print_human_time $(date +%s))" "INFO"
    log "Duration:   $(($(date +%s) - baseline_start)) seconds" "INFO"
    log "=========================" "INFO"
    exit 0
}



# Function definitions
run_gremlin_scenario() {
    log "🚀 Starting Gremlin scenario $GREMLIN_SCENARIO_ID..." "INFO"
    
    # Execute the scenario using Gremlin CLI
    local output
    output=$(gremlin attack scenario execute "$GREMLIN_SCENARIO_ID" \
        --target-containers "$TARGET_NAMESPACE/$TARGET_DEPLOYMENT" \
        --run 2>&1)
    
    if [ $? -eq 0 ]; then
        # Extract the attack ID from the output
        local scenario_run_id=$(echo "$output" | grep -oP '(?<=Attack )[a-f0-9-]+' | head -1)
        if [ -n "$scenario_run_id" ]; then
            log "✅ Successfully started Gremlin scenario with ID: $scenario_run_id" "SUCCESS"
            echo "$scenario_run_id"
            return 0
        fi
    fi
    
    log "❌ Failed to start Gremlin scenario. Output: $output" "ERROR"
    return 1
}

stop_gremlin_attack() {
    local scenario_run_id=$1
    
    if [ -z "$scenario_run_id" ]; then
        log "⚠️  No Gremlin attack ID provided to stop" "WARN"
        return 0
    fi
    
    log "🛑 Stopping Gremlin attack $scenario_run_id" "INFO"
    
    # Stop the attack using Gremlin CLI
    local output
    output=$(gremlin attack halt "$scenario_run_id" 2>&1)
    
    if [ $? -eq 0 ]; then
        log "✅ Successfully stopped Gremlin attack $scenario_run_id" "SUCCESS"
        return 0
    else
        log "⚠️  Failed to stop Gremlin attack $scenario_run_id. Output: $output" "WARN"
        return 1
    fi
}

# Main script execution
main "$@"
exit 0
