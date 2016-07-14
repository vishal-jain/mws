module Mws::Apis::Feeds

  class Api

    attr_reader :products, :images, :prices, :shipping, :inventory,
      :product_relationships, :order_acknowledgement, :order_fulfillment

    def initialize(connection, defaults={})
      raise Mws::Errors::ValidationError, 'A connection is required.' if connection.nil?
      @connection = connection
      defaults[:version] ||= '2009-01-01'
      @defaults = defaults

      @products = self.for :product
      @images = self.for :image
      @prices = self.for :price
      @shipping = self.for :override
      @inventory = self.for :inventory
      @product_relationships = self.for :product_relationship
      @order_acknowledgement = self.for :order_acknowledgement
      @order_fulfillment = self.for :order_fulfillment
    end

    def get(id)
      node = @connection.get '/', { feed_submission_id: id }, @defaults.merge(
        action: 'GetFeedSubmissionResult',
        xpath: 'AmazonEnvelope/Message'
      )
      SubmissionResult.from_xml node
    end

    def submit(body, params)
      params[:feed_type] = Feed::Type.for(params[:feed_type]).val
      doc = @connection.post '/', params, body, @defaults.merge(action: 'SubmitFeed')
      SubmissionInfo.from_xml(doc.xpath('FeedSubmissionInfo').first, body)
    end

    def cancel(options={})

    end

    def list(params={})
      params[:feed_submission_id] ||= params.delete(:ids) || [ params.delete(:id) ].flatten.compact
      doc = @connection.get('/', params, @defaults.merge(action: 'GetFeedSubmissionList'))
      doc.xpath('FeedSubmissionInfo').map do | node |
        SubmissionInfo.from_xml node
      end
    end

    def count()
      @connection.get('/', {}, @defaults.merge(action: 'GetFeedSubmissionCount')).xpath('Count').first.text.to_i
    end

    def for(type)
      TargetedApi.new self, @connection.merchant, type
    end

  end

  class TargetedApi

    def initialize(feeds, merchant, type)
      @feeds = feeds
      @merchant = merchant
      @message_type = Feed::Message::Type.for(type)
      @feed_type = Feed::Type.for(type)
    end

    def add(*resources)
      submit resources, :update, true
    end

    def update(*resources)
      submit resources, :update
    end

    def patch(*resources)
      raise 'Operation Type not supported.' unless @feed_type == Feed::Type.PRODUCT
      submit resources, :partial_update
    end

    def delete(*resources)
      submit resources, :delete
    end

    def send_request(*resources)
      messages = []
      feed = Feed.new @merchant, @message_type do
        resources.each do | resource |
          messages << message(resource, nil)
        end
      end

      Transaction.new @feeds.submit(feed.to_xml, feed_type: @feed_type)
    end

    def submit(resources, def_operation_type=nil, purge_and_replace=false)
      messages = []
      feed = Feed.new @merchant, @message_type do
        resources.each do | resource |
          operation_type = def_operation_type
          if resource.respond_to?(:operation_type) and resource.operation_type
            operation_type = resource.operation_type
          end
          messages << message(resource, operation_type)
        end
      end

      Transaction.new @feeds.submit(feed.to_xml, feed_type: @feed_type, purge_and_replace: purge_and_replace) do
        messages.each do | message |
          item message.id, message.resource.sku, message.operation_type,
            message.resource.respond_to?(:type) ? message.resource.type : nil
        end
      end
    end

  end

end
