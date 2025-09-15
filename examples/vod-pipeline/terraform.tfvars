## -- General --
# osc_pat = "via Env Vars TF_VAR_osc_pat. Must match the environment"
osc_environment = "prod"

# MinIO storage
minio_instance_name = "terraformminioexample"
# minio_usernmame = "via Env Vars TF_VAR_minio_username"
# Note!! - S3 CLI Env Var "AWS_ACCESS_KEY_ID" must match minio_username

# minio_password = "via Env Vars TF_VAR_minio_password"
# Note!! - S3 CLI Env Var "AWS_SECRET_ACCESS_KEY" must match minip_password

# SVT Encore
encore_instance_name = "terraformencoreexample"
encore_bucket        = "encore-terraform" #Minio bucket used by Encore

# Valkey 
valkey_instance_name = "terraformvalkeyexample"
# Valkey password = "via Env Vars TF_VAR_valkey_password"

# Encore callback listener
encore_cb_instance_name = "terraformencorecbexample"

# Encore packager
encore_packager_instance_name = "terraformencorepackexample"
encore_packager_bucket        = "encore-packager-terraform"
encore_packager_output_folder = "output" #Minio bucket used by Encore Packager
