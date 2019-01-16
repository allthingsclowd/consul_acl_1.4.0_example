#!/usr/bin/env bash
set -x

generate_certificate_config () {

  sudo mkdir -p /etc/pki/tls/private
  sudo mkdir -p /etc/pki/tls/certs
  sudo cp -r /usr/local/bootstrap/certificate-config/${5}-key.pem /etc/pki/tls/private/${5}-key.pem
  sudo cp -r /usr/local/bootstrap/certificate-config/${5}.pem /etc/pki/tls/certs/${5}.pem
  sudo cp -r /usr/local/bootstrap/certificate-config/consul-ca.pem /etc/pki/tls/certs/consul-ca.pem
  sudo tee /etc/consul.d/consul_cert_setup.json <<EOF
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


source /usr/local/bootstrap/var.env

sleep 5
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

#lets kill past instance
sudo killall -1 consul &>/dev/null

# check consul binary
[ -f /usr/local/bin/consul ] &>/dev/null || {
    pushd /usr/local/bin
    [ -f consul_1.4.0_linux_amd64.zip ] || {
        sudo wget -q https://releases.hashicorp.com/consul/1.4.0/consul_1.4.0_linux_amd64.zip
    }
    sudo unzip consul_1.4.0_linux_amd64.zip
    sudo chmod +x consul
    popd
}

# check terraform binary
[ -f /usr/local/bin/terraform ] &>/dev/null || {
    pushd /usr/local/bin
    [ -f terraform_0.11.8_linux_amd64.zip ] || {
        sudo wget -q https://releases.hashicorp.com/terraform/0.11.8/terraform_0.11.8_linux_amd64.zip
    }
    sudo unzip terraform_0.11.8_linux_amd64.zip
    sudo chmod +x terraform
    popd
}

AGENT_CONFIG="-config-dir=/etc/consul.d -enable-script-checks=true"
sudo mkdir -p /etc/consul.d

# Configure consul environment variables for use with certificates 
export CONSUL_HTTP_ADDR=https://127.0.0.1:8321
export CONSUL_CACERT=/usr/local/bootstrap/certificate-config/consul-ca.pem
export CONSUL_CLIENT_CERT=/usr/local/bootstrap/certificate-config/cli.pem
export CONSUL_CLIENT_KEY=/usr/local/bootstrap/certificate-config/cli-key.pem

# check for consul hostname or travis => server
if [[ "${HOSTNAME}" =~ "leader" ]] || [ "${TRAVIS}" == "true" ]; then
  echo server

  generate_certificate_config true "/etc/pki/tls/private/server-key.pem" "/etc/pki/tls/certs/server.pem" "/etc/pki/tls/certs/consul-ca.pem" server
  if [ "${TRAVIS}" == "true" ]; then
    sudo mkdir -p /etc/consul.d

  fi

  /usr/local/bin/consul members 2>/dev/null || {
      sudo cp -r /usr/local/bootstrap/conf/consul.d/* /etc/consul.d/.
      sudo /usr/local/bin/consul agent -server -ui -log-level=trace -client=0.0.0.0 -bind=${IP} ${AGENT_CONFIG} -data-dir=/usr/local/consul -bootstrap-expect=1 >${LOG} &
    
    sleep 5
    echo 'Testing Consul KV by Uploading some key/values'
    # upload vars to consul kv
    while read a b; do
      k=${b%%=*}
      v=${b##*=}

      consul kv put "development/$k" $v

    done < /usr/local/bootstrap/var.env
    consul members
  }
else
  echo agent

  generate_certificate_config false "/etc/pki/tls/private/client-key.pem" "/etc/pki/tls/certs/client.pem" "/etc/pki/tls/certs/consul-ca.pem" client
  /usr/local/bin/consul members 2>/dev/null || {
    /usr/local/bin/consul agent -client=0.0.0.0 -bind=${IP} -log-level=trace ${AGENT_CONFIG} -data-dir=/usr/local/consul -join=${LEADER_IP} >${LOG} &
    sleep 10
  }
  
  consul kv export "development/"
  consul members
fi

echo consul started
