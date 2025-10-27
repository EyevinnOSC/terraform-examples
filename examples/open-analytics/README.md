## Terraform/OpenTofu Example - Open Analytics

This solution is based on the use case where you have a streaming solution up and running and you want to gather analytics, using the following OSC components

- SmoothMQ
- ClickHouse Server
- Player Analytics Event Sink
- Player Analytics Worker

### Solution variables

- see \*.tfvars

```bash
export TF_VAR_osc_pat=<osc personal access token>
export TF_VAR_smoothmqaccesskey=<Access key for SmoothMQ>
export TF_VAR_smoothmqsecretkey=<Secret key for SmoothMQ>
export TF_VAR_clickhouseusername=<Username for the ClickHouse Server>
export TF_VAR_clickhousepassword=<Password for the ClickHouse Server>
```

### AWS CLI

! Note that the AWS CLI has to be installed for creating queues

For installing, please see: [here](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html)

### Using

1. Deploy the solution using the terraform/tofu script
2. To try it out:  
   a) Play/pause a movie from the streaming solution that was up-and-running prior to this solution.  
   b) Use the Eyevin Web player [here](https://web.player.eyevinn.technology/index.html) and enter `<eventsink-URL>` in "EPAS eventsink URL" input field.  
   c) Manually by sending a mocked action:
   ```bash
   curl -X POST --json '{ "event": "init", "sessionId": "3", "timestamp": 1740411580982, "playhead": -1, "duration": -1 }' `<eventsink-URL>
   ```
   Then open the clickhouse UI via `<clickhouse-URL>`, input your credentials (`<TF_VAR_clickhouseusername>` and `<TF_VAR_clickhousepassword>`) and run `SELECT * FROM epas_default` and you should see the transaction(s).
3. Visualize data by visiting the Grafana instance created (includes auto provisioned data source and an example dashboard)
