#!/usr/bin/ruby

##############################################################################
# Environment Configuration
##############################################################################
ONE_LOCATION=ENV["ONE_LOCATION"]

if !ONE_LOCATION
    RUBY_LIB_LOCATION="/usr/lib/one/ruby"
else
    RUBY_LIB_LOCATION=ONE_LOCATION+"/lib/ruby"
end

$: << RUBY_LIB_LOCATION

require 'rubygems'
require 'opennebula'
require 'zabbixapi'
require 'rexml/document'

require 'mon_config'

include OpenNebula

GUEST_GROUP = "one-guests one-master.to.infn.it"
GUEST_TEMPLATE = "one-guests-template"
GUEST_APPLICATION = "one-guests-app"
IAAS_GROUP = "one-IaaS"
IAAS_TEMPLATE = "one-IaaS-template"
IAAS_APPLICATION = "one-IaaS-app"

zbx = ZabbixApi.connect(:url => ZBX_ENDPOINT, :user =>  ZBX_USER, :password => ZBX_PASSWORD)

# Ensure the host group we want exists.
zbx.hostgroups.get_or_create(:name => "#{GUEST_GROUP}")
zbx.hostgroups.get_or_create(:name => "#{IAAS_GROUP}")

# Now the template -- created templates are empty by default!
zbx.templates.get_or_create(:host => "#{GUEST_TEMPLATE}", :groups => [:groupid => zbx.hostgroups.get_id(:name => "#{GUEST_GROUP}")])
zbx.templates.get_or_create(:host => "#{IAAS_TEMPLATE}", :groups => [:groupid => zbx.hostgroups.get_id(:name => "#{IAAS_GROUP}")])

zbx.applications.get_or_create(
  :name => "#{GUEST_APPLICATION}",
  :hostid => zbx.templates.get_id(:host => "#{GUEST_TEMPLATE}")
)

zbx.applications.get_or_create(
  :name => "#{IAAS_APPLICATION}",
  :hostid => zbx.templates.get_id(:host => "#{IAAS_TEMPLATE}")
)

client = Client.new(ONE_CREDENTIALS, ONE_ENDPOINT)

vm_pool = VirtualMachinePool.new(client, -1)

rc = vm_pool.info_all
if OpenNebula.is_error?(rc)
     puts rc.message
     exit -1
end

zbx_value_type_map = {
	"float" => 0,
	"char" => 1,
	"log" => 2,
	"unsigned_int" => 3,
	"text" => 4 
}

guest_params = {
	:id => "//ID" ,
	:name => "//NAME",
}

guest_metrics = [
	{ :zbx_item_name => "vm_cpu_used", :zbx_item_key => "vm.cpu.used", :path => "//CPU", :zbx_type => "unsigned_int", :multiple=>false },
	{ :zbx_item_name => "vm_cpu_assigned", :zbx_item_key => "vm.cpu.assigned", :path => "//TEMPLATE/CPU", :zbx_type => "float", :multiple=>false },
	{ :zbx_item_name => "vm_net_tx", :zbx_item_key => "vm.net.tx", :path => "//NET_TX", :zbx_type => "unsigned_int", :multiple=>false },
	{ :zbx_item_name => "vm_net_rx", :zbx_item_key => "vm.net.rx", :path => "//NET_RX", :zbx_type => "unsigned_int", :multiple=>false },
	{ :zbx_item_name => "vm_memory_used", :zbx_item_key => "vm.memory.used", :path => "//MEMORY", :zbx_type => "unsigned_int", :multiple=>false },
	{ :zbx_item_name => "vm_memory_assigned", :zbx_item_key => "vm.memory.assigned", :path => "//TEMPLATE/MEMORY", :zbx_type => "unsigned_int", :multiple=>false },
	{ :zbx_item_name => "vm_disk_name", :zbx_item_key => "vm.disk.name", :path => "//TEMPLATE/DISK/IMAGE", :zbx_type => "char", :multiple=>true }
]

iaas_metrics = [
	{ :zbx_item_name => "CPU assigned", :zbx_item_key => 'grpsum["'+ GUEST_GROUP + '","vm.cpu.assigned",last,0]', :path => "", :zbx_type => "float", :multiple=>false },
	{ :zbx_item_name => "CPU used", :zbx_item_key => 'grpsum["'+ GUEST_GROUP + '","vm.cpu.used",last,0]', :path => "", :zbx_type => "unsigned_int", :multiple=>false },
	{ :zbx_item_name => "Memory assigned", :zbx_item_key => 'grpsum["'+ GUEST_GROUP + '","vm.memory.assigned",last,0]', :path => "", :zbx_type => "unsigned_int", :multiple=>false },
	{ :zbx_item_name => "Memory used", :zbx_item_key => 'grpsum["'+ GUEST_GROUP + '","vm.memory.used",last,0]', :path => "", :zbx_type => "unsigned_int", :multiple=>false }
]



guest_metrics.each do |metric|
	if metric[:zbx_item_key] != nil
		puts "zbx_type: #{zbx_value_type_map[metric[:zbx_type]]}"
		zbx.items.create_or_update(
  			:name => metric[:zbx_item_name],
  			:key_ => metric[:zbx_item_key],
  			:type => 2, #zabbix trapper
			:value_type => zbx_value_type_map[metric[:zbx_type]],
  			:hostid => zbx.templates.get_id(:host => "#{GUEST_TEMPLATE}"),
 # 			:applications => [zbx.applications.get_id(:name => "#{GUEST_APPLICATION}")],
  			:trapper_hosts => "localhost,#{MON_HOST}"
		)
	end
end

iaas_metrics.each do |metric|
	if metric[:zbx_item_key] != nil
		puts "zbx_type: #{zbx_value_type_map[metric[:zbx_type]]}"
		zbx.items.create_or_update(
  			:name => metric[:zbx_item_name],
  			:key_ => metric[:zbx_item_key],
  			:type => 8, #zabbix aggregate
			:value_type => zbx_value_type_map[metric[:zbx_type]],
  			:hostid => zbx.templates.get_id(:host => "#{IAAS_TEMPLATE}"),
 # 			:applications => [zbx.applications.get_id(:name => "#{IAAS_APPLICATION}")],
  			:trapper_hosts => "localhost,#{MON_HOST}"
		)
	end
end

vm_xml_doc = REXML::Document.new(vm_pool.to_xml.to_s)
vm_xml = REXML::XPath.match(vm_xml_doc,'//VM')
vm_xml.each do |vm|
	params_buff = {}	
	guest_params.each_pair do |k,v|
		vm_doc=REXML::Document.new(vm.to_s)
		result = REXML::XPath.first(vm_doc,v)
		buffer =  result.text
		puts "host_params key:#{k} ==> value:#{buffer}"
		params_buff[k] = buffer
	end
	zbx.hosts.create_or_update(
		:host => "one-#{params_buff[:id]}",
		:name => "one-#{params_buff[:id]}-#{params_buff[:name]}",
  			:interfaces => [
    			{
      				:type => 1,
      				:main => 1,
      				:ip => '0.0.0.0',
      				:dns => '0.0.0.0',
      				:port => 10050,
     	 			:useip => 0,
				:usedns => 0
    			}
		],
		:templates => [ 
		{
			:templateid => zbx.templates.get_id(:host => "#{GUEST_TEMPLATE}")
		}
		],
		:groups => [:groupid => zbx.hostgroups.get_id(:name => "#{GUEST_GROUP}")]
	)

	guest_metrics.each do |s|
		buffer = ""
		vm_doc=REXML::Document.new(vm.to_s)
		if ( s[:multiple] )
			result = REXML::XPath.match(vm_doc,s[:path])
			result.each do |r|
				buffer =  buffer + " " + r.text
			end
		else
			result = REXML::XPath.first(vm_doc,s[:path])
			buffer =  result.text
		end
		
		puts "item.name:#{s[:zbx_item_name]} -- path:#{s[:path]} ==> found:#{buffer}"
		puts "zabbix_sender -z #{ZBX_HOST} -s one-#{params_buff[:id]} -k #{s[:zbx_item_key]} -o #{buffer}"
		system("zabbix_sender -z #{ZBX_HOST} -s one-#{params_buff[:id]} -k #{s[:zbx_item_key]} -o #{buffer}")
		
	end
end

