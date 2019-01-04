#!/usr/bin/env bash
set -x

setup_environment () {
    source /usr/local/bootstrap/var.env
    MASTERACL=mymasteraclpassword


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
    export CONSUL_HTTP_TOKEN=${MASTERACL}

    export AGENT_CONFIG="-config-dir=/etc/consul.d -enable-script-checks=true"

}

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
