# $Id: xmlrpc.rb,v 1.8 2007-03-14 08:49:00 znz Exp $

require 'xmlrpc/server'
require 'hiki/plugin'

module Hiki
  module XMLRPCHandler
    module_function

    def init_handler(server, cgi_class=CGI)
      server.add_handler('wiki.getPage') do |page|
        page = utf8_to_euc( page )
        conf = Hiki::Config::new
        db = Hiki::HikiDB::new( conf )
        ret = db.load( page )
        unless ret
          raise XMLRPC::FaultException.new(1, "No such page was found.")
        end
        XMLRPC::Base64.new( euc_to_utf8( ret ) )
      end

      server.add_handler('wiki.getPageInfo') do |page|
        page = utf8_to_euc( page )
        conf = Hiki::Config::new
        db = Hiki::HikiDB::new( conf )
        title = db.get_attribute( page, :title )
        title = page if title.nil? || title.empty?
        {
          'title' => XMLRPC::Base64.new( euc_to_utf8( title ) ),
          'keyword' => db.get_attribute( page, :keyword ).collect { |k| XMLRPC::Base64.new( euc_to_utf8( k ) ) },
          'md5hex' => db.md5hex( page ),
          'lastModified' => db.get_attribute( page, :last_modified ).getutc,
          'author' => XMLRPC::Base64.new( db.get_attribute( page, :editor ) || '' )
        }
      end

      server.add_handler('wiki.putPage') do |page, content, attributes|
        page = utf8_to_euc( page )
        content = utf8_to_euc( content )
        attributes ||= {}
        attributes.each_pair { |k, v|
          case v
          when String
            v.replace( utf8_to_euc( v ) )
          when Array
            v.map!{ |s| s.replace( utf8_to_euc( s ) ) }
          end
        }
        conf = Hiki::Config::new
        cgi = cgi_class::new
        cgi.params['c'] = ['save']
        cgi.params['p'] = [page]
        db = Hiki::HikiDB::new( conf )
        options = conf.options || Hash::new( '' )
        options['page'] = page
        options['cgi']  = cgi
        options['db']  = db
        options['params'] = Hash::new( [] )
        plugin = Hiki::Plugin::new( options, conf )
        plugin.login( attributes['name'], attributes['password'] )

        unless plugin.editable?( page )
          raise XMLRPC::FaultException.new(10, "can't edit this page.")
        end

        md5hex = attributes['md5hex'] || db.md5hex( page )
        update_timestamp = !attributes['minoredit']
        unless plugin.save( page, content.gsub( /\r/, '' ), md5hex, update_timestamp )
          raise XMLRPC::FaultException.new(11, "save failed.")
        end
        keyword = attributes['keyword'] || db.get_attribute( page, :keyword )
        title = attributes['title']
        attr = [[:keyword, keyword.uniq], [:editor, plugin.user]]
        attr << [:title, title] if title
        db.set_attribute(page, attr)
        if plugin.admin? && attributes.has_key?( 'freeze' )
          db.freeze_page( page, attributes['freeze'] ? true : false)
        end
        true
      end

      server.add_handler('wiki.getAllPages') do
        conf = Hiki::Config::new
        db = Hiki::HikiDB::new( conf )
        db.pages.collect{|p| XMLRPC::Base64.new( euc_to_utf8( p ) )}
      end

      #add_multicall
      #add_introspection
    end
  end

  class XMLRPCServer
    include XMLRPCHandler

    def initialize(xmlrpc_enabled)
      return unless xmlrpc_enabled

      if defined?(MOD_RUBY)
        @server = XMLRPC::ModRubyServer.new
      else
        @server = XMLRPC::CGIServer.new
      end

      init_handler(@server)
    end

    def serve
      @server.serve
    end
  end
end
