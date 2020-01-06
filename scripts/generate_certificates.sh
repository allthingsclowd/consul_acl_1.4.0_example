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

    golang_version=1.13

    echo "Start Golang installation"
    which /usr/local/go/bin/go &>/dev/null || {
        echo "Create a temporary directory"
        sudo mkdir -p /tmp/go_src
        pushd /tmp/go_src
        [ -f go${golang_version}.linux-amd64.tar.gz ] || {
            echo "Download Golang source"
            sudo wget -qnv https://dl.google.com/go/go${golang_version}.linux-amd64.tar.gz
        }
        
        echo "Extract Golang source"
        sudo tar -C /usr/local -xzf go${golang_version}.linux-amd64.tar.gz
        popd
        echo "Remove temporary directory"
        sudo rm -rf /tmp/go_src
        echo "Edit profile to include path for Go"
        echo "export PATH=$PATH:/usr/local/go/bin" | sudo tee -a /etc/profile
        echo "Ensure others can execute the binaries"
        sudo chmod -R +x /usr/local/go/bin/
        cat /etc/profile
        source /etc/profile

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

create_default_templates () {
    # Reset the directory contents - let's hope you've saved your keys!!!
    DATE=`date +"%T"`
    [ -d /usr/local/bootstrap/certificate-config/${1} ] && mv /usr/local/bootstrap/certificate-config/${1} /tmp/certificate-config/${1}${DATE}
    mkdir -p /usr/local/bootstrap/certificate-config/${1}
    
    cd /usr/local/bootstrap/certificate-config/${1}
    # Generate a default Certificate Signing Request (CSR)
    #cfssl print-defaults config > ca-config.json
    create_new_ca-config ${1}
    cfssl print-defaults csr > ${1}-ca-csr.json
}

create_new_ca-config () {
    
    tee /usr/local/bootstrap/certificate-config/${1}/${1}-ca-config.json <<EOF
{
    "signing": {
        "default": {
            "expiry": "43800h"
        },
        "profiles": {
            "server": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth"
                ]
            },
            "client": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            },
            "peer": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            }
        }
    }
}
EOF

}

create_required_certificates () {
    # ${1} - product (e.g. "consul")
    # ${2} - hostname (e.g. "\"leader01\"" )
    # ${3} - hosts (e.g. "\"leader01.allthingscloud.eu\",\"127.0.0.1\",\"192.168.6.11\",\"192.168.9.11\",\"81.143.215.2\",\"leader01\",\"hashistack.ie\"" )
    
    create_default_templates ${1}
    
    pushd /usr/local/bootstrap/certificate-config/${1}


    # Step 1 - Create a Certificate Authority
    #########################################

    # Customise the CSR
    # Set algo to RSA and key size 4096
    update_key_in_json_file ${1}-ca-csr.json ".key.algo" "\"rsa\""
    update_key_in_json_file ${1}-ca-csr.json ".key.size" 4096
    update_key_in_json_file ${1}-ca-csr.json ".CN" "\"hashistack.ie\""
    update_key_in_json_file ca-csr.json ".names" "[{\"C\" : \"UK\",\"ST\" : \"Shropshire\",\"L\" : \"Pontesbury\"}]"

    # Generate the Certificate Authorities's (CA's) private key and certificate
    cfssl gencert -initca ${1}-ca-csr.json | cfssljson -bare ${1}-hashistack-ca -

    # This should generate hashistack_ca-key, hashistack_ca.csr, hashistack_ca.pem

#     # Step 2 - Generate Server Certificate
    cfssl print-defaults csr > ${1}-server.json
    
    update_key_in_json_file ${1}-server.json ".key.algo" "\"rsa\""
    update_key_in_json_file ${1}-server.json ".key.size" 4096
    update_key_in_json_file ${1}-server.json ".CN" "${2}"
    update_key_in_json_file ${1}-server.json ".hosts" "[${3}]"
    update_key_in_json_file ${1}-server.json ".names" "[{\"C\" : \"UK\",\"ST\" : \"Shropshire\",\"L\" : \"Pontesbury\"}]"

    cfssl gencert -ca=${1}-hashistack-ca.pem -ca-key=${1}-hashistack-ca-key.pem -config=${1}-ca-config.json -profile=server ${1}-server.json | cfssljson -bare ${1}-hashistack-server

#     # Step 3 - Generate Peer Certificate
    cfssl print-defaults csr > ${1}-peer.json
    
    update_key_in_json_file ${1}-peer.json ".key.algo" "\"rsa\""
    update_key_in_json_file ${1}-peer.json ".key.size" 4096
    update_key_in_json_file ${1}-peer.json ".CN" "\"server\"" # changed from hostname
    update_key_in_json_file ${1}-peer.json ".hosts" "[${3}]"
    update_key_in_json_file ${1}-peer.json ".names" "[{\"C\" : \"UK\",\"ST\" : \"Shropshire\",\"L\" : \"Pontesbury\"}]"

    cfssl gencert -ca=${1}-hashistack-ca.pem -ca-key=${1}-hashistack-ca-key.pem -config=${1}-ca-config.json -profile=peer ${1}-peer.json | cfssljson -bare ${1}-hashistack-peer

#     # Step 4 - Generate Client Certificate
    cfssl print-defaults csr > ${1}-client.json
    
    update_key_in_json_file ${1}-client.json ".key.algo" "\"rsa\""
    update_key_in_json_file ${1}-client.json ".key.size" 4096
    update_key_in_json_file ${1}-client.json ".CN" "\"client\""
    update_key_in_json_file ${1}-client.json ".hosts" "[\"\"]"
    update_key_in_json_file ${1}-client.json ".names" "[{\"C\" : \"UK\",\"ST\" : \"Shropshire\",\"L\" : \"Pontesbury\"}]"

    cfssl gencert -ca=${1}-hashistack-ca.pem -ca-key=${1}-hashistack-ca-key.pem -config=${1}-ca-config.json -profile=client ${1}-client.json | cfssljson -bare ${1}-hashistack-client
   
#     # Generate a certificate for the Consul server
#     echo '{"key":{"algo":"rsa","size":2048}}' | cfssl gencert -ca=hashistack-ca.pem -ca-key=hashistack-ca-key.pem -config=cfssl.json \
#     -hostname="hashistack.ie,192.168.9.11,192.168.*.*,81.143.215.2,localhost,127.0.0.1" - | cfssljson -bare hashistack-server

#     # Generate a certificate for the Consul client
#     echo '{"key":{"algo":"rsa","size":2048}}' | cfssl gencert -ca=hashistack-ca.pem -ca-key=hashistack-ca-key.pem -config=cfssl.json \
#     -hostname="hashistack.ie,client.node.allthingscloud1.consul,192.168.*.*,81.143.215.2,localhost,127.0.0.1" - | cfssljson -bare hashistack-client

#     # Generate a certificate for the CLI
#     echo '{"key":{"algo":"rsa","size":2048}}' | cfssl gencert -ca=hashistack-ca.pem -ca-key=hashistack-ca-key.pem -profile=client \
#     - | cfssljson -bare hashistack-cli

    # wrap certs as p12 for chrome browser
    openssl pkcs12 -password pass:bananas -export -out ${1}-hashistack-server.pfx -inkey ${1}-hashistack-server-key.pem -in ${1}-hashistack-server.pem -certfile ${1}-hashistack-ca.pem
    openssl pkcs12 -password pass:bananas -export -out ${1}-hashistack-client.pfx -inkey ${1}-hashistack-client-key.pem -in ${1}-hashistack-client.pem -certfile ${1}-hashistack-ca.pem
    openssl pkcs12 -password pass:bananas -export -out ${1}-hashistack-peer.pfx -inkey ${1}-hashistack-peer-key.pem -in ${1}-hashistack-peer.pem -certfile ${1}-hashistack-ca.pem
    
    pwd
    ls -al
    popd
}


install_golang
install_cfssl
create_required_certificates "consul" "\"leader01\"" "\"leader01.allthingscloud.eu\",\"127.0.0.1\",\"192.168.6.11\",\"192.168.9.11\",\"81.143.215.2\",\"leader01\",\"hashistack.ie\"" 
create_required_certificates "vault" "\"leader01\"" "\"leader01.allthingscloud.eu\",\"127.0.0.1\",\"192.168.6.11\",\"192.168.9.11\",\"81.143.215.2\",\"leader01\",\"hashistack.ie\""
create_required_certificates "nomad" "\"leader01\"" "\"leader01.allthingscloud.eu\",\"127.0.0.1\",\"192.168.6.11\",\"192.168.9.11\",\"81.143.215.2\",\"leader01\",\"hashistack.ie\"" 