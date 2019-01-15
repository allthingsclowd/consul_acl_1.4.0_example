#!/usr/bin/env bash
set -x
setup_environment () {
    
    echo 'Start Setup of Terraform Environment'
    IFACE=`route -n | awk '$1 == "192.168.2.0" {print $8}'`
    CIDR=`ip addr show ${IFACE} | awk '$2 ~ "192.168.2" {print $2}'`
    IP=${CIDR%%/24}

    if [ -d /vagrant ]; then
        LOG="/vagrant/logs/terraform_${HOSTNAME}.log"
    else
        LOG="terraform.log"
    fi

    if [ "${TRAVIS}" == "true" ]; then
    IP=${IP:-127.0.0.1}
    fi


    echo 'End Setup of Terraform Environment'
}

configure_terraform_consul_backend () {

    echo 'Start Terraform Consul Backend Config'

    [ -f /usr/local/bootstrap/main.tf ] && sudo rm /usr/local/bootstrap/main.tf
    [ -f /usr/local/bootstrap/.terraform ] && sudo rm -rf /usr/local/bootstrap/.terraform

    CONSUL_ACCESS_TOKEN=`cat /usr/local/bootstrap/.terraform_acl`
                

    # admin policy hcl definition file
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


    pushd /usr/local/bootstrap
    cat main.tf
    pwd
    ls
    # initialise the consul backend
    
    echo -e "\n TERRAFORM INIT \n"
    
    rm -rf .terraform/
    TF_LOG=INFO terraform init

    if [[ ${?} > 0 ]]; then
        echo -e "\nWARNING!!!!! TERRAFORM UNABLE TO INITIALSE \n"
        exit 1
    fi

    echo -e "\n TERRAFORM PLAN \n"
    TF_LOG=INFO terraform plan
    if [[ ${?} > 0 ]]; then
        echo -e "\nWARNING!!!!! TERRAFORM PLAN FAIL \n"
        exit 1
    fi

    echo -e "\n TERRAFORM APPLY \n"
    TF_LOG=INFO terraform apply --auto-approve
    if [[ ${?} > 0 ]]; then
        echo -e "\nWARNING!!!!! TERRAFORM APPLY FAILURE \n"
        exit 1
    fi
    popd

    echo -e '\n RESULTS : Terraform state file in Consul backend =>'
    # Setup SSL settings
    export CONSUL_HTTP_ADDR=https://127.0.0.1:8321
    export CONSUL_CACERT=/usr/local/bootstrap/certificate-config/consul-ca.pem
    export CONSUL_CLIENT_CERT=/usr/local/bootstrap/certificate-config/cli.pem
    export CONSUL_CLIENT_KEY=/usr/local/bootstrap/certificate-config/cli-key.pem
    export CONSUL_HTTP_TOKEN=${CONSUL_ACCESS_TOKEN}
    # Read Consul
    consul kv get "dev/app1"

    echo -e '\n Finished Terraform Consul Backend Config\n '   
}

setup_environment
configure_terraform_consul_backend


