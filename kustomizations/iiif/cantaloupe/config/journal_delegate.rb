require 'java'

class CustomDelegate
  attr_accessor :context

  def source(options = {})
    logger = Java::edu.illinois.library.cantaloupe.delegate.Logger

    identifier = context['identifier']
    logger.info 'identifier: ' << identifier
    'HttpSource'
  end

  def pre_authorize(options = {})
    true
  end

  def authorize(options = {})
    true
  end

  def httpsource_resource_info(options = {})
    logger = Java::edu.illinois.library.cantaloupe.delegate.Logger

    # replace double encoded slashes with a /
    identifier = context['identifier'].gsub('%252F', '/')
    logger.info 'identifier: ' << identifier

    if identifier.start_with?('lax:') or identifier.start_with?('lax/') then
      logger.info 'prefix: ' << identifier[0..2] << ' is HTTPSource ' << '${lax_prefix_url}'
      return '${lax_prefix_url}' <<  identifier[4..-1]
    end
    if identifier.start_with?('digests:') or identifier.start_with?('digests/') then
      logger.info 'prefix: ' << identifier[0..6] << ' is HTTPSource ' << '${digests_prefix_url}'
      return '${digests_prefix_url}' <<  identifier[8..-1]
    end
    if identifier.start_with?('journal-cms:') or identifier.start_with?('journal-cms/') then
      logger.info 'prefix: ' << identifier[0..10] << ' is HTTPSource ' << '${journal_cms_prefix_url}'
      return '${journal_cms_prefix_url}' <<  identifier[12..-1]
    end

    if identifier.start_with?('loris-') then
      logger.info 'loris prefix is HTTPSource http://localhost:5004'
      return 'http://localhost:5004/' <<  identifier[6..-1] << '/full/full/0/default.tif'
    end

    nil
  end

  def metadata(options = {})
  end
  def redactions(options = {})
    []
  end
end
