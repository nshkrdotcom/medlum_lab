#!/bin/bash
# run_all.sh - Run all MedlumLlm examples
#
# Usage:
#   ./examples/run_all.sh              # Run all examples
#   ./examples/run_all.sh --quick      # Run only quick examples (health check + embeddings)
#   ./examples/run_all.sh --embeddings # Run only embedding examples
#   ./examples/run_all.sh --chat       # Run only chat examples
#
# Note: Run from the medlum_llm project root directory

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                     MedlumLlm Example Runner                             ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Parse arguments
RUN_HEALTH=true
RUN_EMBEDDINGS=true
RUN_CHAT=true
RUN_CLINICAL=true
RUN_COMPARISON=true

case "$1" in
    --quick)
        RUN_CHAT=false
        RUN_CLINICAL=false
        RUN_COMPARISON=false
        echo "Running quick examples only (health check + basic embeddings)"
        ;;
    --embeddings|--embeddings-only)
        RUN_CHAT=false
        RUN_COMPARISON=false
        echo "Running embedding examples only"
        ;;
    --chat|--chat-only)
        RUN_HEALTH=false
        RUN_EMBEDDINGS=false
        RUN_CLINICAL=false
        echo "Running chat examples only"
        ;;
    *)
        echo "Running all examples"
        ;;
esac

echo ""

# Check if Ollama is running
echo -e "${YELLOW}Checking Ollama connection...${NC}"
if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Ollama is running${NC}"
else
    echo -e "${RED}✗ Ollama is not running${NC}"
    echo ""
    echo "Please start Ollama first:"
    echo "  ollama serve"
    echo ""
    exit 1
fi

# Ensure dependencies are available
echo -e "${YELLOW}Ensuring dependencies...${NC}"
mix deps.get > /dev/null 2>&1
mix compile > /dev/null 2>&1
echo -e "${GREEN}✓ Dependencies ready${NC}"
echo ""

# Track results
declare -a PASSED=()
declare -a FAILED=()
declare -a SKIPPED=()

run_example() {
    local name="$1"
    local file="$2"

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Running: ${name}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if mix run "$file"; then
        PASSED+=("$name")
        echo -e "${GREEN}✓ ${name} completed${NC}"
    else
        FAILED+=("$name")
        echo -e "${RED}✗ ${name} failed${NC}"
    fi

    echo ""
    sleep 1
}

# Run examples based on flags

if [ "$RUN_HEALTH" = true ]; then
    run_example "01. Health Check" "examples/01_health_check.exs"
fi

if [ "$RUN_EMBEDDINGS" = true ]; then
    run_example "02. Embeddings" "examples/02_embeddings.exs"
fi

if [ "$RUN_CHAT" = true ]; then
    # Check which chat models are available
    echo -e "${YELLOW}Checking available chat models...${NC}"

    if ollama list 2>/dev/null | grep -q "BioMistral\|biomistral"; then
        run_example "03. BioMistral Chat" "examples/03_chat_biomistral.exs"
    else
        echo -e "${YELLOW}⊘ Skipping BioMistral (not pulled)${NC}"
        SKIPPED+=("03. BioMistral Chat")
    fi

    if ollama list 2>/dev/null | grep -q "OpenBioLLM\|openbio"; then
        run_example "04. OpenBioLLM Chat" "examples/04_chat_openbio.exs"
    else
        echo -e "${YELLOW}⊘ Skipping OpenBioLLM (not pulled)${NC}"
        SKIPPED+=("04. OpenBioLLM Chat")
    fi

    if ollama list 2>/dev/null | grep -q "meditron"; then
        run_example "05. Meditron Chat" "examples/05_chat_meditron.exs"
    else
        echo -e "${YELLOW}⊘ Skipping Meditron (not pulled)${NC}"
        SKIPPED+=("05. Meditron Chat")
    fi
fi

if [ "$RUN_CLINICAL" = true ]; then
    run_example "06. Clinical Use Cases" "examples/06_clinical_use_cases.exs"
fi

if [ "$RUN_COMPARISON" = true ]; then
    # Only run comparison if at least one chat model is available
    if ollama list 2>/dev/null | grep -qE "BioMistral|OpenBioLLM|meditron"; then
        run_example "07. Model Comparison" "examples/07_model_comparison.exs"
    else
        echo -e "${YELLOW}⊘ Skipping Model Comparison (no chat models)${NC}"
        SKIPPED+=("07. Model Comparison")
    fi
fi

# Advanced examples (08-12) - REAL inference with Ollama models
echo ""
echo -e "${YELLOW}Running advanced examples (REAL inference)...${NC}"
echo ""

run_example "08. Model Registry" "examples/08_model_registry.exs"
run_example "09. Multi-Model Chat" "examples/09_multi_model_chat.exs"
run_example "10. Embedding Comparison" "examples/10_embedding_comparison.exs"
run_example "11. Hardware Aware" "examples/11_hardware_aware.exs"
run_example "12. Clinical Pipeline" "examples/12_clinical_pipeline.exs"

# Print summary
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════╗"
echo -e "║                           SUMMARY                                        ║"
echo -e "╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ ${#PASSED[@]} -gt 0 ]; then
    echo -e "${GREEN}Passed (${#PASSED[@]}):${NC}"
    for example in "${PASSED[@]}"; do
        echo -e "  ${GREEN}✓${NC} $example"
    done
    echo ""
fi

if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo -e "${YELLOW}Skipped (${#SKIPPED[@]}):${NC}"
    for example in "${SKIPPED[@]}"; do
        echo -e "  ${YELLOW}⊘${NC} $example"
    done
    echo ""
fi

if [ ${#FAILED[@]} -gt 0 ]; then
    echo -e "${RED}Failed (${#FAILED[@]}):${NC}"
    for example in "${FAILED[@]}"; do
        echo -e "  ${RED}✗${NC} $example"
    done
    echo ""
    exit 1
fi

echo -e "${GREEN}All examples completed successfully!${NC}"
