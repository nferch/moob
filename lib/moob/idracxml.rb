require 'nokogiri'
require 'tempfile'
require 'time'

module Moob
class IdracXml < BaseLom
  @name = 'Dell iDrac XML'

  INFO_FIELDS = %w[
    biosVer svcTag expSvcCode hostName
    osName osVersion sysDesc sysRev datetime initCountdown presentCountdown
    fwVersion fwUpdated LCCfwVersion
    firstBootDevice vmBootOnce
    racName hwVersionmacAddr recoveryAction
    NicEtherMac1  NicEtherMac2  NicEtherMac3  NicEtherMac4
    NiciSCSIMac1  NiciSCSIMac2  NiciSCSIMac3  NiciSCSIMac4
    NicEtherVMac1 NicEtherVMac2 NicEtherVMac3 NicEtherVMac4
    v4Enabled v4IPAddr v4Gateway v4NetMask
    v6Enabled v6Addr   v6Gateway v6Prefix v6LinkLocal
    v4DHCPEnabled v4DHCPServers v4DNS1 v4DNS2
    v6DHCPEnabled v6DHCPServers v6DNS1 v6DNS2
    v6SiteLocal v6SiteLocal3 v6SiteLocal4 v6SiteLocal5 v6SiteLocal6 v6SiteLocal7 v6SiteLocal8
    v6SiteLocal9 v6SiteLocal10 v6SiteLocal11 v6SiteLocal12 v6SiteLocal13 v6SiteLocal14 v6SiteLocal15
    ipmiLAN ipmiMinPriv hostname
  ]

  DISCOVER_XML_NODES = ['ENDPOINTTYPE', 'ENDPOINTVER', 'PROTOCOLTYPE', 'PROTOCOLVER']

  def initialize hostname, options = {}
    super hostname, options
    @username ||= 'root'
    @password ||= 'calvin'
    @arg = options[:arg]

    discover
  end

  def authenticate
    @session.handle_cookies nil
    start = @session.get 'start.html'
    raise ResponseError.new start unless start.status == 200

    auth = @session.post 'cgi-bin/login',
      "<?xml version='1.0'?><LOGIN><REQ><USERNAME>#{@username}</USERNAME><PASSWORD>#{@password}</PASSWORD></REQ></LOGIN>"
    raise ResponseError.new auth unless auth.status == 200

    auth.body =~ /<SID>([^<]+)<\/SID>/
    @sid = $1
    @session.headers['Cookie'] = "sid=#{@sid}"
    raise 'Cannot find auth result' unless $&
    raise "Auth failed with: \"#{auth.body}\"" unless $1.to_i > 0
    return self
  end

  def discover
    out = @session.get 'cgi-bin/discover'

    raise ResponseError.new out unless out.status == 200

    out_xml = Nokogiri::XML(out.body)

    raise "XML parse error" unless out_xml
    xml_result = {}

    DISCOVER_XML_NODES.each do |n|
      n_xml = out_xml.xpath("//#{n}")
      raise "Can't find #{n} node in XML" unless n_xml
      xml_result[n] = n_xml.first.content
    end

    raise "Unsupported iDRAC" unless xml_result['ENDPOINTTYPE'] =~ /^iDRAC[7-8]?$/
    raise "Unsupported iDRAC subversion" unless xml_result['ENDPOINTVER'] == '1.00'
    raise "Unsupported protocol type" unless xml_result['PROTOCOLTYPE'] == 'HTTPS'
    raise "Unsupported protocol version" unless xml_result['PROTOCOLVER'] == '2.0'
  end


  def logout
    out = @session.get 'cgi-bin/logout'
    raise ResponseError.new out unless out.status == 200
    return self
  end

  action :exec, 'Execute a command'
  def exec
    req = @session.post '/cgi-bin/exec',
      "<?xml version='1.0'?><EXEC><REQ><CMDINPUT>#{@arg}</CMDINPUT><MAXOUTPUTLEN>0x0fff</MAXOUTPUTLEN></REQ></EXEC>"

    out_xml = Nokogiri::XML(req.body)

    raise "XML parse error" unless out_xml

    rc_xml = out_xml.xpath("//CMDRC")

    raise "Cannot find RC XML node" unless rc_xml

    rc = rc_xml.first.content

    puts rc

    output_xml = out_xml.xpath("//CMDOUTPUT")

    raise "Cannot find output XML node" unless output_xml

    puts output_xml.first.content
    Moob.inform "foo"
    Moob.inform req.body
    return nil
  end


end
end
