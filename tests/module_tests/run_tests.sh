#!/bin/bash

# Get the script's directory and navigate to the appropriate build directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/../../build/bin"

# Check if the build directory exists
if [[ ! -d "$BUILD_DIR" ]]; then
    echo "Error: Build directory '$BUILD_DIR' does not exist."
    exit 1
fi

# Navigate to the build directory
cd "$BUILD_DIR" || exit 1

BUILD_DIR=$(pwd)

# Define paths
PYTHON_SCRIPT="../../tests/module_tests/run_exec.py"
EXECUTABLE="$BUILD_DIR/compiler"
OUTPUT_DIR="$BUILD_DIR/module_test_results"

# Ensure the output directory exists
mkdir -p "$OUTPUT_DIR"

# Loop through all subdirectories in saplang/tests/module_tests
for TEST_DIR in $SCRIPT_DIR/*/; do
    # Check if test.sl exists in the current subdirectory
    if [[ -f "${TEST_DIR}test.sl" ]]; then
        TEST_FILE="${TEST_DIR}test.sl"
        RELATIVE_DIR=$(basename "$TEST_DIR")
        OUTPUT_FILE="${OUTPUT_DIR}/${RELATIVE_DIR}/test"
        COMPILE_OUTPUT_TEXT_FILE="${OUTPUT_DIR}/${RELATIVE_DIR}/result_compile.txt"
        EXEC_STDOUT_OUTPUT_FILE="${OUTPUT_DIR}/${RELATIVE_DIR}/result_out.txt"
        INCLUDE_DIR="${TEST_DIR%/}"

        echo "Running test for ${RELATIVE_DIR}..."

        mkdir ${OUTPUT_DIR}/${RELATIVE_DIR}
        touch $COMPILE_OUTPUT_TEXT_FILE
        #Run the Python script with the appropriate arguments
        python3 "$PYTHON_SCRIPT" "$EXECUTABLE" "$COMPILE_OUTPUT_TEXT_FILE" "$TEST_FILE"  "-o" "$OUTPUT_FILE" "-i" "$INCLUDE_DIR"
        python3 "$PYTHON_SCRIPT" "$OUTPUT_FILE" "$EXEC_STDOUT_OUTPUT_FILE"

        echo "$TEST_DIR/expected_out.txt"
        if cmp -s "$EXEC_STDOUT_OUTPUT_FILE" "$TEST_DIR/expected_out.txt"; then
            echo "$RELATIVE_DIR stdout test - SUCCESS"
        else
            echo "$RELATIVE_DIR stdout test - FAILURE"
        fi
    else
        echo "No test.sl found in $TEST_DIR, skipping..."
    fi
done

echo "All tests completed."
