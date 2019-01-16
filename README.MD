# HashiCorp's Consul 1.4.0 ACL Example   [![Build Status](https://travis-ci.org/allthingsclowd/Terraform_Consul_Backend_Configuration.svg?branch=master)](https://travis-ci.org/allthingsclowd/Terraform_Consul_Backend_Configuration)

## [A vagrant/travis example of Consul being used as a backend for Terraform](https://www.terraform.io/docs/backends/types/consul.html)

Three VMs are used in the vagrant file, Travis is an all-in-one setup:
 - cert01 : [simply used to illustrate how to create self signed certificates for use in a consul cluster](https://www.consul.io/docs/guides/creating-certificates.html)
 - leader01 : single node Consul "cluster" deployment running in server mode
 - follower01 : Terraform node that has a Consul agent deployed and configured


## Deployment

``` bash
git clone git@github.com:allthingsclowd/Terraform_Consul_Backend_Configuration.git
cd Terraform_Consul_Backend_Configuration
vagrant up
```

## Accessing the Consul Web UI when using the self-signed certificates

If you would like to use the webui then before visiting `https://192.168.2.11:8321` it's necessary to import the new root CA and client certificates into your system. I used `KeyChain Access` on the Mac to perform these imports.

`consul-ca.pem` is imported into the Systems folder and trusted for all hosts.
`consul-client.pfx` is imported into the personal login (or system) and again trusted for all hosts. The password used for the pfx keys is `bananas`.

## Basic set of policies used to setup the ACLs on Consul 1.4.0 
Ensure to tighten these for a production setup.

``` bash
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

__Caution__ : Ensure that you don't have a forward slash `/` at the end of the statefile path as this will generate 403 errors when Terraform tries to access the Consul backend.

