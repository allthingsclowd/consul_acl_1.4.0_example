# WARNING : UNDER CONSTRUCTION


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

## Challenge - Ascertain minimal policies/rules required to facilitate Consul as a Terraform backend when using a default DENY policy

- ACL Default Policy of DENY
``` bash
  {
    "acl_datacenter": "allthingscloud1",
    "acl_master_token": "${1}",
    "acl_default_policy": "deny",
    "acl_down_policy": "extend-cache"
  }
```

- ACL for Agent Token
``` bash
{
      "Name": "Agent Token",
      "Type": "client",
      "Rules": "node \"\" { policy = \"write\" } session \"\" { policy = \"write\" } service \"\" { policy = \"read\" }"
}
```

- ACL Annonymous Token
``` bash
{
      "ID": "anonymous",
      "Type": "client",
      "Rules": "node \"\" { policy = \"read\" } service \"consul\" { policy = \"read\" } key \"_rexec\" { policy = \"write\" }"
}
```

- ACL Terraform Backend Token
``` bash
"{
      \"Name\": \"${1}\",
      \"Type\": \"client\",
      \"Rules\": \"key \\\"dev/app1\\\" { policy = \\\"write\\\" } node \\\"\\\" { policy = \\\"write\\\" } session \\\"\\\" { policy = \\\"write\\\" }\"
    }"
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
    "datacenter": "allthingscloud1",
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

[ACL's have been enabled on both nodes.](https://www.consul.io/docs/guides/acl.html#bootstrapping-acls)

``` bash
step1_enable_acls_on_server () {

  sudo tee /etc/consul.d/consul_acl_setup.json <<EOF
  {
    "acl_datacenter": "allthingscloud1",
    "acl_master_token": "${1}",
    "acl_default_policy": "deny",
    "acl_down_policy": "extend-cache"
  }
EOF
  # read in new configs
  restart_consul

}

step1_enable_acls_on_agent () {

  sudo tee /etc/consul.d/consul_acl_setup.json <<EOF
  {
    "acl_datacenter": "allthingscloud1",
    "acl_default_policy": "deny",
    "acl_down_policy": "extend-cache"
  }
EOF
  # read in new configs
  restart_consul

}

step2_create_agent_token () {
  AGENTACL=$(curl -s \
        --request PUT \
        --header "X-Consul-Token: ${MASTERACL}" \
        --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
        --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
        --cert "/usr/local/bootstrap/certificate-config/client.pem" \
        --data \
    '{
      "Name": "Agent Token",
      "Type": "client",
      "Rules": "node \"\" { policy = \"write\" } session \"\" { policy = \"write\" } service \"\" { policy = \"read\" }"
    }' https://127.0.0.1:8321/v1/acl/create | jq -r .ID)


  echo "The agent ACL received => ${AGENTACL}"
  echo -n ${AGENTACL} > /usr/local/bootstrap/.client_agent_token
  sudo chmod ugo+r /usr/local/bootstrap/.client_agent_token
}

step3_add_agent_acl () {

  # add the new agent acl token to the consul acl configuration file
  # add_key_in_json_file /etc/consul.d/consul_acl_setup.json ${AGENTACL}
  
  AGENTACL=`cat /usr/local/bootstrap/.client_agent_token`
  # add the new agent acl token via API
  curl -s \
        --request PUT \
        --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
        --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
        --cert "/usr/local/bootstrap/certificate-config/client.pem" \
        --header "X-Consul-Token: ${MASTERACL}" \
        --data \
    "{
      \"Token\": \"${AGENTACL}\"
    }" https://127.0.0.1:8321/v1/agent/token/acl_agent_token

  # lets kill past instance to force reload of new config
  restart_consul
  
}

step4_enable_anonymous_token () {
    
    curl -s \
      --request PUT \
      --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
      --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
      --cert "/usr/local/bootstrap/certificate-config/client.pem" \
      --header "X-Consul-Token: ${MASTERACL}" \
      --data \
    '{
      "ID": "anonymous",
      "Type": "client",
      "Rules": "node \"\" { policy = \"read\" } service \"consul\" { policy = \"read\" } key \"_rexec\" { policy = \"write\" }"
    }' https://127.0.0.1:8321/v1/acl/update
}

step5_create_kv_app_token () {

  APPTOKEN=$(curl -s \
    --request PUT \
    --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
    --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
    --cert "/usr/local/bootstrap/certificate-config/client.pem" \
    --header "X-Consul-Token: ${MASTERACL}" \
    --data \
    "{
      \"Name\": \"${1}\",
      \"Type\": \"client\",
      \"Rules\": \"key \\\"dev/app1\\\" { policy = \\\"write\\\" } node \\\"\\\" { policy = \\\"write\\\" } session \\\"\\\" { policy = \\\"write\\\" }\"
    }" https://127.0.0.1:8321/v1/acl/create | jq -r .ID)

  echo "The ACL token for ${1} is => ${APPTOKEN}"
  echo -n ${APPTOKEN} > /usr/local/bootstrap/.${1}_acl
  sudo chmod ugo+r /usr/local/bootstrap/.${1}_acl
  
} 

restart_consul () {
    
    sudo killall -9 -v consul
    
    if [[ "${HOSTNAME}" =~ "leader" ]] || [ "${TRAVIS}" == "true" ]; then

      /usr/local/bin/consul members 2>/dev/null || {
        sudo cp -r /usr/local/bootstrap/conf/consul.d/* /etc/consul.d/.
        sudo /usr/local/bin/consul agent -server -log-level=trace -ui -client=0.0.0.0 -bind=${IP} ${AGENT_CONFIG} -data-dir=/usr/local/consul -bootstrap-expect=1 >${LOG} &
      }
    else
      /usr/local/bin/consul members 2>/dev/null || {
        /usr/local/bin/consul agent -log-level=trace -client=0.0.0.0 -bind=${IP} ${AGENT_CONFIG} -data-dir=/usr/local/consul -join=${LEADER_IP} >${LOG} &
      }
    fi
    sleep 10
  
}

consul_acl_config () {

  # check for consul hostname or travis => server
  if [[ "${HOSTNAME}" =~ "leader" ]] || [ "${TRAVIS}" == "true" ]; then
    echo server
    step1_enable_acls_on_server ${MASTERACL}
    step2_create_agent_token
    step3_add_agent_acl
    step4_enable_anonymous_token
    
  else
    echo agent
    step1_enable_acls_on_agent
    step3_add_agent_acl
    # for terraform provider
    step5_create_kv_app_token "terraform" "dev/app1/"
    
  fi
  
  if [ "${TRAVIS}" == "true" ]; then
    step5_create_kv_app_token "terraform" "dev/app1/"
  fi
  verify_consul_access
  echo consul started
}

verify_consul_access () {
      
      echo 'Testing Consul KV by Uploading some key/values'
        # upload vars to consul kv
      while read a b; do
        k=${b%%=*}
        v=${b##*=}

        consul kv put "development/$k" $v

      done < /usr/local/bootstrap/var.env
      
      consul kv export "development/"
      
      consul members
}

setup_environment
consul_acl_config

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

