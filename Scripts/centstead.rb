class Centstead
  def Centstead.configure(config, settings)

    # Set The VM Provider
    # 设置 虚拟机 软件
    ENV['VAGRANT_DEFAULT_PROVIDER'] = settings["provider"] ||= "virtualbox"

    # Configure Local Variable To Access Scripts From Remote Location
    # 设置脚本位置变量
    scriptDir = File.dirname(__FILE__)

    # Prevent TTY Errors
    config.ssh.shell = "bash -c 'BASH_ENV=/etc/profile exec bash'"

    # Allow SSH Agent Forward from The Box
    config.ssh.forward_agent = true

    # Configure The Box / 配置 基础盒子
    config.vm.box = settings["box"] ||= "jason-chang/centstead-box"

    #config.vm.box_version = settings["version"] ||= ">= 0.4.0"
    config.vm.hostname = settings["hostname"] ||= "Centstead"

    # A private dhcp network is required for NFS to work (on Windows hosts, at least)
    config.vm.network :private_network, type: "dhcp"

    # Set uid and gid for winnfsd
    config.winnfsd.uid = 1000
    config.winnfsd.gid = 1000

    # Configure A Private Network IP
    config.vm.network :private_network, ip: settings["ip"] ||= "192.168.10.10"

    # Configure Additional Networks
    if settings.has_key?("networks")
      settings["networks"].each do |network|
        config.vm.network network["type"], ip: network["ip"], bridge: network["bridge"] ||= nil
      end
    end

    # Configure A Few VirtualBox Settings
    config.vm.provider "virtualbox" do |vb|
      vb.name = settings["name"] ||= "Centstead-1"
      vb.customize ["modifyvm", :id, "--memory", settings["memory"] ||= "2048"]
      vb.customize ["modifyvm", :id, "--cpus", settings["cpus"] ||= "1"]
      vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--ostype", "RedHat_64"]
    end

    # Configure A Few VMware Settings
    ["vmware_fusion", "vmware_workstation"].each do |vmware|
      config.vm.provider vmware do |v|
        v.vmx["displayName"] = "Centstead"
        v.vmx["memsize"] = settings["memory"] ||= 2048
        v.vmx["numvcpus"] = settings["cpus"] ||= 1
        v.vmx["guestOS"] = "centos-64"
      end
    end

    # Configure A Few Parallels Settings
    config.vm.provider "parallels" do |v|
      v.update_guest_tools = true
      v.memory = settings["memory"] ||= 2048
      v.cpus = settings["cpus"] ||= 1
    end

    # Standardize Ports Naming Schema
    if (settings.has_key?("ports"))
      settings["ports"].each do |port|
        port["guest"] ||= port["to"]
        port["host"] ||= port["send"]
        port["protocol"] ||= "tcp"
      end
    else
      settings["ports"] = []
    end

    # Default Port Forwarding
    default_ports = {
        80   => 80,
        443  => 44300,
        3306 => 33060,
        5432 => 54320
    }

    # Use Default Port Forwarding Unless Overridden
    default_ports.each do |guest, host|
      unless settings["ports"].any? { |mapping| mapping["guest"] == guest }
        config.vm.network "forwarded_port", guest: guest, host: host, auto_correct: true
      end
    end

    # Add Custom Ports From Configuration
    if settings.has_key?("ports")
      settings["ports"].each do |port|
        config.vm.network "forwarded_port", guest: port["guest"], host: port["host"], protocol: port["protocol"], auto_correct: true
      end
    end

    # Configure The Public Key For SSH Access
    if settings.include? 'authorize'
      if File.exists? File.expand_path(settings["authorize"])
        config.vm.provision "shell" do |s|
          s.inline = "echo $1 | grep -xq \"$1\" /home/vagrant/.ssh/authorized_keys || echo $1 | tee -a /home/vagrant/.ssh/authorized_keys"
          s.args = [File.read(File.expand_path(settings["authorize"]))]
        end
      end
    end

    # Copy The SSH Private Keys To The Box
    if settings.include? 'keys'
      settings["keys"].each do |key|
        config.vm.provision "shell" do |s|
          s.privileged = false
          s.inline = "echo \"$1\" > /home/vagrant/.ssh/$2 && chmod 600 /home/vagrant/.ssh/$2"
          s.args = [File.read(File.expand_path(key)), key.split('/').last]
        end
      end
    end

    # Copy User Files Over to VM
    if settings.include? 'copy'
      settings["copy"].each do |file|
        config.vm.provision "file" do |f|
          f.source = File.expand_path(file["from"])
          f.destination = file["to"].chomp('/') + "/" + file["from"].split('/').last
        end
      end
    end

    # Register All Of The Configured Shared Folders
    if settings.include? 'folders'
      settings["folders"].each do |folder|
        mount_opts = []

        if (folder["type"] == "nfs")
          mount_opts = folder["mount_options"] ? folder["mount_options"] : ['vers=3,udp,nolock,actimeo=1']
        elsif (folder["type"] == "smb")
          mount_opts = folder["mount_options"] ? folder["mount_options"] : ['vers=3.02', 'mfsymlinks']
        end

        # For b/w compatibility keep separate 'mount_opts', but merge with options
        options = (folder["options"] || {}).merge({ mount_options: mount_opts })

        # Double-splat (**) operator only works with symbol keys, so convert
        options.keys.each{|k| options[k.to_sym] = options.delete(k) }

        config.vm.synced_folder folder["map"], folder["to"], type: folder["type"] ||= nil, **options
      end
    end

    # 替换可变应用
    if settings.has_key?("reprovison") && settings["reprovison"]

      if settings.has_key?("reinstall") && settings["reinstall"]
        config.vm.provision "shell" do |s|
          s.path = scriptDir + "/clear-env.sh"
        end
      end

      # 拷贝卸载脚本
      config.vm.provision "file", source: "./scripts/remove", destination: "/home/vagrant/.remove"


      # 是否替换 PHP
=begin
      if settings.has_key?("php") && settings["php"]
        config.vm.provision "shell" do |s|
          s.path = scriptDir+  "/php/"+ settings["php"]+ ".sh"
        end
      end
=end

      # 是否替换 Mysql
      if settings.has_key?("mysql") && settings["mysql"]
        config.vm.provision "shell" do |s|
          s.path = scriptDir+  "/mysql/"+ settings["mysql"]+ ".sh"
        end
      end

      # 是否替换 Postgre
=begin
      if settings.has_key?("pgsql") && settings["pgsql"]
        config.vm.provision "shell" do |s|
          s.path = scriptDir+  "/pgsql/"+ settings["pgsql"]+ ".sh"
        end
      end
=end
    end


    # Install All The Configured Nginx Sites
    # 配置 nginx 域名网站
    config.vm.provision "shell" do |s|
      s.path = scriptDir + "/clear-serves.sh"
    end


    settings["sites"].each do |site|

      conf = site["conf"]

      config.vm.provision "shell" do |s|
        s.path = scriptDir + "/serve-init.sh"
        s.args = [conf]
      end

      site["servers"].each do |server|

        type = server["type"] ||= "laravel"

        if (server.has_key?("hhvm") && server["hhvm"])
          type = "hhvm"
        end

        if (type == "symfony")
          type = "symfony2"
        end

        config.vm.provision "shell" do |s|
          s.path = scriptDir + '/serves/' + "#{type}.sh"
          s.args = [conf, server["map"], server["to"], server["port"] ||= "80", server["ssl"] ||= "443"]
        end

        # Configure The Cron Schedule
        if (server.has_key?("schedule"))
          config.vm.provision "shell" do |s|
            if (server["schedule"])
              s.path = scriptDir + "/cron-schedule.sh"
              s.args = [server["map"].tr('^A-Za-z0-9', ''), server["to"]]
            else
              s.inline = "rm -f /etc/cron.d/$1"
              s.args = [server["map"].tr('^A-Za-z0-9', '')]
            end
          end
        end

      end
    end

    config.vm.provision "shell" do |s|
      s.path = scriptDir + "/reload-serves.sh"
    end

    # Configure All Of The Configured Databases
    if settings.has_key?("databases")
      settings["databases"].each do |database|
        name = database["name"]
        db = database["db"] ||= "mysql"
        config.vm.provision "shell" do |s|
          s.path = scriptDir + "/create-" + db + ".sh"
          s.args = [name]
        end
      end
    end

    # Update Composer On Every Provision
    config.vm.provision "shell" do |s|
      s.inline = "/usr/local/bin/composer self-update"
    end
  end
end