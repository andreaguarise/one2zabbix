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

DS_GROUP = "one-hosts " + ONE_CONTROLLER
DS_TEMPLATE = "one-hosts-template"
DS_APPLICATION = "one-hosts-app"

zbx = ZabbixApi.connect(:url => ZBX_ENDPOINT, :user =>  ZBX_USER, :password => ZBX_PASSWORD)

# Ensure the host group we want exists.
zbx.hostgroups.get_or_create(:name => "#{DS_GROUP}")

# Now the template -- created templates are empty by default!
zbx.templates.get_or_create(:host => "#{DS_TEMPLATE}", :groups => [:groupid => zbx.hostgroups.get_id(:name => "#{DS_GROUP}")])

zbx.applications.get_or_create(
  :name => "#{DS_APPLICATION}",
  :hostid => zbx.templates.get_id(:host => "#{DS_TEMPLATE}")
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

puts host_pool.to_xml.to_s
exit 1

metrics = [
	{ :zbx_item_name => "ds_storage_total", :zbx_item_key => "ds.storage.total[aaa]", :path => "//TOTAL_MB", :zbx_type => "unsigned_int", :multiple=>false, :action=>:default },
	{ :zbx_item_name => "ds_storage_free", :zbx_item_key => "ds.storage.free[aaa]", :path => "//FREE_MB", :zbx_type => "unsigned_int", :multiple=>false, :action=>:default },
	{ :zbx_item_name => "ds_storage_used", :zbx_item_key => "ds.storage.used[aaa]", :path => "//USED_MB", :zbx_type => "unsigned_int", :multiple=>false, :action=>:default },
	{ :zbx_item_name => "ds_storage_images", :zbx_item_key => "ds.storage.images[aaa]", :path => "//IMAGES/ID", :zbx_type => "unsigned_int", :multiple=>true, :action=>:count },
]

metrics.each do |i|
	if i[:zbx_item_key] != nil
		puts "zbx_type: #{zbx_value_type_map[i[:zbx_type]]}"
		zbx.items.create_or_update(
  			:name => i[:zbx_item_name],
  			:key_ => i[:zbx_item_key],
  			:type => 2, #zabbix trapper
			:value_type => zbx_value_type_map[i[:zbx_type]],
  			:hostid => zbx.templates.get_id(:host => "#{DS_TEMPLATE}"),
  			:applications => [zbx.applications.get_id(:name => "#{DS_APPLICATION}")],
  			:trapper_hosts => "localhost,#{MON_HOST}"
		)
	end
end

puts ds_pool.to_xml.to_s
exit 1
ds_xml_doc = REXML::Document.new(ds_pool.to_xml.to_s)
ds_xml = REXML::XPath.match(ds_xml_doc,'//DATASTORE')
ds_xml.each do |ds|
	params_buff = {}	
	ds_params.each_pair do |k,v|
		ds_doc=REXML::Document.new(ds.to_s)
		result = REXML::XPath.first(ds_doc,v)
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
			:templateid => zbx.templates.get_id(:host => "#{DS_TEMPLATE}")
		}
		],
		:groups => [:groupid => zbx.hostgroups.get_id(:name => "#{DS_GROUP}")]
	)

	metrics.each do |s|
		buffer = ""
		ds_doc=REXML::Document.new(ds.to_s)
		if ( s[:multiple] )
			if ( s[:action] == :default )
			
				puts s[:path]
				result = REXML::XPath.match(ds_doc,s[:path])
				result.each do |r|
					buffer =  buffer + " " + r.text
				end
			end
			if ( s[:action] == :count )
				count = 0
				result = REXML::XPath.match(ds_doc,s[:path])
				result.each do |r|
					count =  count + 1
				end
				buffer = count.to_s
			end
		else
			result = REXML::XPath.first(ds_doc,s[:path])
			if ( result != nil ) 
				buffer =  result.text
			end
		end
		
		puts "item.name:#{s[:zbx_item_name]} -- path:#{s[:path]} ==> found:#{buffer}"
		puts "zabbix_sender -z #{ZBX_HOST} -s one-#{params_buff[:id]} -k #{s[:zbx_item_key]} -o #{buffer}"
		system("zabbix_sender -z #{ZBX_HOST} -s one-#{params_buff[:id]} -k #{s[:zbx_item_key]} -o #{buffer}")
		
	end
end

