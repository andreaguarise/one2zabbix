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

HOST_GROUP = "one-hosts " + ONE_CONTROLLER
HOST_TEMPLATE = "one-hosts-template"
HOST_APPLICATION = "one-hosts-app"

zbx = ZabbixApi.connect(:url => ZBX_ENDPOINT, :user =>  ZBX_USER, :password => ZBX_PASSWORD)

# Ensure the host group we want exists.
zbx.hostgroups.get_or_create(:name => "#{HOST_GROUP}")

# Now the template -- created templates are empty by default!
zbx.templates.get_or_create(:host => "#{HOST_TEMPLATE}", :groups => [:groupid => zbx.hostgroups.get_id(:name => "#{HOST_GROUP}")])

zbx.applications.get_or_create(
  :name => "#{HOST_APPLICATION}",
  :hostid => zbx.templates.get_id(:host => "#{HOST_TEMPLATE}")
)

client = Client.new(ONE_CREDENTIALS, ONE_ENDPOINT)

host_pool = HostPool.new(client)

rc = host_pool.info
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

host_params = {
	:id => "//ID" ,
	:name => "//NAME",
}

metrics = [
	{ :zbx_item_name => "host_mem_used", :zbx_item_key => "host.mem.used", :path => "//HOST_SHARE/USED_MEM", :zbx_type => "unsigned_int", :multiple=>false, :action=>:default },
	{ :zbx_item_name => "host_mem_total", :zbx_item_key => "host.mem.total", :path => "//HOST_SHARE/MAX_MEM", :zbx_type => "unsigned_int", :multiple=>false, :action=>:default },
	{ :zbx_item_name => "host_mem_free", :zbx_item_key => "host.mem.free", :path => "//HOST_SHARE/FREE_MEM", :zbx_type => "unsigned_int", :multiple=>false, :action=>:default },
	{ :zbx_item_name => "host_cpu_used", :zbx_item_key => "host.cpu.used", :path => "//HOST_SHARE/CPU_USAGE", :zbx_type => "unsigned_int", :multiple=>false, :action=>:default },
	{ :zbx_item_name => "host_cpu_total", :zbx_item_key => "host.cpu.total", :path => "//HOST_SHARE/MAX_CPU", :zbx_type => "unsigned_int", :multiple=>false, :action=>:default },
	{ :zbx_item_name => "host_cpu_free", :zbx_item_key => "host.cpu.free", :path => "//HOST_SHARE/FREE_CPU", :zbx_type => "unsigned_int", :multiple=>false, :action=>:default },
	{ :zbx_item_name => "host_storage_used", :zbx_item_key => "host.storage.used", :path => "//HOST_SHARE/USED_DISK", :zbx_type => "unsigned_int", :multiple=>false, :action=>:default },
  { :zbx_item_name => "host_storage_total", :zbx_item_key => "host.storage.total", :path => "//HOST_SHARE/MAX_DISK", :zbx_type => "unsigned_int", :multiple=>false, :action=>:default },
  { :zbx_item_name => "host_storage_free", :zbx_item_key => "host.storage.free", :path => "//HOST_SHARE/FREE_DISK", :zbx_type => "unsigned_int", :multiple=>false, :action=>:default },
	{ :zbx_item_name => "host_vm_running", :zbx_item_key => "host.vm.running", :path => "//HOST_SHARE/RUNNING_VMS", :zbx_type => "unsigned_int", :multiple=>false, :action=>:default }
]

metrics.each do |i|
	if i[:zbx_item_key] != nil
		puts "zbx_type: #{zbx_value_type_map[i[:zbx_type]]}"
		zbx.items.create_or_update(
  			:name => i[:zbx_item_name],
  			:key_ => i[:zbx_item_key],
  			:type => 2, #zabbix trapper
			  :value_type => zbx_value_type_map[i[:zbx_type]],
  			:hostid => zbx.templates.get_id(:host => "#{HOST_TEMPLATE}"),
  			:applications => [zbx.applications.get_id(:name => "#{HOST_APPLICATION}")],
  			:trapper_hosts => "localhost,#{MON_HOST}"
		)
	end
end

host_xml_doc = REXML::Document.new(host_pool.to_xml.to_s)
host_xml = REXML::XPath.match(host_xml_doc,'//HOST')
host_xml.each do |ds|
	params_buff = {}	
	host_params.each_pair do |k,v|
		host_doc=REXML::Document.new(ds.to_s)
		result = REXML::XPath.first(host_doc,v)
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
			:templateid => zbx.templates.get_id(:host => "#{HOST_TEMPLATE}")
		}
		],
		:groups => [:groupid => zbx.hostgroups.get_id(:name => "#{HOST_GROUP}")]
	)

	metrics.each do |s|
		buffer = ""
		host_doc=REXML::Document.new(ds.to_s)
		if ( s[:multiple] )
			if ( s[:action] == :default )
			
				puts s[:path]
				result = REXML::XPath.match(host_doc,s[:path])
				result.each do |r|
					buffer =  buffer + " " + r.text
				end
			end
			if ( s[:action] == :count )
				count = 0
				result = REXML::XPath.match(host_doc,s[:path])
				result.each do |r|
					count =  count + 1
				end
				buffer = count.to_s
			end
		else
			result = REXML::XPath.first(host_doc,s[:path])
			if ( result != nil ) 
				buffer =  result.text
			end
		end
		
		puts "item.name:#{s[:zbx_item_name]} -- path:#{s[:path]} ==> found:#{buffer}"
		puts "zabbix_sender -z #{ZBX_HOST} -s one-#{params_buff[:id]} -k #{s[:zbx_item_key]} -o #{buffer}"
		system("zabbix_sender -z #{ZBX_HOST} -s one-#{params_buff[:id]} -k #{s[:zbx_item_key]} -o #{buffer}")
		
	end
end

