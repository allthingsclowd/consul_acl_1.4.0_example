Vagrant.configure("2") do |config|

    #override global variables to fit Vagrant setup
    ENV['LEADER_NAME']||="leader01"
    ENV['LEADER_IP']||="192.168.100.11"
    ENV['FOLLOWER_NAME']||="follower01"
    ENV['FOLLOWER_IP']||="192.168.100.10"
    ENV['CERT_NAME']||="certificate"
    ENV['CERT_IP']||="192.168.100.9"

    #global config
    config.vm.synced_folder ".", "/vagrant"
    config.vm.synced_folder ".", "/usr/local/bootstrap"
    config.vm.box = "allthingscloud/web-page-counter"

    config.vm.provider "virtualbox" do |v|
        v.memory = 1024
        v.cpus = 1
        # Hack below required for linux not MacOS
        v.customize ["modifyvm", :id, "--audio", "none"]
    end

    config.vm.define "cert01" do |cert01|
        cert01.vm.hostname = ENV['CERT_NAME']
        cert01.vm.network "private_network", ip: ENV['CERT_IP']
        cert01.vm.provision "shell", path: "scripts/generate_certificates.sh", run: "always"
    end 

    config.vm.define "leader01" do |leader01|
        leader01.vm.hostname = ENV['LEADER_NAME']
        leader01.vm.network "private_network", ip: ENV['LEADER_IP']
        leader01.vm.provision "shell", path: "scripts/install_consul.sh", run: "always"
        leader01.vm.provision "shell", path: "scripts/consul_enable_acls_1.4.sh", run: "always"
        leader01.vm.network "forwarded_port", guest: 8500, host: 8500
    end

    (1..1).each do |i|
        config.vm.define "follower0#{i}" do |follower|
            follower.vm.hostname = "follower0#{i}"
            follower.vm.network "private_network", ip: "192.168.2.#{100+i*10}"
            follower.vm.provision "shell", path: "scripts/install_consul.sh", run: "always"
            follower.vm.provision "shell", path: "scripts/consul_enable_acls_1.4.sh", run: "always"
            follower.vm.provision "shell", path: "scripts/initialise_terraform_consul_backend.sh", run: "always"
        end
    end


end
