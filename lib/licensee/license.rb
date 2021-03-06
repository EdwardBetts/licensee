require 'uri'

module Licensee
  class InvalidLicense < ArgumentError; end
  class License
    @all = {}
    @keys_licenses = {}

    class << self
      # All license objects defined via Licensee (via choosealicense.com)
      #
      # Options:
      # - :hidden - boolean, return hidden licenses (default: false)
      # - :featured - boolean, return only (non)featured licenses (default: all)
      #
      # Returns an Array of License objects.
      def all(options = {})
        @all[options] ||= begin
          options = { hidden: false, featured: nil }.merge(options)
          output = licenses.dup
          output.reject!(&:hidden?) unless options[:hidden]
          return output if options[:featured].nil?
          output.select { |l| l.featured? == options[:featured] }
        end
      end

      def keys
        @keys ||= license_files.map do |license_file|
          ::File.basename(license_file, '.txt').downcase
        end + PSEUDO_LICENSES
      end

      def find(key, options = {})
        options = { hidden: true }.merge(options)
        keys_licenses(options)[key.downcase]
      end
      alias [] find
      alias find_by_key find

      def license_dir
        dir = ::File.dirname(__FILE__)
        ::File.expand_path '../../vendor/choosealicense.com/_licenses', dir
      end

      def license_files
        @license_files ||= Dir.glob("#{license_dir}/*.txt")
      end

      private

      def licenses
        @licenses ||= keys.map { |key| new(key) }
      end

      def keys_licenses(options = {})
        @keys_licenses[options] ||= all(options).map { |l| [l.key, l] }.to_h
      end
    end

    attr_reader :key

    # Preserved for backwards compatability
    YAML_DEFAULTS = Licensee::LicenseMeta.members

    # Pseudo-license are license placeholders with no content
    #
    # `other` - The project had a license, but we were not able to detect it
    # `no-license` - The project is not licensed (e.g., all rights reserved)
    #
    # Note: A lack of detected license will be a nil license
    PSEUDO_LICENSES = %w[other no-license].freeze

    include Licensee::ContentHelper
    extend Forwardable
    def_delegators :meta, *LicenseMeta.helper_methods

    def initialize(key)
      @key = key.downcase
    end

    # Path to vendored license file on disk
    def path
      @path ||= File.expand_path "#{@key}.txt", Licensee::License.license_dir
    end

    # License metadata from YAML front matter with defaults merged in
    def meta
      @meta ||= LicenseMeta.from_yaml(yaml)
    end

    # Returns the human-readable license name
    def name
      title ? title : key.capitalize
    end

    def name_without_version
      /(.+?)(( v?\d\.\d)|$)/.match(name)[1]
    end

    def other?
      key == 'other'
    end

    def gpl?
      key == 'gpl-2.0' || key == 'gpl-3.0'
    end

    def lgpl?
      key == 'lgpl-2.1' || key == 'lgpl-3.0'
    end

    # Is this license a Creative Commons license?
    def creative_commons?
      key.start_with?('cc-')
    end

    # The license body (e.g., contents - frontmatter)
    def content
      @content ||= parts[2] if parts && parts[2]
    end
    alias to_s content
    alias text content
    alias body content

    def url
      URI.join(Licensee::DOMAIN, "/licenses/#{key}/").to_s
    end

    def ==(other)
      !other.nil? && key == other.key
    end

    def pseudo_license?
      PSEUDO_LICENSES.include?(key)
    end

    def rules
      @rules ||= LicenseRules.from_meta(meta)
    end

    def inspect
      "#<Licensee::License key=#{key}>"
    end

    private

    # Raw content of license file, including YAML front matter
    def raw_content
      return if pseudo_license?
      unless File.exist?(path)
        raise Licensee::InvalidLicense, "'#{key}' is not a valid license key"
      end
      @raw_content ||= File.read(path, encoding: 'utf-8')
    end

    def parts
      return unless raw_content
      @parts ||= raw_content.match(/\A(---\n.*\n---\n+)?(.*)/m).to_a
    end

    def yaml
      @yaml ||= parts[1] if parts
    end
  end
end
