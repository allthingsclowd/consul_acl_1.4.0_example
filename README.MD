# HashiCorp's Consul 1.4.0 ACL Example   [![Build Status](https://travis-ci.org/allthingsclowd/consul_acl_1.4.0_example.svg?branch=master)](https://travis-ci.org/allthingsclowd/consul_acl_1.4.0_example)

## [A vagrant/travis example of Consul being used as a backend for Terraform](https://www.terraform.io/docs/backends/types/consul.html)

Three VMs are used in the vagrant file, Travis is an all-in-one setup:
 - cert01 : [simply used to illustrate how to create self signed certificates for use in a consul cluster](https://www.consul.io/docs/guides/creating-certificates.html)
 - leader01 : single node Consul "cluster" deployment running in server mode
 - follower01 : Terraform node that has a Consul agent deployed and configured

## Deployment

``` bash
git clone git@github.com:allthingsclowd/consul_acl_1.4.0_example.git
cd consul_acl_1.4.0_example
vagrant up
```

## Accessing the Consul Web UI when using the self-signed certificates

If you would like to use the webui then before visiting `https://192.168.2.11:8321` it's necessary to import the new root CA and client certificates into your system. I used `KeyChain Access` on the Mac to perform these imports.

`consul-ca.pem` is imported into the Systems folder and trusted for all hosts.
`consul-client.pfx` is imported into the personal login (or system) and again trusted for all hosts. The password used for the pfx keys is `bananas`.

## Basic set of policies used to setup the ACLs on Consul 1.4.0 
Ensure to tighten these for a production setup.

``` bash
create_acl_policy () {

      curl \
      --request PUT \
      --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
      --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
      --cert "/usr/local/bootstrap/certificate-config/client.pem" \
      --header "X-Consul-Token: ${CONSUL_HTTP_TOKEN}" \
      --data \
    "{
      \"Name\": \"${1}\",
      \"Description\": \"${2}\",
      \"Rules\": \"${3}\"
      }" https://127.0.0.1:8321/v1/acl/policy
}

step3_create_an_agent_token_policies () {
    
    create_acl_policy "agent-policy" "Agent Token" "node_prefix \\\"\\\" { policy = \\\"write\\\"} service_prefix \\\"\\\" { policy = \\\"read\\\" }"
    create_acl_policy "list-all-nodes" "List All Nodes" "node_prefix \\\"\\\" { policy = \\\"read\\\" }"
    create_acl_policy "ui-access" "Enable UI Access" "key \\\"\\\" { policy = \\\"write\\\"} node \\\"\\\" { policy = \\\"read\\\" } service \\\"\\\" { policy = \\\"read\\\" }"
    create_acl_policy "consul-service" "Consul Service" "service \\\"consul\\\" { policy = \\\"read\\\" }"
    create_acl_policy "development-app" "Sample Development Application" "key_prefix \\\"development/\\\" { policy = \\\"write\\\" }"
}

step4_create_an_agent_token () {
    
    AGENTTOKEN=$(curl \
      --request PUT \
      --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
      --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
      --cert "/usr/local/bootstrap/certificate-config/client.pem" \
      --header "X-Consul-Token: ${CONSUL_HTTP_TOKEN}" \
      --data \
    '{
        "Description": "Agent Token",
        "Policies": [
            {
              "Name": "agent-policy"
            },
            {
              "Name": "list-all-nodes"
            },
            {
              "Name": "ui-access"
            },
            {
              "Name": "consul-service"
            },
            {
              "Name": "development-app"
            }
        ],
        "Local": false
      }' https://127.0.0.1:8321/v1/acl/token | jq -r .SecretID)

      echo "The Agent Token received => ${AGENTTOKEN}"
      echo -n ${AGENTTOKEN} > /usr/local/bootstrap/.agenttoken_acl
      sudo chmod ugo+r /usr/local/bootstrap/.agenttoken_acl
      export AGENTTOKEN
}
```

## Build details..

[TLS had been configured and enabled on both the Consul Server and Agent.](https://www.consul.io/docs/agent/encryption.html#rpc-encryption-with-tls)
``` bash
generate_certificate_config () {

  sudo mkdir -p /etc/pki/tls/private
  sudo mkdir -p /etc/pki/tls/certs
  sudo cp -r /usr/local/bootstrap/certificate-config/${5}-key.pem /etc/pki/tls/private/${5}-key.pem
  sudo cp -r /usr/local/bootstrap/certificate-config/${5}.pem /etc/pki/tls/certs/${5}.pem
  sudo cp -r /usr/local/bootstrap/certificate-config/consul-ca.pem /etc/pki/tls/certs/consul-ca.pem
    tee /etc/consul.d/consul_cert_setup.json <<EOF
    {
    "primary_datacenter": "allthingscloud1",
    "data_dir": "/usr/local/consul",
    "log_level": "INFO",
    "server": ${1},
    "node_name": "${HOSTNAME}",
    "addresses": {
        "https": "0.0.0.0"
    },
    "ports": {
        "https": 8321,
        "http": -1
    },
    "verify_incoming": true,
    "verify_outgoing": true,
    "key_file": "$2",
    "cert_file": "$3",
    "ca_file": "$4"
    }
EOF
}

```
A terraform specific ACL token is created with the following rules

``` bash
create_acl_policy "terraform-backend" "Terraform Session Token" "node_prefix \\\"\\\" { policy = \\\"write\\\"} service_prefix \\\"\\\" { policy = \\\"write\\\" } key_prefix \\\"dev/app1\\\" { policy = \\\"write\\\" } session_prefix \\\"\\\" { policy = \\\"write\\\" }"
```

And the resulting token gets added to the backend configuration for terraform:

``` bash

    tee /usr/local/bootstrap/main.tf <<EOF
resource "null_resource" "Terraform-Consul-Backend-Demo" {
        provisioner "local-exec" {
            command = "echo hello Consul"
        }
} 

terraform {
        backend "consul" {
            address = "127.0.0.1:8321"
            access_token = "${CONSUL_ACCESS_TOKEN}"
            lock = true
            scheme  = "https"
            path    = "dev/app1"
            ca_file = "/usr/local/bootstrap/certificate-config/consul-ca.pem"
            cert_file = "/usr/local/bootstrap/certificate-config/client.pem"
            key_file = "/usr/local/bootstrap/certificate-config/client-key.pem"
        }
}
EOF

```

## The output looks like this

``` bash
    .
    .
    .
    .
    .
   follower01:  TERRAFORM INIT
    follower01: + rm -rf .terraform/
    follower01: + TF_LOG=INFO
    follower01: + terraform init
    follower01: 2019/01/16 19:38:01 [INFO] Terraform version: 0.12.0 alpha4 2c36829d3265661d8edbd5014de8090ea7e2a076
    follower01: 2019/01/16 19:38:01 [INFO] Go runtime version: go1.11.1
    follower01: 2019/01/16 19:38:01 [INFO] CLI args: []string{"/usr/local/bin/terraform", "init"}
    follower01: 2019/01/16 19:38:01 [DEBUG] Attempting to open CLI config file: /root/.terraformrc
    follower01: 2019/01/16 19:38:01 [DEBUG] File doesn't exist, but doesn't need to. Ignoring.
    follower01: 2019/01/16 19:38:01 [INFO] CLI command args: []string{"init"}
    follower01: Initializing the backend...
    follower01: 2019/01/16 19:38:01 [INFO] Failed to read plugin lock file .terraform/plugins/linux_amd64/lock.json: open .terraform/plugins/linux_amd64/lock.json: no such file or directory
    follower01:
    follower01: Successfully configured the backend "consul"! Terraform will automatically
    follower01: use this backend unless the backend configuration changes.
    follower01: 2019/01/16 19:38:01 [INFO] Failed to read plugin lock file .terraform/plugins/linux_amd64/lock.json: open .terraform/plugins/linux_amd64/lock.json: no such file or directory
    follower01: Initializing provider plugins...
    follower01: The following providers do not have any version constraints in configuration,
    follower01: so the latest version was installed.
    follower01: To prevent automatic upgrades to new major versions that may contain breaking
    follower01: changes, it is recommended to add version = "..." constraints to the
    follower01: corresponding provider blocks in configuration, with the constraint strings
    follower01: suggested below.
    follower01: * provider.null: version = "~> 1.0"
    follower01: Terraform has been successfully initialized!
    follower01:
    follower01: You may now begin working with Terraform. Try running "terraform plan" to see
    follower01: any changes that are required for your infrastructure. All Terraform commands
    follower01: should now work.
    follower01: If you ever set or change modules or backend configuration for Terraform,
    follower01: rerun this command to reinitialize your working directory. If you forget, other
    follower01: commands will detect it and remind you to do so if necessary.
    follower01: + [[ 0 > 0 ]]
    follower01: + echo -e '\n TERRAFORM PLAN \n'
    follower01:  TERRAFORM PLAN
    follower01: + TF_LOG=INFO
    follower01: + terraform plan
    follower01: 2019/01/16 19:38:02 [INFO] Terraform version: 0.12.0 alpha4 2c36829d3265661d8edbd5014de8090ea7e2a076
    follower01: 2019/01/16 19:38:02 [INFO] Go runtime version: go1.11.1
    follower01: 2019/01/16 19:38:02 [INFO] CLI args: []string{"/usr/local/bin/terraform", "plan"}
    follower01: 2019/01/16 19:38:02 [DEBUG] Attempting to open CLI config file: /root/.terraformrc
    follower01: 2019/01/16 19:38:02 [DEBUG] File doesn't exist, but doesn't need to. Ignoring.
    follower01: 2019/01/16 19:38:02 [INFO] CLI command args: []string{"plan"}
    follower01: 2019/01/16 19:38:02 [INFO] backend/local: starting Plan operation
    follower01: 2019/01/16 19:38:02 [INFO] created consul lock session e867920f-5641-1048-7b4c-d3eeb5da4ba5
    follower01: 2019-01-16T19:38:02.323Z [INFO]  plugin: configuring client automatic mTLS
    follower01: 2019-01-16T19:38:02.381Z [INFO]  plugin.terraform-provider-null_v1.0.0-5-gf54ff98-dev_x4: configuring server automatic mTLS: timestamp=2019-01-16T19:38:02.365Z
    follower01: 2019-01-16T19:38:02.611Z [INFO]  plugin.terraform-provider-null_v1.0.0-5-gf54ff98-dev_x4: configuring server automatic mTLS: timestamp=2019-01-16T19:38:02.598Z
    follower01: 2019-01-16T19:38:02.720Z [ERROR] plugin.terraform: reading plugin stderr: error="read |0: file already closed"
    follower01: 2019-01-16T19:38:02.720Z [DEBUG] plugin: plugin process exited: path=/usr/local/bin/terraform pid=1343
    follower01: 2019-01-16T19:38:02.720Z [DEBUG] plugin: plugin exited
    follower01: 2019/01/16 19:38:02 [TRACE] [walkValidate] Exiting eval tree: provisioner.local-exec (close)
    follower01: 2019/01/16 19:38:02 [TRACE] vertex "provisioner.local-exec (close)": visit complete
    follower01: 2019/01/16 19:38:02 [INFO] backend/local: plan calling Refresh
    follower01: Refreshing Terraform state in-memory prior to plan...
    follower01: The refreshed state will be used to calculate this plan, but will not be
    follower01: persisted to local or remote state storage.
    follower01:
    follower01: 2019/01/16 19:38:02 [INFO] terraform: building graph: GraphTypeRefresh
    follower01: ------------------------------------------------------------------------
    follower01: 2019-01-16T19:38:02.779Z [INFO]  plugin.terraform-provider-null_v1.0.0-5-gf54ff98-dev_x4: configuring server automatic mTLS: timestamp=2019-01-16T19:38:02.778Z
.
.
.
.
    follower01: 2019/01/16 19:38:03 [TRACE] [walkPlan] Exiting eval tree: provisioner.local-exec (close)
    follower01: 2019/01/16 19:38:03 [TRACE] vertex "provisioner.local-exec (close)": visit complete
    follower01: 2019-01-16T19:38:03.645Z [INFO]  plugin.terraform-provider-null_v1.0.0-5-gf54ff98-dev_x4: configuring server automatic mTLS: timestamp=2019-01-16T19:38:03.645Z
    follower01: null_resource.Terraform-Consul-Backend-Demo: Creating...
    follower01: null_resource.Terraform-Consul-Backend-Demo: Provisioning with 'local-exec'...
    follower01: null_resource.Terraform-Consul-Backend-Demo (local-exec): Executing: ["/bin/sh" "-c" "echo hello Consul"]
    follower01: null_resource.Terraform-Consul-Backend-Demo (local-exec): hello Consul
    follower01: null_resource.Terraform-Consul-Backend-Demo: Creation complete after 0s [id=9087727108894708343]
    follower01:
    follower01: Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
    follower01: + [[ 0 > 0 ]]
    follower01: + popd
    follower01: /home/vagrant
    follower01: + echo -e '\n RESULTS : Terraform state file in Consul backend =>'
    follower01:
    follower01:  RESULTS : Terraform state file in Consul backend =>
    follower01: + export CONSUL_HTTP_ADDR=https://127.0.0.1:8321
    follower01: + CONSUL_HTTP_ADDR=https://127.0.0.1:8321
    follower01: + export CONSUL_CACERT=/usr/local/bootstrap/certificate-config/consul-ca.pem
    follower01: + CONSUL_CACERT=/usr/local/bootstrap/certificate-config/consul-ca.pem
    follower01: + export CONSUL_CLIENT_CERT=/usr/local/bootstrap/certificate-config/cli.pem
    follower01: + CONSUL_CLIENT_CERT=/usr/local/bootstrap/certificate-config/cli.pem
    follower01: + export CONSUL_CLIENT_KEY=/usr/local/bootstrap/certificate-config/cli-key.pem
    follower01: + CONSUL_CLIENT_KEY=/usr/local/bootstrap/certificate-config/cli-key.pem
    follower01: + export CONSUL_HTTP_TOKEN=f0950006-7fa6-3bc2-c205-de16207e3d8c
    follower01: + CONSUL_HTTP_TOKEN=f0950006-7fa6-3bc2-c205-de16207e3d8c
    follower01: + consul kv get dev/app1
    follower01: {
    follower01:   "version": 4,
    follower01:   "terraform_version": "0.12.0",
    follower01:   "serial": 0,
    follower01:   "lineage": "a3e75291-eb6e-a8f5-1496-d06e55dcc90a",
    follower01:   "outputs": {},
    follower01:   "resources": [
    follower01:     {
    follower01:       "mode": "managed",
    follower01:       "type": "null_resource",
    follower01:       "name": "Terraform-Consul-Backend-Demo",
    follower01:       "provider": "provider.null",
    follower01:       "instances": [
    follower01:         {
    follower01:           "schema_version": 0,
    follower01:           "attributes": {
    follower01:             "id": "9087727108894708343",
    follower01:             "triggers": null
    follower01:           }
    follower01:         }
    follower01:       ]
    follower01:     }
    follower01:   ]
    follower01: }
    follower01: + echo -e '\n Finished Terraform Consul Backend Config\n '
    follower01:  Finished Terraform Consul Backend Config
```

__Caution__ : Ensure that you don't have a forward slash `/` at the end of the statefile path as this will generate 403 errors when Terraform tries to access the Consul backend.
