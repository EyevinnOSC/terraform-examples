# Terraform examples for Eyevinn OSC

Welcome to terraform examples for Eyevinn OSC.

Pleas note that these are examples only, primarily to illustrate how more complex solutions can be created in Eyevinn OSC using terraform.

## Documentation

Eyevinn OSC terraform resource documentation can be found at [OSC Terraform Registry](https://registry.terraform.io/providers/EyevinnOSC/osc/latest).

## Quick Guide - General

This is a **general** quick guide how to use the examples. Additional details may be provided in each example.

- Change to the directory of the example you wish to run
- Have a look at, and edit the `\*.tfvars` file to see what variables to provide via the tfvars-file and/or environment variables. Variables that are considered sensitive should be provided via an environment variable and not via the tfvars-file.
- Get your personal access token from [OSC App Settings](https://app.osaas.io/dashboard/settings/api)
- Set the sensitive variables (e.g. pat, api-keys etc):

```bash
export TF_VAR_<name of the variable used by terraform>=<the actual value>

e.g.

export TF_VAR_osc_pat = <OSC PERSONAL ACCESS TOKEN>
```

### Execution

- run `teraform init`
- (optionally) run `terraform plan`
  This will show you the acion plan and if any issues have been detected
- run `terraform apply`

### Tear down

To tear down everything created and clean up, do:
`terraform destroy`
