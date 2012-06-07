module ZoneBuilder
public
  # Define a new zone.  Zonefiles will be created, named after the zone.
  #
  # @example
  #   require 'zone_builder'
  #   ZoneBuilder::domain 'example.com' do
  #     soa 'ns1'                           # SOA and NS for ns1.example.com.
  #
  #     view(:external) {ip '10.1.1.2'}     # external A record
  #     view(:internal) {ip '192.168.1.1'}  # internal A record
  #     ip6 '2001::1'                       # AAAA record, both internal and external
  #
  #     view(:internal) {net '192.168.1'}   # generate .rev zone for internal view only
  #     net6 '2001::/64'                    # generate .rev6 zone for both views
  #
  #     ns 'ns1.example.org.'               # @ NS ns1.example.org.
  #     mx 10, :mx1                         # @ MX mx1.example.com.
  #
  #     host :* do                          # defaults for hosts, e.g. if they all share one 'external' ip
  #       view(:external) {ip PUBLIC_IP}
  #     end
  #
  #     host :host1 do
  #       view(:internal) {ip '192.168.1.1'}
  #       ip6 '2001::1'
  #       cname :vpn, :www
  #     end
  #
  #     srv :kerberos, :udp, 0, 0, 88, :kdc1
  #     srv :kerberos, :tcp, 0, 0, 88, :kdc1
  #     srv 'kerberos-tls', :tcp, 0, 0, 88, :kdc1
  #
  #     txt :_kerberos, 'EXAMPLE.COM'
  #   end
  def self.domain name, &block
    d = Domain.new name
    d.instance_eval &block

    # use the mtime of the file calling this function to create a serial number
    zone_file = /^(.*):\d*:in `.*'$/.match(caller()[0])[1]
    serial = File.mtime(zone_file).to_i
    d.views.each do |view|
      make_zone d, serial, view
      make_rzone d, serial, view
      make_rzone6 d, serial, view
    end
  end

private
  # A view-based generic container of attributes and accessor methods
  class Node
    def initialize parent
      @parent = parent
      @views = Hash.new {|h,k| h[k] = {}}
      @current_view = nil
    end

    def rtype
      raise 'You must override Node.rtype'
    end

    def check_rtype rtype
      raise %{Unknown rtype #{rtype} on #{self}} unless self.rtypes.member? rtype
    end

    # append value to list of values for a view
    def add_value_in_view rtype, value, view
      self.check_rtype rtype
      if Enumerable === value
        # unwrap values with only one element
        value = value.count == 0 ? nil : value.count == 1 ? value[0] : value
      end
      @views[view][rtype] ||= []
      @views[view][rtype] << value
    end

    # get the list of values for a view, escalating to to the default view or a base node
    def get_value_in_view rtype, view
      self.check_rtype rtype
      v = @views[view][rtype] || []
      v += (@views[nil][rtype] || []) if view
      return v if v.count > 0
      return @parent.get_value_in_view rtype, view if @parent
      return []
    end

    # execute block scoped to a view
    def view view, &block
      @views[view]
      if block
        raise "Nested views not supported" if @current_view
        @current_view = view
        self.instance_eval &block
        @current_view = nil
      end
    end

    # for known rtypes, implement get and set methods
    def method_missing(symbol, *args, &block)
      return super(symbol, args, &block) unless self.rtypes.member? symbol
      if args.count == 0
        get_value_in_view symbol, @current_view
      else
        add_value_in_view symbol, args, @current_view
      end
    end
  end

  # A host within a domain
  class Host < Node
    attr_reader :name
    def initialize name, parent
      super parent
      @name = (name ? name.to_s : name)
    end

    def rtypes
      [:ip, :ip6, :cname]
    end

    def views
      @views.keys
    end
  end

  # A bind domain
  class Domain < Node
    def rtypes
      [:soa, :ip, :ip6, :mx, :ns, :net, :net6, :srv, :txt]
    end

    attr_reader :name, :fqdn, :filename, :hostmaster
    def initialize name
      super nil
      @fqdn = name
      @fqdn += '.' unless name.end_with? '.'
      @filename = fqdn.chomp('.')
      @hostmaster = qualify 'hostmaster'

      @hosts = {:* => Host.new(nil, nil)}
    end

    def host name, &block
      @hosts[name] ||= Host.new name, @hosts[:*]
      @hosts[name].instance_eval &block
    end

    def hosts
      return @hosts.values.reject {|h| h.name.nil?}
    end

    def views
      (@views.keys + @hosts.values.map {|h| h.views}).flatten.uniq.reject(&:nil?)
    end

    def qualify name
      name = name.to_s
      return name if name.end_with? '.'
      return name + '.' + @fqdn
    end
  end

  def self.make_zone domain, serial, view
    zname = "db.#{domain.filename}@#{view}"

    open(zname, 'w') do |io|
      io.puts "$TTL 20m"
      io.puts "$ORIGIN #{domain.fqdn}"

      # times: slave refresh, retry, expire, negative cache
      io.puts "@ SOA #{domain.qualify domain.soa[0]} #{domain.hostmaster} (#{serial} 20m 3m 7d 20m)"
      io.puts "@ NS #{domain.qualify domain.soa[0]}"

      domain_formats = {
        ip: "@ A %s",
        ip6: "@ AAAA %s",
        mx: "@ MX %s %s",
        ns: "@ NS %s",
        srv: "_%s._%s SRV %s %s %s %s",
        txt: "%s TXT \"%s\"",
      }

      domain_formats.each do |key, format|
        domain.get_value_in_view(key, view).each do |value|
          io.puts(format % value)
        end
      end

      host_formats = {
        ip: "%s A %s",
        ip6: "%s AAAA %s",
      }

      domain.hosts.each do |host|
        io.puts
        io.puts "; #{host.name}"
        ([host.name] + host.cname.flatten).each do |name|
          host_formats.each do |key, format|
            host.get_value_in_view(key, view).each do |value|
              io.puts(format % [name, value])
            end
          end
        end
      end
    end
  end

  def self.make_rzone domain, serial, view
    net = domain.get_value_in_view(:net, view).first
    return unless net

    zname = "db.#{domain.filename}@#{view}.rev"
    open(zname, 'w') do |io|
      io.puts "$TTL 20m"
      io.puts "$ORIGIN #{ip_to_arpa net}"

      # times: slave refresh, retry, expire, negative cache
      io.puts "@ SOA #{domain.qualify domain.soa[0]} #{domain.hostmaster} (#{serial} 20m 3m 7d 20m)"
      io.puts "@ NS #{domain.qualify domain.soa[0]}"

      domain_formats = {
        ns: "@ NS %s",
      }

      domain_formats.each do |key, format|
        domain.get_value_in_view(key, view).each do |value|
          io.puts(format % (domain.qualify value))
        end
      end

      ptrs = {}
      domain.hosts.each do |host|
        host.get_value_in_view(:ip, view).each {|ip| ptrs[ip] ||= host.name}
      end
      domain.get_value_in_view(:ip, view).each {|ip| ptrs[ip] ||= domain.fqdn}

      ptrs.each do |ip, host|
        io.puts "#{ip_to_arpa ip} IN PTR #{domain.qualify host}"
      end
    end
  end

  def self.make_rzone6 domain, serial, view
    net = domain.get_value_in_view(:net6, view).first
    return unless net

    zname = "db.#{domain.filename}@#{view}.rev6"
    open(zname, 'w') do |io|
      io.puts "$TTL 20m"
      io.puts "$ORIGIN #{ip6_to_arpa net}"

      # times: slave refresh, retry, expire, negative cache
      io.puts "@ SOA #{domain.qualify domain.soa[0]} #{domain.hostmaster} (#{serial} 20m 3m 7d 20m)"
      io.puts "@ NS #{domain.qualify domain.soa[0]}"

      domain_formats = {
        ns: "@ NS %s",
      }

      domain_formats.each do |key, format|
        domain.get_value_in_view(key, view).each do |value|
          io.puts(format % (domain.qualify value))
        end
      end

      ptrs = {}
      domain.hosts.each do |host|
        host.get_value_in_view(:ip6, view).each {|ip| ptrs[ip] ||= host.name}
      end
      domain.get_value_in_view(:ip6, view).each {|ip| ptrs[ip] ||= domain.fqdn}

      ptrs.each do |ip, host|
        io.puts "#{ip6_to_arpa ip} IN PTR #{domain.qualify host}"
      end
    end
  end

  def self.ip_to_arpa ip
    return ip.split('.').reverse.join('.') + '.in-addr.arpa.'
  end

  def self.ip6_to_arpa ip
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
end
