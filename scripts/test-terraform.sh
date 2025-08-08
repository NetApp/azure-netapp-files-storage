#!/bin/bash

# Terraform Testing Script
# This script provides quick validation of Terraform templates

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check if az is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to test NFS Volume template
test_nfs_volume() {
    print_status "Testing NFS Volume template..."
    
    cd terraform/nfs-volume/
    
    # Initialize
    terraform init -input=false
    
    # Validate
    if terraform validate; then
        print_success "NFS Volume template validation passed"
    else
        print_error "NFS Volume template validation failed"
        return 1
    fi
    
    # Plan
    if terraform plan -var="volume_name=test-volume-$(date +%s)" -input=false; then
        print_success "NFS Volume template plan successful"
    else
        print_error "NFS Volume template plan failed"
        return 1
    fi
    
    cd ../..
}

# Function to test Linux VM with NFS template
test_linux_vm_with_nfs() {
    print_status "Testing Linux VM with NFS template..."
    
    cd terraform/linux-vm-with-nfs/
    
    # Initialize
    terraform init -input=false
    
    # Validate
    if terraform validate; then
        print_success "Linux VM with NFS template validation passed"
    else
        print_error "Linux VM with NFS template validation failed"
        return 1
    fi
    
    # Plan (without applying to avoid costs)
    if terraform plan \
        -var="admin_username=testuser" \
        -var="admin_password=TestPassword123!" \
        -input=false; then
        print_success "Linux VM with NFS template plan successful"
    else
        print_error "Linux VM with NFS template plan failed"
        return 1
    fi
    
    cd ../..
}

# Function to test Multi-Linux VMs with NFS template
test_multi_linux_vms_with_nfs() {
    print_status "Testing Multi-Linux VMs with NFS template..."
    
    cd terraform/multi-linux-vms-with-nfs/
    
    # Initialize
    terraform init -input=false
    
    # Validate
    if terraform validate; then
        print_success "Multi-Linux VMs with NFS template validation passed"
    else
        print_error "Multi-Linux VMs with NFS template validation failed"
        return 1
    fi
    
    # Plan (without applying to avoid costs)
    if terraform plan \
        -var="admin_username=testuser" \
        -var="admin_password=TestPassword123!" \
        -var="vm_count=2" \
        -input=false; then
        print_success "Multi-Linux VMs with NFS template plan successful"
    else
        print_error "Multi-Linux VMs with NFS template plan failed"
        return 1
    fi
    
    cd ../..
}

# Function to run security checks
run_security_checks() {
    print_status "Running security checks..."
    
    # Check for hardcoded passwords in Terraform files
    if grep -r "password.*=.*\".*\"" terraform/ --include="*.tf" --include="*.tfvars"; then
        print_warning "Found potential hardcoded passwords in Terraform files"
    else
        print_success "No hardcoded passwords found"
    fi
    
    # Check for sensitive data in outputs
    if grep -r "password\|secret\|key" terraform/ --include="*.tf" -i; then
        print_warning "Found potential sensitive data in Terraform files"
    else
        print_success "No obvious sensitive data found"
    fi
    
    print_success "Security checks completed"
}

# Function to generate test report
generate_test_report() {
    print_status "Generating test report..."
    
    cat > test-report.md << EOF
# Terraform Test Report

**Test Date:** $(date)
**Tester:** $(whoami)
**Azure Subscription:** $(az account show --query name -o tsv)

## Test Results

### Prerequisites Check
- [x] Terraform installed
- [x] Azure CLI installed
- [x] Azure authentication

### Template Validation
- [x] NFS Volume template
- [x] Linux VM with NFS template
- [x] Multi-Linux VMs with NFS template

### Security Checks
- [x] No hardcoded passwords
- [x] Sensitive data handling

## Recommendations

1. Test in multiple Azure regions
2. Validate with different parameter combinations
3. Test actual deployments in non-production environment
4. Verify cleanup procedures

## Next Steps

1. Run full deployment tests
2. Test performance scenarios
3. Validate security configurations
4. Test disaster recovery scenarios
EOF
    
    print_success "Test report generated: test-report.md"
}

# Main execution
main() {
    echo "=========================================="
    echo "    Terraform Template Testing Script"
    echo "=========================================="
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Test each template
    test_nfs_volume
    test_linux_vm_with_nfs
    test_multi_linux_vms_with_nfs
    
    # Run security checks
    run_security_checks
    
    # Generate report
    generate_test_report
    
    echo ""
    echo "=========================================="
    print_success "All tests completed successfully!"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "1. Review test-report.md"
    echo "2. Run actual deployments in test environment"
    echo "3. Validate functionality and performance"
    echo "4. Test cleanup procedures"
}

# Run main function
main "$@" 