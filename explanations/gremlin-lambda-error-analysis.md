# Gremlin Lambda Configuration Error Analysis

## Error Summary (From Production Lambda)

```
[gremlin-lambda] [ef957eb4-e01c-49a5-9bde-228038f24288] 
Loading configuration file from ARN: "arn:aws:ssm:us-west-2:226324427081:parameter/gremlin/config"
Using role: "arn:aws:iam::226324427081:role/chofer-audit-break-glass-dev-break-glass-role"

Effective Configuration: { 
  TeamID: [EMPTY], 
  Debug: true, 
  Labels: [], 
  CertificateProvided: false, 
  PrivateKeyProvided: false
}

Multiple configuration validation errors:
- configuration did not contain a team ID
- configuration did not contain a certificate  
- configuration did not contain a private key
```

## Root Cause

The **production Lambda** (account 226324427081) is loading configuration from SSM Parameter Store at `/gremlin/config`, but the configuration is **missing required fields**:

1. **TeamID** - Empty/missing
2. **Certificate** - Not provided (CertificateProvided: false)
3. **Private Key** - Not provided (PrivateKeyProvided: false)

**Note**: This is a DIFFERENT Lambda than the example repo. The example repo (failure-flags-v2-poc) will help us understand the correct configuration format.

## Configuration Loading Flow

```
Lambda starts
  ↓
Loads from SSM: arn:aws:ssm:us-west-2:226324427081:parameter/gremlin/config
  ↓
Uses IAM role: arn:aws:iam::226324427081:role/chofer-audit-break-glass-dev-break-glass-role
  ↓
Validates configuration
  ↓
FAILS: Missing TeamID, Certificate, Private Key
```

## What's in SSM Parameter Store

The parameter `/gremlin/config` exists but contains incomplete configuration:
- TeamID: **empty**
- Labels: **empty map**
- CertificateProvided: **false**
- PrivateKeyProvided: **false**

## Required Configuration Format

The Lambda expects configuration with:

```json
{
  "TeamID": "your-gremlin-team-id",
  "Certificate": "base64-encoded-cert-or-arn",
  "CertificateARN": "arn:aws:secretsmanager:...",
  "PrivateKey": "base64-encoded-key-or-arn",
  "PrivateKeyARN": "arn:aws:secretsmanager:...",
  "Labels": {
    "key": "value"
  }
}
```

## Fix Options

### Option 1: Update SSM Parameter (Recommended)
Update `/gremlin/config` in SSM Parameter Store with proper values:

```bash
aws ssm put-parameter \
  --name /gremlin/config \
  --type SecureString \
  --value '{
    "TeamID": "438c58ec-03db-47ac-8c58-ec03db67ac42",
    "CertificateARN": "arn:aws:secretsmanager:us-west-2:226324427081:secret/gremlin/certificate",
    "PrivateKeyARN": "arn:aws:secretsmanager:us-west-2:226324427081:secret/gremlin/private-key"
  }' \
  --overwrite \
  --region us-west-2
```

### Option 2: Store Credentials in Secrets Manager
1. Store Gremlin certificate in Secrets Manager
2. Store Gremlin private key in Secrets Manager  
3. Reference ARNs in SSM config

### Option 3: Use Environment Variables
Configure Lambda environment variables directly:
- GREMLIN_TEAM_ID
- GREMLIN_CERTIFICATE (base64)
- GREMLIN_PRIVATE_KEY (base64)

## Gremlin Credentials Needed

From your team (438c58ec-03db-47ac-8c58-ec03db67ac42):
- **Team ID**: 438c58ec-03db-47ac-8c58-ec03db67ac42
- **Team Secret**: 680010a2-b4b7-4540-8010-a2b4b7b54031
- **Certificate**: Download from Gremlin UI → Settings → Teams → Certificates
- **Private Key**: Download from Gremlin UI → Settings → Teams → Certificates

## Next Steps

1. **Check current SSM parameter value:**
   ```bash
   aws ssm get-parameter --name /gremlin/config --region us-west-2 --with-decryption
   ```

2. **Download Gremlin certificates:**
   - Go to: https://app.gremlin.com/settings/teams
   - Download certificate and private key

3. **Store in Secrets Manager:**
   ```bash
   aws secretsmanager create-secret \
     --name gremlin/certificate \
     --secret-string "$(cat gremlin.cert)" \
     --region us-west-2
   
   aws secretsmanager create-secret \
     --name gremlin/private-key \
     --secret-string "$(cat gremlin.key)" \
     --region us-west-2
   ```

4. **Update SSM config with ARNs**

5. **Test Lambda again**

## Reference: failure-flags-v2-poc (Example Setup)

Repository: https://codeberg.org/drudgesentinel/failure-flags-v2-poc
Location: /Users/seanwiley/failure-flags-v2-poc

**Purpose**: This is an EXAMPLE repository showing proper failure flags configuration.
- NOT the source of the error messages
- Will be used to demonstrate correct AWS Parameter Store setup
- Shows proper config.yaml format for Gremlin Lambda

**Configuration Method in Example:**
- Uses `config.yaml` bundled in Lambda zip (line 72 in main.tf)
- Environment variable: `GREMLIN_CONFIG_FILE = "/var/task/config.yaml"`
- Config includes: team_id, team_certificate, team_private_key, labels

**Production Lambda Issue:**
- Different Lambda (account 226324427081)
- Uses SSM Parameter Store instead of bundled config.yaml
- SSM parameter `/gremlin/config` is incomplete/empty

## Next Steps

1. **Use example repo to create proper config.yaml**
2. **Deploy example Lambda to test AWS Parameter Store approach**
3. **Document correct SSM parameter format**
4. **Fix production Lambda's SSM parameter with correct values**
