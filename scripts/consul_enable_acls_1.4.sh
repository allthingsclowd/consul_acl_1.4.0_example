#!/usr/bin/env bash
set -x

setup_environment () {
    source /usr/local/bootstrap/var.env

    IFACE=`route -n | awk '$1 == "192.168.2.0" {print $8;exit}'`
    CIDR=`ip addr show ${IFACE} | awk '$2 ~ "192.168.2" {print $2}'`
    IP=${CIDR%%/24}

    if [ -d /vagrant ]; then
    sudo mkdir -p /vagrant/logs
    LOG="/vagrant/logs/consul_${HOSTNAME}.log"
    else
    LOG="consul.log"
    fi

    if [ "${TRAVIS}" == "true" ]; then
    IP=${IP:-127.0.0.1}
    fi

    # Configure consul environment variables for use with certificates 
    export CONSUL_HTTP_ADDR=https://127.0.0.1:8321
    export CONSUL_CACERT=/usr/local/bootstrap/certificate-config/consul-ca.pem
    export CONSUL_CLIENT_CERT=/usr/local/bootstrap/certificate-config/cli.pem
    export CONSUL_CLIENT_KEY=/usr/local/bootstrap/certificate-config/cli-key.pem
    

    export AGENT_CONFIG="-config-dir=/etc/consul.d -enable-script-checks=true"

}

step1_enable_acls_on_server () {

  sudo tee /etc/consul.d/consul_acl_1.4_setup.json <<EOF
  {
    "primary_datacenter": "allthingscloud1",
    "acl" : {
      "enabled" : true,
      "default_policy" : "deny",
      "down_policy" : "extend-cache"
    }
  }
EOF
  # read in new configs
  restart_consul

}

step2_create_bootstrap_token_on_server () {

  curl -s -w "\n%{http_code}" \
        --request PUT \
        --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
        --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
        --cert "/usr/local/bootstrap/certificate-config/client.pem" \
        https://127.0.0.1:8321/v1/acl/bootstrap |  {
            read body
            read result
            if [ "$result" == "200" ]; then
                BOOTSTRAPACL=`jq -r .SecretID <<< "$body"`
                echo "The BootStrap ACL received => ${BOOTSTRAPACL}"
                echo -n ${BOOTSTRAPACL} > /usr/local/bootstrap/.bootstrap_acl
                sudo chmod ugo+r /usr/local/bootstrap/.bootstrap_acl
            else
                echo "The system may already be bootstrapped - return code ${result}"

            fi

           }

  BOOTSTRAPACL=`cat /usr/local/bootstrap/.bootstrap_acl`
  export CONSUL_HTTP_TOKEN=${BOOTSTRAPACL}
  echo ${CONSUL_HTTP_TOKEN}
        
}

step3_create_an_agent_token_policy () {
    
    curl \
      --request PUT \
      --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
      --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
      --cert "/usr/local/bootstrap/certificate-config/client.pem" \
      --header "X-Consul-Token: ${CONSUL_HTTP_TOKEN}" \
      --data \
    '{
      "Name": "agent-policy",
      "Description": "Agent Token Policy",
      "Rules": "node_prefix \"\" { policy = \"write\"} service_prefix \"\" { policy = \"read\" } service \"consul\" { policy = \"read\" } key_prefix \"development/\" { policy = \"write\" }"
      }' https://127.0.0.1:8321/v1/acl/policy
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
            }
        ],
        "Local": false
      }' https://127.0.0.1:8321/v1/acl/token | jq -r .SecretID)

      echo "The Agent Token received => ${AGENTTOKEN}"
      echo -n ${AGENTTOKEN} > /usr/local/bootstrap/.agenttoken_acl
      sudo chmod ugo+r /usr/local/bootstrap/.agenttoken_acl
      export AGENTTOKEN
}

step5_add_agent_token_on_server () {

  sudo tee /etc/consul.d/consul_acl_1.4_setup.json <<EOF
  {
  "primary_datacenter": "allthingscloud1",
  "acl" : {
    "enabled" : true,
    "default_policy" : "deny",
    "down_policy" : "extend-cache",
    "tokens" : {
      "agent" : "${AGENTTOKEN}"
    }
  }
}
EOF
  # read in new configs
  restart_consul

}

step6_verify_acl_config () {

    AGENTTOKEN=`cat /usr/local/bootstrap/.agenttoken_acl`


    curl -s -w "\n%{http_code}" \
      --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
      --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
      --cert "/usr/local/bootstrap/certificate-config/client.pem" \
      --header "X-Consul-Token: ${AGENTTOKEN}" \
      https://127.0.0.1:8321/v1/catalog/nodes | {
            read body
            read result
            if [ "$result" == "200" ]; then
                TAGGEDADDRESSES=`jq -r '.[0].TaggedAddresses' <<< "$body"`
                if [ "${TAGGEDADDRESSES}" != "" ];then
                  echo "The ACL system appears to be bootstrapped correctly - Tagged Addresses ${TAGGEDADDRESSES}"
                else
                  echo "The ACL system does not appear to be bootstrapped correctly - Tagged Addresses ${TAGGEDADDRESSES}"
                fi
            else
                echo "The ACL system does not appear to be bootstrapped correctly - return code ${result}"

            fi

           }

}

step7_enable_acl_on_client () {

  AGENTTOKEN=`cat /usr/local/bootstrap/.agenttoken_acl`
  export CONSUL_HTTP_TOKEN=${AGENTTOKEN}

  sudo tee /etc/consul.d/consul_acl_1.4_setup.json <<EOF
  {
  "acl" : {
    "enabled" : true,
    "default_policy" : "deny",
    "down_policy" : "extend-cache",
    "tokens" : {
      "agent" : "${AGENTTOKEN}"
    }
  }
}
EOF
  # read in new configs
  restart_consul

}

step8_create_anonymous_token_policy () {
    # Allow listing nodes and consul dns service for all nodes - may wish to tighten this for production
    curl \
      --request PUT \
      --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
      --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
      --cert "/usr/local/bootstrap/certificate-config/client.pem" \
      --header "X-Consul-Token: ${CONSUL_HTTP_TOKEN}" \
      --data \
    '{
      "Name": "list-nodes-dns-policy",
      "Description": "Allow all nodes to list nodes and access the consul DNS service",
      "Rules": "node_prefix \"\" { policy = \"read\"} service \"consul\" { policy = \"read\" }"
      }' https://127.0.0.1:8321/v1/acl/policy
}

step9_get_anonymous_token_id () {
    # Allow listing nodes and consul dns service for all nodes - may wish to tighten this for production
    AGENTTOKEN=`cat /usr/local/bootstrap/.agenttoken_acl`
    export CONSUL_HTTP_TOKEN=${AGENTTOKEN}

    curl \
      --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
      --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
      --cert "/usr/local/bootstrap/certificate-config/client.pem" \
      --header "X-Consul-Token: ${CONSUL_HTTP_TOKEN}" \
     https://127.0.0.1:8321/v1/acl/policies
}

step10_assign_policy_to_anonymous_token () {
    # Allow listing nodes and consul dns service for all nodes - may wish to tighten this for production
    curl \
      --request PUT \
      --cacert "/usr/local/bootstrap/certificate-config/consul-ca.pem" \
      --key "/usr/local/bootstrap/certificate-config/client-key.pem" \
      --cert "/usr/local/bootstrap/certificate-config/client.pem" \
      --header "X-Consul-Token: ${CONSUL_HTTP_TOKEN}" \
      --data \
    '{
      "Name": "list-nodes-dns-policy",
      "Description": "Allow all nodes to list nodes and access the consul DNS service",
      "Rules": "node_prefix \"\" { policy = \"read\"} service \"consul\" { policy = \"read\" } key_prefix \"development/\" { policy = \"write\" }"
      }' https://127.0.0.1:8321/v1/acl/policy
}

create_app_token () {

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
    step1_enable_acls_on_server
    step2_create_bootstrap_token_on_server
    step3_create_an_agent_token_policy
    step4_create_an_agent_token
    step5_add_agent_token_on_server
    step6_verify_acl_config
    
  else
    echo agent
    step7_enable_acl_on_client
    step6_verify_acl_config
    #step9_get_anonymous_token_id

    #step1_enable_acls_on_agent
    #step3_add_agent_acl
    # for terraform provider
    #step5_create_kv_app_token "terraform" "dev/app1/"
    
  fi
  
  if [ "${TRAVIS}" == "true" ]; then
    step5_create_kv_app_token "terraform" "dev/app1/"
  fi
  verify_consul_access
  echo consul started
}

verify_consul_access () {
      
      echo 'Testing Consul KV by Uploading some key/values'

      #lets delete old consul storage
      consul kv delete -recurse development
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
