#!/bin/bash
set -euo pipefail

# TPC-DS dsgen Build Script for Ubuntu Linux
# This script builds the TPC-DS data generation tool (dsgen) on Ubuntu Linux
# 
# Usage: Place this script in the DSGen-software-code-4.0.0/ directory
#        Directory structure should be:
#        ./DSGen-software-code-4.0.0/build_dsgen_ubuntu.sh
#        ./DSGen-software-code-4.0.0/tools/
#        ./DSGen-software-code-4.0.0/tools/makefile

# Configuration
# Assume script is placed in DSGen-software-code-4.0.0 directory alongside tools folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPCDS_SOURCE_DIR="$SCRIPT_DIR"
TOOLS_DIR="$TPCDS_SOURCE_DIR/tools"
BUILD_DIR="$TOOLS_DIR/build"
INSTALL_DIR="/usr/local/bin"
BUILD_LOG="$SCRIPT_DIR/dsgen_build_ubuntu.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$BUILD_LOG"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$BUILD_LOG"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$BUILD_LOG"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$BUILD_LOG"
}

# Check if running on Ubuntu Linux
check_ubuntu() {
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        error "This script is designed for Ubuntu Linux only. Use build_dsgen_macos.sh for macOS."
    fi
    
    # Check if it's Ubuntu specifically
    if [ ! -f /etc/os-release ]; then
        error "Cannot determine Linux distribution. This script is designed for Ubuntu."
    fi
    
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        warn "This script is designed for Ubuntu, but detected: $ID"
        warn "Proceeding anyway, but some package names might not match..."
    fi
    
    log "Detected Ubuntu system: $PRETTY_NAME"
    log "Kernel: $(uname -a)"
}

# Check if running as root (required for apt operations)
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo) for package installation"
    fi
}

# Install build dependencies using apt
install_dependencies() {
    log "Installing build dependencies using apt..."
    
    # Update package list
    apt-get update -y
    
    # Install essential build tools
    local packages=(
        "build-essential"
        "gcc"
        "g++"
        "make"
        "flex"
        "bison"
        "libfl-dev"
        "libreadline-dev"
        "libncurses5-dev"
        "libncursesw5-dev"
        "zlib1g-dev"
        "libssl-dev"
        "libsqlite3-dev"
        "libxml2-dev"
        "libxslt1-dev"
        "libyaml-dev"
        "libffi-dev"
        "libbz2-dev"
        "liblzma-dev"
        "libgdbm-dev"
        "libnss3-dev"
        "libedit-dev"
        "libc6-dev"
        "linux-libc-dev"
    )
    
    for package in "${packages[@]}"; do
        if dpkg -l | grep -q "^ii  $package "; then
            info "$package is already installed"
        else
            log "Installing $package..."
            apt-get install -y "$package" || warn "Failed to install $package"
        fi
    done
    
    log "Build dependencies installation completed"
}

# Check if TPC-DS source exists
check_source() {
    log "Checking TPC-DS source code..."
    
    if [ ! -d "$TPCDS_SOURCE_DIR" ]; then
        error "TPC-DS source directory not found: $TPCDS_SOURCE_DIR"
    fi
    
    if [ ! -d "$TOOLS_DIR" ]; then
        error "TPC-DS tools directory not found: $TOOLS_DIR"
    fi
    
    if [ ! -f "$TOOLS_DIR/Makefile.suite" ]; then
        error "TPC-DS Makefile.suite not found: $TOOLS_DIR/Makefile.suite"
    fi
    
    log "TPC-DS source code found"
}

# Setup TPC-DS build for Ubuntu Linux
setup_tpcds_build() {
    log "Setting up TPC-DS build for Ubuntu Linux..."
    
    cd "$TOOLS_DIR"
    
    # Create build directory
    mkdir -p "$BUILD_DIR"
    
    # Copy Makefile.suite to Makefile
    cp Makefile.suite Makefile
    
    # Configure for Linux (Ubuntu)
    # Set OS to LINUX
    sed -i 's/^OS = .*/OS = LINUX/' Makefile
    
    # Ensure CC is set to gcc
    sed -i 's/^CC = .*/CC = gcc/' Makefile
    
    # Adjust CFLAGS for Ubuntu Linux
    # Ensure 64-bit support and proper flags
    sed -i 's/^LINUX_CFLAGS = .*/LINUX_CFLAGS = -g -Wall -O2/' Makefile
    
    # Ensure BASE_CFLAGS includes proper 64-bit support
    sed -i 's/^BASE_CFLAGS = .*/BASE_CFLAGS = -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE -DYYDEBUG/' Makefile
    
    # Set LEX to flex (Ubuntu typically uses flex)
    sed -i 's/^LINUX_LEX = .*/LINUX_LEX = flex/' Makefile
    
    # Set YACC to bison (Ubuntu typically uses bison)
    sed -i 's/^LINUX_YACC = .*/LINUX_YACC = bison -y/' Makefile
    
    # Ensure proper library linking
    sed -i 's/^LINUX_LIBS = .*/LINUX_LIBS = -lm -lfl/' Makefile
    
    log "TPC-DS build configured for Ubuntu Linux"
}

# Build TPC-DS tools
build_tools() {
    log "Building TPC-DS tools..."
    
    cd "$TOOLS_DIR"
    
    # Clean previous build
    log "Cleaning previous build..."
    make clean 2>/dev/null || true
    
    # Skip standard make build and go directly to manual build with multiple definition fix
    # This is necessary because TPC-DS tools have known multiple definition issues on modern systems
    log "Building TPC-DS tools with manual process and multiple definition fix..."
    
    # Build individual tools with multiple definition fix
    log "Building distcomp, mkheader, and checksum..."
    if ! make distcomp mkheader checksum 2>&1 | tee -a "$BUILD_LOG"; then
        error "Failed to build basic tools. Check $BUILD_LOG for details."
    fi
    
    # Compile all object files needed for dsdgen and dsqgen
    log "Compiling all object files..."
    # Use make with -k flag to continue building even after errors
    if ! make -k -j$(nproc) 2>&1 | tee -a "$BUILD_LOG"; then
        log "Standard make failed (expected due to multiple definitions), but object files should be compiled"
    fi
    
    # Build dsdgen with multiple definition fix
    log "Building dsdgen with multiple definition fix..."
    if ! gcc -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE -DYYDEBUG -DLINUX -g -Wall \
        -Wl,--allow-multiple-definition -o dsdgen \
        s_brand.o s_customer_address.o s_call_center.o s_catalog.o s_catalog_order.o \
        s_catalog_order_lineitem.o s_catalog_page.o s_catalog_promotional_item.o \
        s_catalog_returns.o s_category.o s_class.o s_company.o s_customer.o s_division.o \
        s_inventory.o s_item.o s_manager.o s_manufacturer.o s_market.o s_pline.o \
        s_product.o s_promotion.o s_purchase.o s_reason.o s_store.o s_store_promotional_item.o \
        s_store_returns.o s_subcategory.o s_subclass.o s_warehouse.o s_web_order.o \
        s_web_order_lineitem.o s_web_page.o s_web_promotinal_item.o s_web_returns.o \
        s_web_site.o s_zip_to_gmt.o w_call_center.o w_catalog_page.o w_catalog_returns.o \
        w_catalog_sales.o w_customer_address.o w_customer.o w_customer_demographics.o \
        w_datetbl.o w_household_demographics.o w_income_band.o w_inventory.o w_item.o \
        w_promotion.o w_reason.o w_ship_mode.o w_store.o w_store_returns.o w_store_sales.o \
        w_timetbl.o w_warehouse.o w_web_page.o w_web_returns.o w_web_sales.o w_web_site.o \
        dbgen_version.o address.o build_support.o date.o decimal.o dist.o driver.o \
        error_msg.o genrand.o join.o list.o load.o misc.o nulls.o parallel.o permute.o \
        pricing.o print.o r_params.o StringBuffer.o tdef_functions.o tdefs.o text.o \
        scd.o scaling.o release.o sparse.o validate.o -lm 2>&1 | tee -a "$BUILD_LOG"; then
        error "Failed to build dsdgen. Check $BUILD_LOG for details."
    fi
    
    # Build dsqgen with multiple definition fix
    log "Building dsqgen with multiple definition fix..."
    if ! gcc -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE -DYYDEBUG -DLINUX -g -Wall \
        -Wl,--allow-multiple-definition -o dsqgen \
        address.o date.o decimal.o dist.o error_msg.o expr.o eval.o genrand.o \
        grammar_support.o keywords.o list.o nulls.o permute.o print.o QgenMain.o \
        query_handler.o r_params.o scaling.o StringBuffer.o substitution.o tdefs.o \
        text.o tokenizer.o w_inventory.o y.tab.o release.o scd.o build_support.o \
        parallel.o -lm 2>&1 | tee -a "$BUILD_LOG"; then
        error "Failed to build dsqgen. Check $BUILD_LOG for details."
    fi
    
    log "TPC-DS tools built successfully with manual build and multiple definition fix"
}

# Create dsgen alias (dsgen is the same as dsdgen)
create_dsgen_alias() {
    log "Creating dsgen alias..."
    
    cd "$TOOLS_DIR"
    
    # Create dsgen as a symlink to dsdgen
    if [ -f "dsdgen" ]; then
        ln -sf "dsdgen" "dsgen"
        log "Created dsgen alias"
    else
        error "dsdgen binary not found after build"
    fi
}

# Verify build
verify_build() {
    log "Verifying build..."
    
    cd "$TOOLS_DIR"
    
    # List of expected binaries
    local binaries=("dsdgen" "dsqgen" "dsgen" "distcomp" "mkheader" "checksum")
    local missing_binaries=()
    
    for binary in "${binaries[@]}"; do
        if [ -f "$binary" ]; then
            if [ -x "$binary" ]; then
                local version=$("./$binary" -h 2>&1 | head -1 || echo "Unknown version")
                log "✓ $binary: $version"
            else
                warn "$binary exists but is not executable"
                chmod +x "$binary"
            fi
        else
            missing_binaries+=("$binary")
        fi
    done
    
    if [ ${#missing_binaries[@]} -gt 0 ]; then
        warn "Missing binaries: ${missing_binaries[*]}"
    fi
    
    log "Build verification completed"
}

# Install tools to system path
install_tools() {
    log "Installing tools to system path..."
    
    cd "$TOOLS_DIR"
    
    # Create links in /usr/local/bin for system-wide access
    local binaries=("dsdgen" "dsqgen" "dsgen" "distcomp" "mkheader" "checksum")
    
    for binary in "${binaries[@]}"; do
        if [ -f "$binary" ]; then
            # Remove existing link if it exists
            rm -f "$INSTALL_DIR/$binary" 2>/dev/null || true
            # Create new link
            ln -sf "$TOOLS_DIR/$binary" "$INSTALL_DIR/$binary"
            log "Installed: $INSTALL_DIR/$binary -> $TOOLS_DIR/$binary"
        fi
    done
    
    log "Tools installed to system path"
}

# Test the tools
test_tools() {
    log "Testing TPC-DS tools..."
    
    cd "$TOOLS_DIR"
    
    # Test dsgen (data generator) help
    log "Testing dsgen help..."
    if ./dsgen -h >/dev/null 2>&1; then
        log "✓ dsgen help: Working"
    else
        warn "dsgen help test failed"
    fi
    
    # Test dsqgen (query generator) help
    log "Testing dsqgen help..."
    if ./dsqgen -h >/dev/null 2>&1; then
        log "✓ dsqgen help: Working"
    else
        warn "dsqgen help test failed"
    fi
    
    # Test dsdgen (data generator) help
    log "Testing dsdgen help..."
    if ./dsdgen -h >/dev/null 2>&1; then
        log "✓ dsdgen help: Working"
    else
        warn "dsdgen help test failed"
    fi
    
    # Test actual data generation (small scale)
    log "Testing data generation with 1GB scale factor..."
    if ./dsgen -SCALE 1 -FORCE Y >/dev/null 2>&1; then
        # Check if data files were created
        local data_files=$(ls *.dat 2>/dev/null | wc -l)
        if [ "$data_files" -gt 0 ]; then
            log "✓ Data generation: Working (generated $data_files data files)"
            # Clean up test files
            rm -f *.dat
        else
            warn "Data generation test failed - no data files created"
        fi
    else
        warn "Data generation test failed"
    fi
    
    log "Tool testing completed"
}

# Create usage examples
create_examples() {
    log "Creating usage examples..."
    
    local examples_dir="$TOOLS_DIR/examples"
    mkdir -p "$examples_dir"
    
    # Create example scripts
    cat > "$examples_dir/generate_data.sh" << 'EOF'
#!/bin/bash
# TPC-DS Data Generation Example for Ubuntu Linux

# Set scale factor (1 = 1GB, 10 = 10GB, 100 = 100GB)
SCALE_FACTOR=1

# Set output directory
OUTPUT_DIR="/tmp/tpcds_data"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "Generating TPC-DS data with scale factor $SCALE_FACTOR..."
echo "Output directory: $OUTPUT_DIR"

# Generate data using dsgen
cd "$(dirname "$0")/.."
./dsgen -SCALE $SCALE_FACTOR -FORCE Y

# Move generated files to output directory
mv *.dat "$OUTPUT_DIR/" 2>/dev/null || true

echo "Data generation completed!"
echo "Generated files in: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
EOF

    cat > "$examples_dir/generate_queries.sh" << 'EOF'
#!/bin/bash
# TPC-DS Query Generation Example for Ubuntu Linux

# Set output directory
OUTPUT_DIR="/tmp/tpcds_queries"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "Generating TPC-DS queries..."
echo "Output directory: $OUTPUT_DIR"

# Generate queries using dsqgen
cd "$(dirname "$0")/.."

# Generate all 99 queries
for i in {1..99}; do
    echo "Generating query $i..."
    ./dsqgen $i > "$OUTPUT_DIR/query_$i.sql"
done

echo "Query generation completed!"
echo "Generated queries in: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
EOF

    # Make examples executable
    chmod +x "$examples_dir"/*.sh
    
    log "Usage examples created in: $examples_dir"
}

# Create status script
create_status_script() {
    log "Creating status script..."
    
    cat > "$TOOLS_DIR/check_tools.sh" << 'EOF'
#!/bin/bash
# TPC-DS Tools Status Check for Ubuntu Linux

echo "=== TPC-DS Tools Status ==="
echo "Date: $(date)"
echo "System: $(uname -a)"
echo "Distribution: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")"
echo ""

echo "=== Installed Tools ==="
cd "$(dirname "$0")"

tools=("dsdgen" "dsqgen" "dsgen" "distcomp" "mkheader" "checksum")
for tool in "${tools[@]}"; do
    if [ -f "$tool" ] && [ -x "$tool" ]; then
        echo "✓ $tool: Available"
        ./$tool -h 2>&1 | head -1 | sed 's/^/  /'
    else
        echo "✗ $tool: Not available"
    fi
    echo ""
done

echo "=== System Links ==="
for tool in "${tools[@]}"; do
    if [ -L "/usr/local/bin/$tool" ]; then
        echo "✓ /usr/local/bin/$tool: Linked"
    else
        echo "✗ /usr/local/bin/$tool: Not linked"
    fi
done

echo ""
echo "=== Usage Examples ==="
echo "Generate 1GB data: ./examples/generate_data.sh"
echo "Generate queries: ./examples/generate_queries.sh"
echo "Check status: ./check_tools.sh"
EOF

    chmod +x "$TOOLS_DIR/check_tools.sh"
    
    log "Status script created: $TOOLS_DIR/check_tools.sh"
}

# Main execution
main() {
    log "Starting TPC-DS dsgen build process for Ubuntu Linux..."
    
    # Initialize log file
    echo "TPC-DS dsgen Build Log for Ubuntu Linux - $(date)" > "$BUILD_LOG"
    
    check_ubuntu
    check_root
    install_dependencies
    check_source
    setup_tpcds_build
    build_tools
    create_dsgen_alias
    verify_build
    install_tools
    test_tools
    create_examples
    create_status_script
    
    log "TPC-DS dsgen build completed successfully!"
    
    echo ""
    echo "=========================================="
    echo "Build Summary:"
    echo "=========================================="
    echo "Build log: $BUILD_LOG"
    echo "Tools directory: $TOOLS_DIR"
    echo "System links: $INSTALL_DIR/"
    echo "Examples: $TOOLS_DIR/examples/"
    echo "Status check: $TOOLS_DIR/check_tools.sh"
    echo ""
    echo "Quick test:"
    echo "  cd $TOOLS_DIR && ./check_tools.sh"
    echo ""
    echo "Generate 1GB test data:"
    echo "  cd $TOOLS_DIR && ./examples/generate_data.sh"
    echo ""
    echo "Available commands:"
    echo "  dsgen -h                    # Data generator help"
    echo "  dsqgen -h                   # Query generator help"
    echo "  dsgen -SCALE 1 -FORCE Y     # Generate 1GB test data"
    echo "  dsgen -SCALE 10 -FORCE Y    # Generate 10GB data"
    echo "=========================================="
}

# Run main function
main "$@"
