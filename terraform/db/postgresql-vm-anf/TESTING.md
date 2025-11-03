# Testing Guide for PostgreSQL VM + ANF

This guide covers testing procedures for all three deployment methods.

## Pre-Deployment Testing (No Azure Resources Required)

### 1. Terraform Testing

#### Syntax Validation
```bash
cd terraform/db/postgresql-vm-anf
terraform init
terraform validate
```

**Expected:** Configuration is valid

#### Plan Preview
```bash
# Set required variables
export TF_VAR_admin_password="TestPassword123!"
export TF_VAR_postgresql_admin_password="TestPGPassword123!"
export TF_VAR_database_password="TestDBPassword123!"

# Generate plan
terraform plan
```

**What to verify:**
- ✅ Plan generates without errors
- ✅ All resources listed (VM, VNet, NSG, NetApp, etc.)
- ✅ Resource count matches expected (~8-9 resources)
- ✅ No unexpected changes

#### Format Check
```bash
terraform fmt -check
```

**Expected:** Files are properly formatted

### 2. ARM Template Testing

#### JSON Validation
```bash
cd arm-templates/db/postgresql-vm-anf
python3 -m json.tool postgresql-vm-anf-template.json > /dev/null
echo "JSON is valid"
```

**Expected:** No syntax errors

#### Azure Template Validation (Requires Azure CLI)
```bash
az deployment group validate \
  --resource-group <test-rg> \
  --template-file postgresql-vm-anf-template.json \
  --parameters postgresql-vm-anf-parameters.json
```

**What to verify:**
- ✅ Template validates successfully
- ✅ No parameter errors
- ✅ All required parameters provided

#### What-If Preview (Requires Azure CLI)
```bash
az deployment group what-if \
  --resource-group <test-rg> \
  --template-file postgresql-vm-anf-template.json \
  --parameters postgresql-vm-anf-parameters.json
```

**What to verify:**
- ✅ Preview shows resources that will be created
- ✅ No unexpected changes
- ✅ Resource count matches expected

### 3. PowerShell Testing

#### Syntax Validation
```powershell
cd powershell/db/postgresql-vm-anf
Get-Help .\deploy-postgresql-vm-anf.ps1 -Full
```

**Expected:** Help displays correctly, no syntax errors

#### Parameter Validation
```powershell
# Test parameter parsing
.\deploy-postgresql-vm-anf.ps1 -WhatIf
```

**Expected:** Script recognizes all parameters

## Deployment Testing (Requires Azure Subscription)

### Test Environment Setup

**Prerequisites:**
- Active Azure subscription
- Azure NetApp Files enabled
- Contributor permissions
- Test resource group (can be deleted after testing)

### 1. Terraform Deployment Test

#### Deploy
```bash
cd terraform/db/postgresql-vm-anf

# Initialize
terraform init

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan
```

#### Post-Deployment Verification

**1. Resource Verification:**
```bash
# Check resources created
az resource list --resource-group <rg-name> --output table
```

**2. VM Status:**
```bash
# Check VM is running
az vm show --name <vm-name> --resource-group <rg-name> --query "powerState"
```

**3. PostgreSQL Setup Status:**
```bash
# SSH to VM and check PostgreSQL
ssh azureuser@<vm-public-ip>
sudo systemctl status postgresql
sudo cat /var/log/postgresql-setup.log
```

**4. ANF Mount Verification:**
```bash
# On VM
mount | grep nfs
df -h /mnt/postgresql-data
ls -la /mnt/postgresql-data/postgresql-data
```

**5. PostgreSQL Functionality:**
```bash
# On VM
sudo -u postgres psql -c "SELECT version();"
sudo -u postgres psql -c "\l"  # List databases
sudo -u postgres psql -d mydb -c "\dt"  # List tables
```

**6. Network Connectivity:**
```bash
# From local machine (if public IP enabled)
psql -h <vm-public-ip> -p 5432 -U appuser -d mydb
```

### 2. ARM Template Deployment Test

#### Deploy
```bash
cd arm-templates/db/postgresql-vm-anf

az deployment group create \
  --resource-group <rg-name> \
  --template-file postgresql-vm-anf-template.json \
  --parameters postgresql-vm-anf-parameters.json \
  --name postgresql-vm-deployment
```

#### Verification

**1. Check Deployment Status:**
```bash
az deployment group show \
  --resource-group <rg-name> \
  --name postgresql-vm-deployment \
  --query "properties.provisioningState"
```

**2. Verify Outputs:**
```bash
az deployment group show \
  --resource-group <rg-name> \
  --name postgresql-vm-deployment \
  --query "properties.outputs"
```

**3. Follow same verification steps as Terraform** (VM status, PostgreSQL, ANF mount, etc.)

### 3. PowerShell Deployment Test

#### Deploy
```powershell
cd powershell/db/postgresql-vm-anf

$vmPassword = ConvertTo-SecureString "YourVMPassword123!" -AsPlainText -Force
$pgPassword = ConvertTo-SecureString "PostgresPassword123!" -AsPlainText -Force
$dbPassword = ConvertTo-SecureString "DatabasePassword123!" -AsPlainText -Force

.\deploy-postgresql-vm-anf.ps1 `
    -ResourceGroupName "rg-postgresql-test" `
    -AdminUsername "azureuser" `
    -AdminPassword $vmPassword `
    -PostgreSQLAdminPassword $pgPassword `
    -DatabasePassword $dbPassword `
    -Location "eastus"
```

#### Verification

**1. Check Script Output:**
- ✅ Script completes without errors
- ✅ All resources created successfully
- ✅ Connection strings provided

**2. Follow same verification steps** (VM status, PostgreSQL, ANF mount, etc.)

## Post-Deployment Tests

### Functional Tests

#### 1. Database Operations
```sql
-- Connect to PostgreSQL
psql -h <vm-ip> -p 5432 -U appuser -d mydb

-- Test table operations
INSERT INTO test_table (message) VALUES ('Test message');
SELECT * FROM test_table;
UPDATE test_table SET message = 'Updated' WHERE id = 1;
DELETE FROM test_table WHERE id = 1;
```

#### 2. Data Persistence (ANF)
```bash
# Create a large table to verify ANF storage
sudo -u postgres psql -d mydb -c "
CREATE TABLE large_test AS 
SELECT generate_series(1, 100000) AS id, 
       md5(random()::text) AS data;
"

# Check storage usage
df -h /mnt/postgresql-data
```

#### 3. PostgreSQL Performance
```sql
-- Test query performance
EXPLAIN ANALYZE SELECT * FROM large_test WHERE id BETWEEN 1000 AND 2000;
```

#### 4. Network Connectivity
- ✅ SSH access works
- ✅ PostgreSQL accepts connections from allowed IPs
- ✅ Firewall rules work correctly

#### 5. Backup/Recovery
```bash
# Test PostgreSQL backup
sudo -u postgres pg_dump mydb > /tmp/mydb_backup.sql

# Test restore
sudo -u postgres psql -d mydb < /tmp/mydb_backup.sql
```

### Cleanup Tests

#### 1. Terraform Destroy
```bash
terraform destroy
```

**Verify:**
- ✅ All resources deleted
- ✅ No orphaned resources

#### 2. ARM Template Cleanup
```bash
az group delete --name <rg-name> --yes --no-wait
```

#### 3. PowerShell Cleanup
```powershell
Remove-AzResourceGroup -Name "rg-postgresql-test" -Force
```

## Test Scenarios

### Scenario 1: Default Deployment
- **Test:** Deploy with default parameters
- **Expected:** All resources created, PostgreSQL working

### Scenario 2: Custom Configuration
- **Test:** Deploy with custom PostgreSQL version, port, database name
- **Expected:** Custom configuration applied correctly

### Scenario 3: No Public IP
- **Test:** Deploy with `createPublicIP = false`
- **Expected:** VM accessible only via private network

### Scenario 4: Different ANF Service Levels
- **Test:** Deploy with Premium/Ultra service level
- **Expected:** Higher performance storage available

### Scenario 5: Multiple Databases
- **Test:** Create additional databases after deployment
- **Expected:** All databases stored on ANF

### Scenario 6: VM Restart
- **Test:** Restart VM and verify PostgreSQL auto-starts
- **Expected:** PostgreSQL starts automatically, data persists on ANF

## Success Criteria

### Minimum Viable Test
✅ All three tools can be deployed  
✅ Resources are created  
✅ PostgreSQL is installed and running  
✅ ANF volume is mounted  
✅ Database is accessible  
✅ Cleanup works

### Comprehensive Test
✅ All success criteria above  
✅ Performance tests pass  
✅ Multiple configurations tested  
✅ Error handling verified  
✅ Documentation matches actual behavior

## Known Issues & Limitations

### Current Limitations
- Single VM (no high availability)
- Manual backups required
- No automatic failover

### Potential Issues
- PostgreSQL setup may take 10-15 minutes
- ANF volume provisioning may take 3-5 minutes
- Internet required for PostgreSQL installation

## Next Steps After Testing

1. **Document any issues found**
2. **Update READMEs if behavior differs**
3. **Add troubleshooting section**
4. **Create example configurations**
5. **Add to CI/CD if applicable**

