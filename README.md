# Terraform AWS Bootstrap

These instructions aim to start with a fresh AWS account and take it to using Terraform with all state stored in S3.
This should allow 100% infrastructure as code with as few manual steps as possible and without keeping any secrets in
the source code itself.

# Prerequisites

This documentation assumes Terraform and the AWS CLI are installed. The installation procedure for these tools varies by
operating system and distribution, and is beyond the scope of this document.

# Bootstrapping Terraform

## Initial Access Credentials

As a general policy, as little as possible should be done as the root user in AWS. Here, the initial resources required
for bootstrapping Terraform will be created using the root acount, but then after that a special `terraform` user will
perform all resource manipulation. First, we need to create access credentials on the root account that Terraform can
use to create the initial resources.

From the [AWS IAM Management Console](https://console.aws.amazon.com/iam), go to [Manage Security
Credentials](https://console.aws.amazon.com/iam/home#/security_credentials), usually available from the drop-down that
says "Delete your root access keys". On that page, expand the area for "Access keys (access key ID and secret access
key)", then click "Create New Access Key" and a page with an "Access Key ID" and "Secret Access Key" will be shown.
These access credentials will be used by Terraform to create the initial resources. Once the resources are created, we
will delete those credentials so they can't be used anymore.
 
## Configure AWS CLI

Issue the command `aws configure`. When prompted, enter the "AWS Access Key ID" and "AWS Secret Access Key" shown
earlier when creating the access credentials. Note that even if MFA is configured on the root account, the MFA
codes won't actually need to be used for the AWS CLI when using this access key. The "Default output format" can be
specified as `json`.

Even if a default region is set in `aws configure` Terraform still complains unless the `AWS_DEFAULT_REGION`
environment variable is set, so set it like this:

```bash
export AWS_DEFUALT_REGION=us-east-2
```

Using whatever region is desired for storing these bootstrapping resources.

## Configure Module

Create a Terraform file with a `module` entry, for example `bootstrap.tf` would have the following contents:

```hcl
module "bootstrap" {
  source    = "vexingcodes/bootstrap/aws"
  version   = "1.0.0"
  s3_bucket = "someveryuniquename"
}
```

Minimally, a value for `s3_bucket` _must_ be provided. S3 buckets must have globally unique names, so no defaulted name
other than a random string could work. There are additional variables that can be set if desired. See `variables.tf` for
more information. None of the values entered here are particularly secret, so this Terraform file is meant to be checked
in to source control.

Once the Terraform file is complete, issue the following command to initialize Terraform.

```bash
terraform init
```

## Create Initial Resources

Now we are ready to create the resources in AWS necessary to store the Terraform state. These initial resources include:

* A terraform IAM group and user under which Terraform operations will occur.
* An S3 bucket that stores the state files themselves.
* A DynamoDB that locks the state files so only one entity can be working with them at a time.
* An AWS Secrets Manager secret that can be used to get all of the information to run Terraform as the `terraform` user
  and store the remote state in the S3 backend.

To create these resources run the following command from the `/src/bootstrap` directory in the `dev-env` container shell.

```bash
terraform apply
```

Terraform will determine what needs to be created and will a list of changes it will attempt to make. It will also
prompt for confirmation before actually creating any resources.

## Transition to S3 State Storage

Now all of the pieces are in place to store Terraform state in Amazon S3. Now we need to write a Terraform `provider`
block that describes to Terraform how to configure the S3 backend to store state files. To do this, we need to read
information stored in the Amazon Secrets Manager secret. The following commands wil retreive the secret value, and parse
individual pieces of information out of the secret.

```bash
INFO_JSON=$(aws secretsmanager get-secret-value --secret-id terraform | jq --raw-output .SecretString)
ACCESS_KEY=$(jq --raw-output .access_key <<< ${INFO_JSON})
BUCKET=$(jq --raw-output .bucket <<< ${INFO_JSON})
LOCK_TABLE=$(jq --raw-output .lock_table <<< ${INFO_JSON})
REGION=$(jq --raw-output .region <<< ${INFO_JSON})
SECRET_KEY=$(jq --raw-output .secret_key <<< ${INFO_JSON})
```

If a non-default value was used for the `secret` variable of the module, the flag `--secret-id terraform` will need to
be changed to use the actual secret name, e.g. `--secret-id mysecret`. Using these extracted variables a new Terraform
file with a `provider` block and `terraform.backend` block can be created. For instance, creating `config.tf`:

```bash
cat << EOF > config.tf
provider "aws" {
  access_key = "${ACCESS_KEY}"
  secret_key = "${SECRET_KEY}"
  region     = "${REGION}"
}

terraform {
  backend "s3" {
    encrypt        = true
    bucket         = "${BUCKET}"
    region         = "${REGION}"
    dynamodb_table = "${LOCK_TABLE}"
    access_key     = "${ACCESS_KEY}"
    secret_key     = "${SECRET_KEY}"
    key            = "bootstrap.tfstate"
  }
}
EOF
```

Do _not_ check this `config.tf` file in to source control. It contains secret information that should not be available
publicly. The `bootstrap.tfstate` string in the above command represents the name of the S3 blob that will store the
terraform state for the bootstrapping resources. It can be named arbitrarily. Note that this value is the only thing
in the configuration that cannot be derived from the information stored in the secret. Since the `config.tf` file should
not be checked in to source control, this value will need to be remembered in some way. One way to "remember" these
values is to use the [tfconfig](https://github.com/vexingcodes/terraform-aws-tfconfig) script. This script allows a user
to check in a `.tfconfig` file that specifies the blob name (among other things that may be specified), so that to
regenerate the `config.tf` file from a fresh clone of a repository, a user only has to run the `tfconfig` script with no
arguments. For instance, in this case the `.tfconfig` file contents would be as follows:

```json
{
  "key": "bootstrap.tfstate"
}
```

With the `.tfconfig` file in place, simply running the `tfconfig` script should generate `config.tf` if the AWS IAM user
is allowed to read the Amazon Secrets Manager secret containing the provider/backend configuration variables.

A particular version of the `tfconfig` script (in this case `v1.0.0`) can be retrieved and made executable using the
following commands:

```bash
wget https://raw.githubusercontent.com/vexingcodes/terraform-aws-tfconfig/v1.0.0/tfconfig
chmod +x tfconfig
```

Once the `config.tf` Terraform file is in place, run the following command again.

```bash
terraform init
```

Terraform should notice that the S3 backend is configured, but there is no state stored in S3 yet. It notices that there
is already a local state file, and asks whether or not that local state should be uploaded to S3. Answer `yes` to this
question to transition from local state storage to remote state storage. Once the upload has completed, the
`terraform.tfstate` local file should be empty, but the `terraform.tfstate.backup` file will still contain the state.
Just to be sure, run the following command. It should say no changes need to be made to the infrastructure:

```bash
terraform plan
```

If that is successful, the old local state files can be removed:

```bash
rm *.tfstate*
```

# Tearing Down Bootstrap Resources

Terraform should be able to tear down any resources that it sets up (or that are manually imported). However, Terraform
does not expect to tear down the resources that are currently storing the state remotely, so care needs to be taken when
destroying the bootstrapping resources. Since these resources started life with locally-stored Terraform state, that's
how they'll have to end their life as well. Luckily, Terraform has some built-in commands that make it easy to
transition back to local state:

```bash
terraform state pull > terraform.tfstate
```

These commands will pull the state file down from S3 and store it locally in `terraform.tfstate`. The AWS `provider`
block written earlier must be removed to go back to using the default provider block. In the case of this exapmle, we
named the file with the provider and backend blocks `config.tf` so remove it with:

```bash
rm config.tf
```

Once the provider block has been removed run:

```bash
terraform init
```

Terraform will notice that we have transitioned back to local state. At this point, the bootstrapping resources can be
destroyed using the following command:

```bash
terraform destroy
```
