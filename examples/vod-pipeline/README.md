## Terraform/OpenTofu Example - VOD pipeline

This solution will automaticall create a complete VOD pipeline including transcoding and ABR packaging, using the following OSC components

- MinIO (S3 compatible storage)
- Valkey (Redis compatible key/value store used for message queue)
- Encore (VOD transcoding system)
- Encore Callback Listener (Handles callbacks from encore and posting to Valkey queue)
- Encore Packager (Packages the transcoded files to ABR-packages)

See general guidelines [here](../../README.md#quick-guide---general)

### Solution variables

- Env variables that needs to be set

```bash
export TF_VAR_osc_pat = <osc personal access token>
export TF_VAR_minio_username = <User name for the minio storage>
export TF_VAR_minio_password = <Password for the minio storage>
export TF_VAR_valkey_password = <Password for the Valkey store>
```

### AWS CLI

! Note that the AWS CLI has to be installed since the terraform deployment takes care of creating the buckets automatically

For installing, please see: [here](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html)

Note!! - S3 CLI Env Var `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` must match `minio_username` and `minio_password`

### Using

1. Deploy the solution using the terraform/tofu script
2. Upload a video file to the MinIO storage like this:

   ```bash
   aws --endpoint-url <MinIO instance URL> s3 cp <path_to_file>/<video_file_name.mp4> s3://<encore_bucket>/<folder>
   ```

   Example

   This will upload a video file named test_local.mp4 located in user root, to the bucket named "encore-terraform" (see variables) and folder named "input". The folder "input" will automatically be created:

   ```bash
   aws --endpoint-url https://eyevinnlab-myvodpipeline.minio-minio.auto.prod.osaas.io s3 cp ~/test_local.mp4 s3://encore/input/
   ```

3. POST an encore job. This can be done via the swagger pages:

   Go to the Encore service instance card in the OSC APP UI and select to "Open API Docs" (click the three dots top right)

   Example POST json:

   ```json
   {
     "externalId": "terraform_test",
     "profile": "program",
     "outputFolder": "s3://encore/output/",
     "baseName": "terraformtest",
     "progressCallbackUri": "https://eyevinnlab-myvodpipeline.eyevinn-encore-callback-listener.auto.prod.osaas.io/encoreCallback",
     "inputs": [
       {
         "uri": "s3://encore/input/test_local.mp4",
         "seekTo": 0,
         "copyTs": true,
         "type": "AudioVideo"
       }
     ]
   }
   ```

   where `progressCallbackURI` = <"Encore Callback Listener instance URL">/encoreCallback

Instead of uploading the input source file to the MinIO storage you can instead change the URI to the source file in the json POST body to point to your publically available file (https://<some_host>/<path>/<filename>)

4. Check for packager output using the AWS CLI (example)

```bash
   aws --endpoint-url https://eyevinnlab-terraformminioexample.minio-minio.auto.prod.osaas.io s3 ls s3://encore-packager --recursive
```
