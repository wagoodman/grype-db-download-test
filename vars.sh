set -euo pipefail

BOLD="\033[1m"
PASS="\033[0;32m"
FAIL="\033[0;31m"
AUX="\033[0;90m"
RESET="\033[0m"

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
output_dir="output"
# extra "eu-south-1"
regions=("us-east-1" "us-west-2" "eu-west-1" "eu-west-2" "sa-east-1" "ap-southeast-2" "ap-northeast-1" "eu-central-1")
function_name="download-grype-db"
payload="function.zip"
aws_role="arn:aws:iam::988505687240:role/lambda-execution-role"
update=true

export AWS_PROFILE=dev
export AWS_PAGER=""


function pass() {
    echo -e "${PASS}  ✔ ${RESET}$1"
}

function fail() {
    echo -e "${FAIL}  ✘ ${RESET}$1"
}

function step() {
    echo -e "${BOLD}❯ $1${RESET}"
}

function aux() {
    echo -e "${AUX}  $1${RESET}"
}

function create_payload() {
    rm -f $payload
    step "creating payload..."
    zip $payload gdb.py
}

function deploy_lambda() {
    region=$1

    if ! aws lambda get-function --function-name $function_name --region $region &> /dev/null
    then
        step "creating function in $region"
        aws lambda create-function \
            --handler gdb.lambda_handler \
            --function-name $function_name \
            --description "Invoke grype-db and time result" \
            --runtime python3.12 \
            --role $aws_role \
            --region $region \
            --timeout 300 \
            --zip-file fileb://$payload | jq -r '.FunctionArn'

    else
        step "updating function code in $region"
        aws lambda update-function-code \
            --function-name $function_name \
            --region $region \
            --zip-file fileb://$payload | jq -r '.FunctionArn'
    fi

    aux "waiting for function to be active and updated in $region..."
    while true; do
        state=$(aws lambda get-function-configuration \
            --function-name $function_name \
            --region $region \
            --query "State" \
            --output text)

        last_update_status=$(aws lambda get-function-configuration \
            --function-name $function_name \
            --region $region \
            --query "LastUpdateStatus" \
            --output text)

        if [ "$state" == "Active" ] && [ "$last_update_status" == "Successful" ]; then
            pass "function is active and updated in $region"
            break
        elif [ "$state" == "Failed" ] || [ "$last_update_status" == "Failed" ]; then
            fail "deployment failed in $region"
            exit 1
        else
            aux "? state: '$state', last update: '$last_update_status', waiting..."
            sleep 2
        fi
    done
}

function invoke_lambda() {
    region=$1

    step "invoking function in $region"

    mkdir -p $output_dir/$region
    result_file=$output_dir/$region/$timestamp.json

    result=$(aws lambda invoke \
        --function-name $function_name \
        --region $region \
        --log-type Tail \
        --payload '{}' \
        --cli-binary-format raw-in-base64-out \
        $result_file)

    echo $result | jq -r '.LogResult' | base64 -d
    cat $result_file | jq
    echo "Average Mb/s $(cat $result_file | jq -r '.average_mbps') over $(cat $result_file | jq -r '.total_time') seconds"
}
