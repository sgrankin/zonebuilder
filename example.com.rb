#!/usr/bin/env ruby
$LOAD_PATH.unshift File.dirname(__FILE__)

require 'zone_builder'

PUBLIC_IP = '1.1.1.1'

ZoneBuilder::domain 'example.com' do
  soa 'ns1'

  view(:external) {ip PUBLIC_IP}
  view(:internal) {ip '192.168.1.1'}
  ip6 '2001::1'

  view(:internal) {net '192.168.1'}
  net6 '2001::/64'

  mx 10, :mx1

  view(:external) {ns 'ns1.example.org.'}

  host :* do
    view(:external) {ip PUBLIC_IP}
  end

  host :host1 do
    view(:internal) {ip '192.168.1.1'}
    ip6 '2001::1'
    cname :vpn
  end

  host :host2 do
    view(:internal) {ip '192.168.1.2'}
    ip6 '2001::2'
    cname :mail, :mx1, :www, :ns
  end

  srv :kerberos, :udp, 0, 0, 88, :kdc1
  srv :kerberos, :tcp, 0, 0, 88, :kdc1
  srv 'kerberos-tls', :tcp, 0, 0, 88, :kdc1

  txt :_kerberos, 'EXAMPLE.COM'
end
