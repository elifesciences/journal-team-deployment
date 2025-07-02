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
      logger.info 'prefix: ' << identifier[0..2] << ' is HTTPSource ' << 'https://s3-external-1.amazonaws.com/prod-elife-published/articles/'
      return 'https://s3-external-1.amazonaws.com/prod-elife-published/articles/' <<  identifier[4..-1]
    end
    if identifier.start_with?('digests:') or identifier.start_with?('digests/') then
      logger.info 'prefix: ' << identifier[0..6] << ' is HTTPSource ' << 'https://s3-external-1.amazonaws.com/prod-elife-published/digests/'
      return 'https://s3-external-1.amazonaws.com/prod-elife-published/digests/' <<  identifier[8..-1]
    end
    if identifier.start_with?('journal-cms:') or identifier.start_with?('journal-cms/') then
      logger.info 'prefix: ' << identifier[0..10] << ' is HTTPSource ' << 'https://prod--journal-cms.elifesciences.org/sites/default/files/iiif/'
      return 'https://prod--journal-cms.elifesciences.org/sites/default/files/iiif/' <<  identifier[12..-1]
    end
    nil
  end

  def metadata(options = {})
  end
  def redactions(options = {})
    []
  end
end
