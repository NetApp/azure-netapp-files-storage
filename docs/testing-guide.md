# Azure NetApp Files - Terraform Testing Guide

## Executive Summary

This document provides comprehensive testing procedures for the Azure NetApp Files Terraform templates. The testing framework ensures reliability, security, and performance across all deployment scenarios.

**Document Version:** 1.0  
**Last Updated:** $(date +%Y-%m-%d)  
**Maintained By:** Development Team  
**Review Cycle:** Quarterly

## Testing Objectives

### Primary Goals
- **Reliability**: Ensure consistent deployment across environments
- **Security**: Validate security configurations and compliance
- **Performance**: Verify resource performance and scalability
- **Maintainability**: Test resource cleanup and state management

### Success Criteria
- All templates deploy successfully in target environments
- Security configurations meet organizational standards
- Performance benchmarks are achieved
- Cleanup procedures remove all resources without errors

## Prerequisites

### System Requirements

#### Development Environment
- **Operating System**: Windows 10+, macOS 10.15+, or Linux (Ubuntu 18.04+)
- **Memory**: Minimum 8GB RAM
- **Storage**: 10GB available disk space
- **Network**: Stable internet connection for Azure connectivity

#### Required Software
| Software | Version | Installation Method |
|----------|---------|-------------------|
| Terraform | 1.0+ | [Download](https://www.terraform.io/downloads) |
| Azure CLI | 2.30.0+ | [Install Guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) |
| Git | 2.20+ | [Download](https://git-scm.com/downloads) |

#### Verification Commands
```bash
terraform --version
az --version
git --version
```

### Azure Requirements

#### Subscription Access
- **Role**: Contributor or Owner permissions
- **Features**: Azure NetApp Files enabled
- **Quotas**: Sufficient resource quotas for testing
- **Regions**: Access to target deployment regions

#### Network Requirements
- **Connectivity**: Stable connection to Azure services
- **Firewall**: Port 443 access for Azure APIs
- **DNS**: Resolution for Azure endpoints

## Testing Framework

### Test Matrix Overview

| Template | Complexity Level | Test Scenarios | Estimated Duration | Risk Level |
|----------|-----------------|----------------|-------------------|------------|
| NFS Volume | Basic | 3 scenarios | 30 minutes | Low |
| Linux VM with NFS | Intermediate | 4 scenarios | 45 minutes | Medium |
| Multi-Linux VMs with NFS | Advanced | 5 scenarios | 60 minutes | High |

### Testing Phases

#### Phase 1: Validation Testing
- **Duration**: 15 minutes per template
- **Focus**: Syntax validation and configuration verification
- **Deliverable**: Validation report

#### Phase 2: Functional Testing
- **Duration**: 30 minutes per template
- **Focus**: Deployment and functionality verification
- **Deliverable**: Functional test results

#### Phase 3: Security Testing
- **Duration**: 15 minutes per template
- **Focus**: Security configuration validation
- **Deliverable**: Security assessment report

#### Phase 4: Performance Testing
- **Duration**: 30 minutes per template
- **Focus**: Performance benchmarking and scalability
- **Deliverable**: Performance metrics

## Test Scenarios

### 1. NFS Volume Template Testing

#### Scenario 1.1: Basic Deployment
**Objective**: Validate basic NFS volume deployment functionality

**Test Steps**:
```bash
cd terraform/nfs-volume/
terraform init
terraform plan -var="volume_name=test-volume-1"
terraform apply -var="volume_name=test-volume-1" -auto-approve
```

**Expected Results**:
- [ ] Virtual network created successfully
- [ ] NetApp account created successfully
- [ ] Capacity pool created successfully
- [ ] NFS volume created successfully
- [ ] Outputs contain valid volume IP and mount commands

**Success Criteria**:
- All resources deployed without errors
- Volume accessible via NFS protocol
- Network configuration meets requirements

#### Scenario 1.2: Custom Parameters
**Objective**: Validate template flexibility with custom parameters

**Test Steps**:
```bash
terraform apply \
  -var="volume_name=custom-volume" \
  -var="volume_size_gib=200" \
  -var="location=westus2" \
  -var="project_name=testing" \
  -auto-approve
```

**Expected Results**:
- [ ] Volume size configured to 200 GiB
- [ ] Resources deployed in West US 2 region
- [ ] All resources tagged with "testing" project
- [ ] Custom volume name applied correctly

**Success Criteria**:
- Parameter customization works as expected
- Resource tagging implemented correctly
- Regional deployment successful

#### Scenario 1.3: Idempotency Test
**Objective**: Validate template idempotency and state management

**Test Steps**:
```bash
terraform apply -var="volume_name=test-volume-1" -auto-approve
```

**Expected Results**:
- [ ] No changes detected (idempotent behavior)
- [ ] No new resources created
- [ ] State file accurately reflects current deployment
- [ ] Resource attributes match expected values

**Success Criteria**:
- Template demonstrates true idempotency
- State management functions correctly
- No unintended resource modifications

### 2. Linux VM with NFS Template Testing

#### Scenario 2.1: Basic VM Deployment
**Objective**: Validate complete Linux VM deployment with NFS integration

**Test Steps**:
```bash
cd terraform/linux-vm-with-nfs/
terraform init
terraform apply \
  -var="admin_username=testuser" \
  -var="admin_password=\${ADMIN_PASSWORD:-testpassword}" \
  -auto-approve
```

**Expected Results**:
- [ ] Virtual network and subnets created successfully
- [ ] Network security group configured with SSH/NFS rules
- [ ] Linux VM deployed with Ubuntu 18.04-LTS
- [ ] NFS volume automatically mounted to VM
- [ ] Public IP address assigned for SSH access
- [ ] Cloud-init script executed successfully

**Success Criteria**:
- VM accessible via SSH
- NFS volume mounted and accessible
- Network security properly configured
- All services operational

#### **Scenario 2.2: SSH Connection Test**
```bash
# Get SSH command from outputs
terraform output ssh_command

# Test SSH connection (replace with actual IP)
ssh testuser@<public-ip>
```

**Expected Results:**
- ✅ SSH connection successful
- ✅ NFS volume mounted at `/mnt/anf-vol1`
- ✅ Test file exists: `/mnt/anf-vol1/mount-test.txt`

#### **Scenario 2.3: Security Validation**
```bash
# Check NSG rules
az network nsg rule list --nsg-name nsg-linuxVM --resource-group rg-dev-anf-vm

# Verify export policy
az netappfiles volume show --name anf-vol1 --account-name netappaccount --pool-name netapppool --resource-group rg-dev-anf-vm
```

**Expected Results:**
- ✅ SSH rule (port 22) exists
- ✅ NFS rule (port 2049) exists
- ✅ Export policy allows VM subnet
- ✅ Root access disabled

#### **Scenario 2.4: Performance Test**
```bash
# SSH into VM and run performance tests
ssh testuser@<public-ip>

# Test NFS performance
dd if=/dev/zero of=/mnt/anf-vol1/testfile bs=1M count=100
dd if=/mnt/anf-vol1/testfile of=/dev/null bs=1M
```

**Expected Results:**
- ✅ Write performance acceptable
- ✅ Read performance acceptable
- ✅ No errors during I/O operations

### **3. Multi-Linux VMs with NFS Template Testing**

#### **Scenario 3.1: Multi-VM Deployment**
```bash
cd terraform/multi-linux-vms-with-nfs/
terraform init
terraform apply \
  -var="admin_username=testuser" \
  -var="admin_password=\${ADMIN_PASSWORD:-testpassword}" \
  -var="vm_count=3" \
  -auto-approve
```

**Expected Results:**
- ✅ 3 VMs created with sequential names
- ✅ Load balancer created (since VM count > 1)
- ✅ Shared NFS volume accessible by all VMs
- ✅ Each VM has VM-specific directory

#### **Scenario 3.2: Shared Storage Test**
```bash
# SSH to each VM and verify shared storage
for i in {1..3}; do
  ssh testuser@<vm-$i-ip> "ls -la /mnt/azlinux-shared-nfs/"
  ssh testuser@<vm-$i-ip> "echo 'Test from VM $i' > /mnt/azlinux-shared-nfs/vm-$i/test.txt"
done

# Verify files are visible from all VMs
ssh testuser@<vm-1-ip> "ls -la /mnt/azlinux-shared-nfs/vm-*/"
```

**Expected Results:**
- ✅ All VMs can access shared volume
- ✅ VM-specific directories exist
- ✅ Files created on one VM visible on others
- ✅ Shared directory exists with proper permissions

#### **Scenario 3.3: Load Balancer Test**
```bash
# Get load balancer IP
terraform output load_balancer_ip

# Test load balancer connectivity
ssh testuser@<load-balancer-ip>
```

**Expected Results:**
- ✅ Load balancer accessible
- ✅ Traffic distributed across VMs
- ✅ Health checks passing

#### **Scenario 3.4: Scalability Test**
```bash
# Test with different VM counts
terraform apply \
  -var="admin_username=testuser" \
  -var="admin_password=\${ADMIN_PASSWORD:-testpassword}" \
  -var="vm_count=5" \
  -auto-approve
```

**Expected Results:**
- ✅ 5 VMs created successfully
- ✅ All VMs can access shared storage
- ✅ Load balancer includes all VMs

#### **Scenario 3.5: High Availability Test**
```bash
# Simulate VM failure (stop one VM)
az vm stop --name azlinuxvms1 --resource-group rg-dev-anf-multi-vm

# Verify other VMs still accessible
ssh testuser@<load-balancer-ip>
```

**Expected Results:**
- ✅ Load balancer routes traffic to healthy VMs
- ✅ Shared storage still accessible
- ✅ No data loss

## 🔍 **Validation Checklist**

### **Syntax and Configuration**
- [ ] `terraform validate` passes
- [ ] `terraform plan` shows expected resources
- [ ] No syntax errors in configuration files
- [ ] Variable validation works correctly

### **Security Testing**
- [ ] Passwords are required (no hardcoded defaults)
- [ ] Network security groups configured correctly
- [ ] Export policies restrict access appropriately
- [ ] Root access disabled on NFS volumes
- [ ] Subnet delegation configured for NetApp Files

### **Functionality Testing**
- [ ] All resources created successfully
- [ ] VMs can SSH and access NFS volumes
- [ ] Shared storage works across multiple VMs
- [ ] Load balancer distributes traffic correctly
- [ ] Cloud-init scripts execute properly

### **Performance Testing**
- [ ] NFS read/write performance acceptable
- [ ] VM creation time reasonable
- [ ] Network connectivity stable
- [ ] No resource conflicts

### **Cleanup Testing**
- [ ] `terraform destroy` removes all resources
- [ ] No orphaned resources left behind
- [ ] Resource group deletion successful

## 📊 **Test Results Template**

### **Test Report Format**
```
Template: [Template Name]
Test Date: [Date]
Tester: [Name]
Azure Region: [Region]

Test Scenarios:
1. [Scenario Name] - ✅ PASS / ❌ FAIL
   - Details: [Specific results]
   - Issues: [Any problems found]

2. [Scenario Name] - ✅ PASS / ❌ FAIL
   - Details: [Specific results]
   - Issues: [Any problems found]

Overall Result: ✅ PASS / ❌ FAIL
Recommendations: [Any suggestions for improvement]
```

## 🚨 **Common Issues and Solutions**

### **Issue: Terraform Init Fails**
```bash
# Solution: Check provider versions
terraform init -upgrade
```

### **Issue: Azure Authentication Errors**
```bash
# Solution: Re-authenticate
az login
az account set --subscription "your-subscription-id"
```

### **Issue: NetApp Files Not Available**
```bash
# Solution: Enable NetApp Files
az feature register --namespace Microsoft.NetApp --name ANFGA
az provider register --namespace Microsoft.NetApp
```

### **Issue: VM Creation Fails**
```bash
# Solution: Check quotas and VM size availability
az vm list-skus --location eastus --size Standard_D2s_v3
```

## 📝 **Reporting**

After testing, provide:
1. **Test Results Summary** with pass/fail status
2. **Detailed Logs** for any failures
3. **Performance Metrics** (if applicable)
4. **Security Validation** results
5. **Recommendations** for improvements

## 🔄 **Continuous Testing**

For ongoing testing:
- Run tests after any template changes
- Test in multiple Azure regions
- Validate with different parameter combinations
- Test cleanup procedures regularly

## Test Execution Guidelines

### Pre-Test Checklist
- [ ] All prerequisites met
- [ ] Test environment prepared
- [ ] Azure subscription validated
- [ ] Resource quotas confirmed
- [ ] Test data prepared

### During Testing
- **Documentation**: Record all test results and observations
- **Screenshots**: Capture important outputs and error messages
- **Logs**: Maintain detailed logs of all operations
- **Timing**: Record execution times for performance analysis

### Post-Test Activities
- **Cleanup**: Remove all test resources
- **Documentation**: Update test reports
- **Analysis**: Review results and identify improvements
- **Reporting**: Submit comprehensive test report

## Quality Assurance

### Test Coverage Requirements
- **Functional Testing**: 100% of template features
- **Security Testing**: All security configurations
- **Performance Testing**: Baseline performance metrics
- **Integration Testing**: End-to-end workflows

### Defect Management
- **Severity Levels**: Critical, High, Medium, Low
- **Reporting**: Use standardized defect report format
- **Tracking**: Maintain defect tracking throughout testing
- **Resolution**: Verify fixes before test completion

## Risk Management

### Identified Risks
1. **Resource Costs**: Uncontrolled Azure resource creation
2. **Data Loss**: Accidental deletion of production resources
3. **Security**: Exposure of sensitive information during testing
4. **Performance**: Impact on shared Azure resources

### Mitigation Strategies
- **Cost Control**: Use resource tagging and monitoring
- **Data Protection**: Implement backup procedures
- **Security**: Use test environments and secure credentials
- **Performance**: Schedule tests during off-peak hours

## Appendices

### Appendix A: Test Environment Setup
Detailed instructions for setting up test environments

### Appendix B: Troubleshooting Guide
Common issues and resolution procedures

### Appendix C: Performance Benchmarks
Expected performance metrics and thresholds

### Appendix D: Security Checklist
Comprehensive security validation procedures

---

**Document Control**
- **Version**: 1.0
- **Last Updated**: $(date +%Y-%m-%d)
- **Next Review**: $(date -d "+3 months" +%Y-%m-%d)
- **Approved By**: Development Team Lead

**Important Notes**:
- Always test in non-production environments first
- Use unique resource names to avoid conflicts
- Follow organizational security policies
- Document all deviations from standard procedures 