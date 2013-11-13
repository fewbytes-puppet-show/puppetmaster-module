# == Class: puppetmaster
#
# Full description of class puppetmaster here.
#
# === Parameters
#
# Document parameters here.
#
# [*sample_parameter*]
#   Explanation of what this parameter affects and what it defaults to.
#   e.g. "Specify one or more upstream ntp servers as an array."
#
# === Variables
#
# Here you should define a list of variables that this module would require.
#
# [*sample_variable*]
#   Explanation of how this variable affects the funtion of this class and if it
#   has a default. e.g. "The parameter enc_ntp_servers must be set by the
#   External Node Classifier as a comma separated list of hostnames." (Note,
#   global variables should not be used in preference to class parameters  as of
#   Puppet 2.6.)
#
# === Examples
#
#  class { puppetmaster:
#    servers => [ 'pool.ntp.org', 'ntp.local.company.com' ]
#  }
#
# === Authors
#
# Author Name <author@domain.com>
#
# === Copyright
#
# Copyright 2013 Your name here, unless otherwise noted.
#
class puppetmaster ( 
	$autosign				 = true,
	$service_ip				 = $ipaddress,
	$files_repo              = "/srv/puppet/files",
	$fileserver_extra_mounts = [],
	$use_rubygems            = true
	) {

	if $::fqdn == undef or $::fqdn == "" {
		warning("fqdn not defined, using hostname instead")
		$fqdn_real = downcase($::hostname)
	} else {
		$fqdn_real = downcase($::fqdn)
	}

	include puppetdb
	
	if $use_rubygems {
		include ruby::dev
		package{"unicorn": provider => gem }
	} else {
		package{"rubygem-unicorn": alias => "unicorn"}
	}
	package{"puppetdb-terminus": }
	file{"/etc/puppet/puppet.conf":
		content => template("puppetmaster/puppet.conf.erb"),
		mode => 644,
		notify => Service[puppetmaster]
	}
	file{"/etc/puppet/fileserver.conf":
		content => template("puppetmaster/fileserver.conf.erb"),
		mode => 644,
		notify => Service[puppetmaster]
	}
	file{"/etc/puppet/auth.conf":
		content => template("puppetmaster/auth.conf.erb"),
		mode => 644,
		notify => Service[puppetmaster]
	}
	file{[dirname($files_repo), "$files_repo"]:
		ensure => directory
	}
	class{"puppetdb::master::routes": notify => Service[puppetmaster]}
	class{"puppetdb::master::puppetdb_conf": notify => Service[puppetmaster], server => $hostname }
	file{"/etc/puppet/rack": ensure => directory, mode => 644, before => Service[puppetmaster]}
	file{"/etc/puppet/rack/public": ensure => directory, mode => 644, before => Service[puppetmaster]}
	file{"/etc/puppet/rack/config.ru": ensure => present, mode => 644, source => "puppet:///modules/puppetmaster/config.ru", before => Service[puppetmaster]}
	file{"/etc/puppet/rack/unicorn.rb": ensure => present, mode => 644, source => "puppet:///modules/puppetmaster/unicorn.rb", before => Service[puppetmaster] }

	exec{"puppet cert generate ${::fqdn} --dns_alt_names=${::hostname},${service_ip}": 
		path => "/usr/bin:/usr/local/bin:/bin",
		creates => "/var/lib/puppet/ssl/private_keys/${::fqdn}.pem"
	}
	->
	upstart::service{"puppetmaster":
		chdir => "/etc/puppet/rack",
		exec => "unicorn -c /etc/puppet/rack/unicorn.rb /etc/puppet/rack/config.ru",
		require => Package[unicorn]
	}
		
	# make sure puppetdb has a valid cert
	exec{"/usr/sbin/puppetdb-ssl-setup":
		creates => "/etc/puppetdb/ssl/keystore.jks",
		require => Exec["puppet cert generate ${::fqdn} --dns_alt_names=${::hostname},${service_ip}"],
		notify => Service[puppetdb]
	}

	include apache
	include apache::mod::ssl
	include apache::mod::proxy
	include apache::mod::proxy_http
	include apache::mod::mime
	include apache::mod::headers

	apache::vhost{"puppet":
		port  => 8140,
		ssl => true,
		ssl_cert => "/var/lib/puppet/ssl/certs/${fqdn_real}.pem",
		ssl_key => "/var/lib/puppet/ssl/private_keys/${fqdn_real}.pem",
		ssl_ca => "/var/lib/puppet/ssl/ca/ca_crt.pem",
		ssl_chain => "/var/lib/puppet/ssl/ca/ca_crt.pem",
		ssl_crl => "/var/lib/puppet/ssl/ca/ca_crl.pem",
		servername => $fqdn,
		docroot => "/etc/puppet/rack/public",
		proxy_pass => [{path => "/", url => "http://localhost:3000/"}],
		request_headers => [
			"unset X-Forwarded-For",
			"set X-SSL-Subject %{SSL_CLIENT_S_DN}e",
        	"set X-Client-DN %{SSL_CLIENT_S_DN}e",
        	"set X-Client-Verify %{SSL_CLIENT_VERIFY}e"
		],
		custom_fragment => template("puppetmaster/apache.conf.erb")
	}
}
