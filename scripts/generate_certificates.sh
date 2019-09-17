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
    which /usr/local/go &>/dev/null || {
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
    [ -d /usr/local/bootstrap/certificate-config ] && mv /usr/local/bootstrap/certificate-config /tmp/certificate-config${DATE}
    mkdir -p /usr/local/bootstrap/certificate-config
    
    cd /usr/local/bootstrap/certificate-config
    # Generate a default Certificate Signing Request (CSR)
    #cfssl print-defaults config > ca-config.json
    create_new_ca-config
    cfssl print-defaults csr > ca-csr.json
}

create_new_ca-config () {
    
    tee ca-config.json <<EOF
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
    
    pushd /usr/local/bootstrap/certificate-config


    # Step 1 - Create a Certificate Authority
    #########################################

    # Customise the CSR
    # Set algo to RSA and key size 2048
    update_key_in_json_file ca-csr.json ".key.algo" "\"rsa\""
    update_key_in_json_file ca-csr.json ".key.size" 2048
    update_key_in_json_file ca-csr.json ".CN" "\"hashistack.ie\""
    update_key_in_json_file ca-csr.json ".names" "[{\"C\" : \"UK\",\"ST\" : \"Shropshire\",\"L\" : \"Pontesbury\"}]"

    # Generate the Certificate Authorities's (CA's) private key and certificate
    cfssl gencert -initca ca-csr.json | cfssljson -bare hashistack_ca -

    # This should generate hashistack_ca-key, hashistack_ca.csr, hashistack_ca.pem

    # Step 2 - Generate Server Certificates
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
    echo '{"key":{"algo":"rsa","size":2048}}' | cfssl gencert -ca=hashistack-ca.pem -ca-key=hashistack-ca-key.pem -config=cfssl.json \
    -hostname="hashistack.ie,192.168.9.11,192.168.*.*,81.143.215.2,localhost,127.0.0.1" - | cfssljson -bare hashistack-server

    # Generate a certificate for the Consul client
    echo '{"key":{"algo":"rsa","size":2048}}' | cfssl gencert -ca=hashistack-ca.pem -ca-key=hashistack-ca-key.pem -config=cfssl.json \
    -hostname="hashistack.ie,client.node.allthingscloud1.consul,192.168.*.*,81.143.215.2,localhost,127.0.0.1" - | cfssljson -bare hashistack-client

    # Generate a certificate for the CLI
    echo '{"key":{"algo":"rsa","size":2048}}' | cfssl gencert -ca=hashistack-ca.pem -ca-key=hashistack-ca-key.pem -profile=client \
    - | cfssljson -bare hashistack-cli

    # wrap certs as p12 for chrome browser
    openssl pkcs12 -password pass:bananas -export -out hashistack-server.pfx -inkey hashistack-server-key.pem -in hashistack-server.pem -certfile hashistack-ca.pem
    openssl pkcs12 -password pass:bananas -export -out hashistack-client.pfx -inkey hashistack-client-key.pem -in hashistack-client.pem -certfile hashistack-ca.pem
    openssl pkcs12 -password pass:bananas -export -out hashistack-cli.pfx -inkey hashistack-cli-key.pem -in hashistack-cli.pem -certfile hashistack-ca.pem
    
    pwd
    ls -al
    popd
}


install_golang
install_cfssl
create_required_certificates
