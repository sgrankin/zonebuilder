require 'date'
require 'ostruct'

module ZoneBuilder
  def domain name, &block
    d = Domain.new name
    db = DomainBuilder.new d
    db.instance_eval &block

    zone_file = /^(.*):\d*:in `.*'$/.match(caller()[1])[1]
    serial = File.mtime(zone_file).to_i
    d.views.each do |view|
      make_zone d, serial, view
      make_rzone d, serial, view
      make_rzone6 d, serial, view
    end
  end

private
  class Host < OpenStruct
    def initialize name
      super()

      self.names = [name]
      self.ip = hash_with_views
      self.ip6 =hash_with_views
    end

    def name
      return names[0]
    end

    def hash_with_views
      return Hash.new {|h,k| h[k] = []}
    end
  end

  class HostBuilder
    def initialize host
      @h = host
    end

    def name *args
      @h.names += args.flatten
    end

    def ip ip, view = nil
      @h.ip[view] << ip
    end

    def ip6 ip, view = nil
      @h.ip6[view] << ip
    end

    def method_missing(symbol, *args, &block)
      case symbol
      when /(.*)_(.*)/
        send($1.to_sym, *(args + [$2.to_sym]))
      else
        super(symbol, *args, &block)
      end
    end
  end

  class Domain < Host
    def initialize fqdn
      super "@"

      fqdn += '.' unless name.end_with? '.'
      self.fqdn = fqdn
      self.filename = fqdn.chomp('.')
      self.ns = hash_with_views
      self.mx = hash_with_views
      self.hosts = {}
      self.views = []
      self.prefix = {}
      self.prefix6 = {}

      self.hostmaster = fq 'hostmaster'
    end

    def fq name
      name = name.to_s
      return name if name.end_with? '.'
      return name + '.' + self.fqdn
    end
  end

  class DomainBuilder < HostBuilder
    def initialize domain
      super domain
      @d = domain
    end

    def view name
      @d.views << name
    end

    def soa name
      @d.soa = @d.fq(name)
      ns name
    end

    def prefix p, view = nil
      @d.prefix[view] = p
    end

    def prefix6 p, view = nil
      @d.prefix6[view] = p
    end

    def mx pri, name, view = nil
      @d.mx[view] << [pri, @d.fq(name)]
    end

    def ns name, view = nil
      @d.ns[view] << @d.fq(name)
    end

    def host name, &block
      h = Host.new @d.fq(name)
      hb = HostBuilder.new h
      hb.instance_eval &block
      @d.hosts[name] = h
    end
  end

  def make_host io, host, default_host, view
    io.puts
    io.puts "; #{host.name}"
    host.names.each do |name|
      items_for_view(host.ip, view).each{|ip| io.puts "#{name}	A	#{ip}"}
      items_for_view(host.ip6, view).each{|ip| io.puts "#{name}	AAAA	#{ip}"}

      if default_host
        items_for_view(default_host.ip, view).each{|ip| io.puts "#{name}	A	#{ip}"}
        items_for_view(default_host.ip6, view).each{|ip| io.puts "#{name}	AAAA	#{ip}"}
      end
    end
  end

  def make_zone domain, serial, view
    zname = "db.#{domain.filename}@#{view}"

    open(zname, 'w') do |io|
      io.puts "$TTL 20m"
      io.puts "$ORIGIN #{domain.fqdn}"

      # times: slave refresh, retry, expire, negative cache
      io.puts "@	SOA	#{domain.soa} #{domain.hostmaster} (#{serial} 20m 3m 7d 20m)"

      items_for_view(domain.ns, view).each{|ns| io.puts "	NS	#{ns}" }
      items_for_view(domain.mx, view).each{|pri, name| io.puts "	MX	#{pri} #{name}"}

      make_host io, domain, nil, view

      domain.hosts.each do |name, host|
        next if name == :* # skip the default host
        make_host io, host, domain.hosts[:*], view
      end
    end
  end

  def make_rzone domain, serial, view
    prefix = domain.prefix[view] || domain.prefix[nil]
    return unless prefix

    zname = "db.#{domain.filename}@#{view}.rev"
    open(zname, 'w') do |io|
      io.puts "$TTL 20m"
      io.puts "$ORIGIN #{ip_to_arpa prefix}"

      # times: slave refresh, retry, expire, negative cache
      io.puts "@	SOA	#{domain.soa} #{domain.hostmaster} (#{serial} 20m 3m 7d 20m)"

      items_for_view(domain.ns, view).each{|ns| io.puts "	NS	#{ns}" }

      ptrs = {}
      domain.hosts.each do |name, host|
        items_for_view(host.ip, view).each{|ip| ptrs[ip] ||= host.name}
      end
      items_for_view(domain.ip, view).each{|ip| ptrs[ip] ||= domain.fqdn}

      ptrs.each do |ip, host|
        io.puts "#{ip_to_arpa ip}	IN	PTR	#{host}"
      end
    end
  end

  def make_rzone6 domain, serial, view
    prefix = domain.prefix6[view] || domain.prefix6[nil]
    return unless prefix

    zname = "db.#{domain.filename}@#{view}.rev6"
    open(zname, 'w') do |io|
      io.puts "$TTL 20m"
      io.puts "$ORIGIN #{ip6_to_arpa prefix}"

      # times: slave refresh, retry, expire, negative cache
      io.puts "@	SOA	#{domain.soa} #{domain.hostmaster} (#{serial} 20m 3m 7d 20m)"

      items_for_view(domain.ns, view).each{|ns| io.puts "	NS	#{ns}" }

      ptrs = {}
      domain.hosts.each do |name, host|
        items_for_view(host.ip6, view).each{|ip| ptrs[ip] ||= host.name}
      end
      items_for_view(domain.ip6, view).each{|ip| ptrs[ip] ||= domain.fqdn}

      ptrs.each do |ip, host|
        io.puts "#{ip6_to_arpa ip}	IN	PTR	#{host}"
      end
    end
  end

  def items_for_view hash, view
    return hash[nil] + hash[view]
  end

  def ip_to_arpa ip
    return ip.split('.').reverse.join('.') + '.in-addr.arpa.'
  end

  def ip6_to_arpa ip
    ip, length = ip.split '/'
    length = (length ? length.to_i : 128) / 4 # in nibbles

    # normalize :: by tacking 0 onto the appropriate end
    ip = '0' + ip if /^::/ =~ ip
    ip =  ip + '0' if /::$/ =~ ip

    # normalize each quad and split into nibbles
    nibs = ip.split(':')
    nibs.map!{|i| format('%04x',i.to_i(16)).chars.to_a unless i.empty?}
    nibs.flatten!

    # drop off any extra nibbles
    nibs = nibs[0...length]

    # expand the :: entry into 0s
    if nibs.index nil
      nibs[nibs.index nil] = ['0'] * (length - nibs.size + 1)
    end

    # and done
    return nibs.reverse.join('.') + '.ip6.arpa.'
  end

  extend self
end

def domain name, &block
  ZoneBuilder.domain name, &block
end
