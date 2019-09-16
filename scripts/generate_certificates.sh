#!/usr/bin/env bash

set -x

update_key_in_json_file () {
    cat ${1}
    mv ${1} temp.json
    jq -r "${2} |= ${3}" temp.json > ${1}
    rm temp.json
    cat ${1}
}

install_golang () {
    # install go binary

    REQUIRED_GO_VERSION="go1.11.4"
    CURRENT_GO_VERSION=`go version | cut -d ' ' -f 3`

    [ "${REQUIRED_GO_VERSION}" == "${CURRENT_GO_VERSION}" ] &>/dev/null || {
        go version
        [ -d /usr/local/go ] && sudo rm -rf /usr/local/go
        [ -d /usr/local/bin/go ] && sudo rm -rf /usr/local/bin/go
        go version
        pushd /usr/local/bin
        [ -f ${REQUIRED_GO_VERSION}.linux-amd64.tar.gz ] || {
            sudo wget -q https://dl.google.com/go/${REQUIRED_GO_VERSION}.linux-amd64.tar.gz
        }
        sudo tar -C /usr/local -xzf ${REQUIRED_GO_VERSION}.linux-amd64.tar.gz
        popd
        go version
    }

    [ -d $HOME/go ] || mkdir $HOME/go

    grep -q -F 'export GOPATH=${HOME}/go' ~/.profile || echo 'export GOPATH=${HOME}/go' >> ~/.profile
    grep -q -F 'export PATH=${PATH}:/usr/local/go/bin:${GOPATH}/bin' ~/.profile || echo 'export PATH=${PATH}:/usr/local/go/bin:${GOPATH}/bin' >> ~/.profile

    source ~/.profile
}

install_cfssl () {
    sudo apt-get install -y golang-cfssl
    cfssl version

}

create_required_certificates () {
    mkdir -p /usr/local/bootstrap/certificate-config
    pushd /usr/local/bootstrap/certificate-config


    # Step 1 - Create a Certificate Authority
    #########################################
    # Generate a default Certificate Signing Request (CSR)
    cfssl print-defaults csr > ca-csr.json

    # Set algo to RSA and key size 2048
    update_key_in_json_file ca-csr.json ".key.algo" "\"rsa\""
    update_key_in_json_file ca-csr.json ".key.size" 2048
    update_key_in_json_file ca-csr.json ".CN" "\"allthingscloud.eu\""
    update_key_in_json_file ca-csr.json ".hosts" "[\"allthingscloud.eu\",\"github.com/allthingsclowd\"]"
    update_key_in_json_file ca-csr.json ".names" "[{\"C\" : \"UK\",\"ST\" : \"SY5\",\"L\" : \"Pontesbury\"}]"

    # Generate the Certificate Authorities's (CA's) private key and certificate
    cfssl gencert -initca ca-csr.json | cfssljson -bare consul-ca

    # Step 2 - Generate and Sign Node Certificates
    # admin policy hcl definition file
    tee cfssl.json <<EOF
    {
    "signing": {
        "default": {
            "expiry": "87600h",
            "usages": [
                "signing",
                "key encipherment",
                "server auth",
                "client auth"
                ]
            }
        }
    }
EOF
    
    # Generate a certificate for the Consul server
    echo '{"key":{"algo":"rsa","size":2048}}' | cfssl gencert -ca=consul-ca.pem -ca-key=consul-ca-key.pem -config=cfssl.json \
    -hostname="server.node.allthingscloud1.consul,localhost,127.0.0.1" - | cfssljson -bare server

    # Generate a certificate for the Consul client
    echo '{"key":{"algo":"rsa","size":2048}}' | cfssl gencert -ca=consul-ca.pem -ca-key=consul-ca-key.pem -config=cfssl.json \
    -hostname="client.node.allthingscloud1.consul,localhost,127.0.0.1" - | cfssljson -bare client

    # Generate a certificate for the CLI
    echo '{"key":{"algo":"rsa","size":2048}}' | cfssl gencert -ca=consul-ca.pem -ca-key=consul-ca-key.pem -profile=client \
    - | cfssljson -bare cli

    # wrap certs as p12 for chrome browser
    openssl pkcs12 -password pass:bananas -export -out consul-server.pfx -inkey server-key.pem -in server.pem -certfile consul-ca.pem
    openssl pkcs12 -password pass:bananas -export -out consul-client.pfx -inkey client-key.pem -in client.pem -certfile consul-ca.pem
    openssl pkcs12 -password pass:bananas -export -out consul-cli.pfx -inkey cli-key.pem -in cli.pem -certfile consul-ca.pem
    
    pwd
    ls -al
    popd
}


install_golang
install_cfssl
create_required_certificates
