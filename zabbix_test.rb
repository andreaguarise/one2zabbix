#!/usr/bin/ruby
require 'rubygems'
require 'rubix'
Rubix.connect('http://192.135.19.27/zabbix/api_jsonrpc.php', 'Admin', 'zabbix')

# Ensure the host group we want exists.
host_group = Rubix::HostGroup.find_or_create(:name => "Test Zabbix Hosts")
