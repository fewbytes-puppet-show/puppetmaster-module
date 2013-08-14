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
class puppetmaster ( $autosign = true ) {
	include puppetdb

	package{"unicorn": provider => gem }
	package{"puppetdb-terminus": }
	file{"/etc/puppet/puppet.conf":
		content => template("puppetmaster/puppet.conf.erb"),
		mode => 644,
	}
	class{"puppetdb::master::routes": notify => Service[puppetmaster]}
	class{"puppetdb::master::puppetdb_conf": notify => Service[puppetmaster], server => $ipaddress }
	file{"/etc/puppet/rack": ensure => directory, mode => 644, before => Service[puppetmaster]}
	file{"/etc/puppet/rack/public": ensure => directory, mode => 644, before => Service[puppetmaster]}
	file{"/etc/puppet/rack/config.ru": ensure => present, mode => 644, source => "puppet:///modules/puppetmaster/config.ru", before => Service[puppetmaster]}
	file{"/etc/puppet/rack/unicorn.rb": ensure => present, mode => 644, source => "puppet:///modules/puppetmaster/unicorn.rb", before => Service[puppetmaster] }
	file{"/etc/init/puppetmaster.conf":
		ensure => present,
		mode => 644,
		source => "puppet:///modules/puppetmaster/puppetmaster.upstart.conf", 
		notify => Service[puppetmaster]
	}
	exec{"puppet cert generate ${::fqdn} --dns_alt_names=${::hostname},${::ipaddress}": 
		path => "/usr/bin:/usr/local/bin:/bin",
		creates => "/var/lib/puppet/ssl/private_keys/${::fqdn}.pem"
	}
	->
	service{"puppetmaster": ensure => running}
	
	# make sure puppetdb has a valid cert
	exec{"/usr/sbin/puppetdb-ssl-setup":
		creates => "/etc/puppetdb/ssl/keystore.jks",
		require => Exec["puppet cert generate ${::fqdn} --dns_alt_names=${::hostname},${::ipaddress}"],
		notify => Service[puppetdb]
	}

	include apache
	include apache::mod::ssl
	include apache::mod::proxy
	include apache::mod::proxy_http
	include apache::mod::mime

	apache::mod{headers: }
	apache::vhost{"puppet":
		port  => 8140,
		ssl => true,
		ssl_cert => "/var/lib/puppet/ssl/certs/${::fqdn}.pem",
		ssl_key => "/var/lib/puppet/ssl/private_keys/${::fqdn}.pem",
		ssl_ca => "/var/lib/puppet/ssl/ca/ca_crt.pem",
		ssl_chain => "/var/lib/puppet/ssl/ca/ca_crt.pem",
		ssl_crl => "/var/lib/puppet/ssl/ca/ca_crl.pem",
		servername => $fqdn,
		docroot => "/etc/puppet/rack/public",
		custom_fragment => template("puppetmaster/apache.conf.erb")
	}
}
