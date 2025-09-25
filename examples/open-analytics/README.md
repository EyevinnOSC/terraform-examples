## Terraform Example - Open Analytics

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
export AWS_ACCESS_KEY_ID=<same as smoothmqaccesskey>
export AWS_SECRET_ACCESS_KEY=<same as smoothmqsecretkey>
```

### AWS CLI

! Note that the AWS CLI has to be installed for creating queues

For installing, please see: [here](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html)

### Using

1. Deploy the solution using the terraform script
2. To try it out:
    a) Play/pause a movie from the streaming solution that was up-and-running prior to this solution.
    b) If no up-and-running solution is available -> Run this bash to send a mocked action: "curl -X POST --json '{ "event": "init", "sessionId": "3", "timestamp": 1740411580982, "playhead": -1, "duration": -1 }' <eventsink-URL>"
    Then go to <clickhouse-URL>, input your credentials (<TF_VAR_clickhouseusername> and <TF_VAR_clickhousepassword>) then run "SELECT * FROM epas_default", you should see it.
3. Visualize data by integrating with Grafana: https://docs.osaas.io/osaas.wiki/Solution%3A-Eyevinn-Open-Analytics.html#step-7-grafana-integration-for-analytics-pipeline