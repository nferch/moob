require 'nokogiri'
require 'tempfile'
require 'time'

module Moob
class IdracXml < BaseLom
  @name = 'Dell iDrac XML'

  DISCOVER_XML_NODES = ['ENDPOINTTYPE', 'ENDPOINTVER', 'PROTOCOLTYPE', 'PROTOCOLVER']

  def initialize hostname, options = {}
    super hostname, options
    @username ||= 'root'
    @password ||= 'calvin'
    @arg = options[:arg]

    discover
  end

  def xml_request method, uri, data
    out = @session.send(method, uri, data)

    raise ResponseError.new resp unless out.status == 200

    out_xml = Nokogiri::XML(out.body)

    raise "Cannot parse XML response for request to #{uri}" unless out_xml

    resp_xml = out_xml.xpath("//RESP")

    raise "Cannot find response XML node in response to #{uri}" unless resp_xml

    resp_xml.children.each do |n|
      puts n.inspect
    end
  end

  def authenticate
    @session.handle_cookies nil
    resp = xml_request 'post', 'cgi-bin/login',
      "<?xml version='1.0'?><LOGIN><REQ><USERNAME>#{@username}</USERNAME><PASSWORD>#{@password}</PASSWORD></REQ></LOGIN>"

    raise "Session ID missing from response" unless resp.include?('SID')

    @sid = resp['SID']
    @session.headers['Cookie'] = "sid=#{@sid}"
    raise "Auth failed with: \"#{auth.body}\"" unless @sid.to_i != 0
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

    rc_s = rc_xml.first.content

    rc = Integer(rc_s)

    output_xml = out_xml.xpath("//CMDOUTPUT")

    raise "Cannot find output XML node" unless output_xml

    if rc != 0
      Moob.warn "exec returned rc #{rc}"
    end
    puts output_xml.first.content
    return nil
  end


end
end
