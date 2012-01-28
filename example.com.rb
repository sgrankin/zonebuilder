#!/usr/bin/env ruby

require './zonebuilder'

PUBLIC_IP = '1.1.1.1'

domain 'example.com' do
  view :internal
  view :external

  soa 'ns1'

  ip_external PUBLIC_IP
  ip_internal '192.168.1.1'
  ip6 '2001::1'

  prefix_internal '192.168.1'
  prefix6 '2001::/64'

  mx 10, :mx1

  ns_external 'ns1.example.org.'

  host :* do
    ip_external PUBLIC_IP
  end

  host :host1 do
    ip_internal '192.168.1.1'
    ip6 '2001::1'

    name :vpn
  end

  host :host2 do
    ip_internal '192.168.1.2'
    ip6 '2001::2'

    name :mail, :mx1, :www, :ns1
  end

  srv :kerberos, :udp, 0, 0, 88, :kdc1
  srv :kerberos, :tcp, 0, 0, 88, :kdc1
  srv 'kerberos-tls', :tcp, 0, 0, 88, :kdc1

  txt :_kerberos, 'EXAMPLE.COM'
end
