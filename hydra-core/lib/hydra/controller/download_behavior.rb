module Hydra
  module Controller
    module DownloadBehavior
      extend ActiveSupport::Concern

      included do
        before_filter :load_asset
        before_filter :load_datastream
      end
      
      # Responds to http requests to show the datastream
      def show
        if can_download?
          # we can now examine asset and determine if we should send_content, or some other action.
          send_content (asset)
        else 
          logger.info "Can not read #{params['id']}"
          raise Hydra::AccessDenied.new("You do not have sufficient access privileges to read this document, which has been marked private.", :read, params[:id])
        end
      end

      protected

      def load_asset
        @asset = ActiveFedora::Base.find(params[:id], :cast=>true)
      end

      def load_datastream
        @ds = datastream_to_show
      end

      def asset
        @asset
      end

      def datastream
        @ds
      end

      # Override this method to enforce access controls. By default it allows
      # any datastream on an object the current user has read access to.
      # @return [Boolean] can the curent user view this object/datastream
      def can_download?
        can? :read, datastream.pid
      end 


      # Override this method to change which datastream is shown.
      # Loads the datastream specified by the HTTP parameter `:datastream_id`. 
      # If this object does not have a datastream by that name, return the default datastream
      # as returned by {#default_content_ds}
      # @return [ActiveFedora::Datastream] the datastr
      def datastream_to_show
        ds = asset.datastreams[params[:datastream_id]] if params.has_key?(:datastream_id)
        ds = default_content_ds if ds.nil?
        ds
      end
      
      # Handle the HTTP show request
      def send_content(asset)
        response.headers['Accept-Ranges'] = 'bytes'

        if request.head?
          content_head(datastream)
        elsif request.headers["Range"]
          send_range(datastream)
        else
          send_file_headers! content_options
          self.response_body = datastream.stream
        end
      end

      # Create some headers for the datastream
      def content_options
        {disposition: 'inline', type: datastream.mimeType, filename: datastream_name}
      end

      # Override this if you'd like a different filename
      # @return [String] the filename
      def datastream_name
        params[:filename] || asset.label
      end


      # render an HTTP HEAD response
      def content_head
        response.headers['Content-Length'] = datastream.dsSize
        response.headers['Content-Type'] = datastream.mimeType
        head :ok
      end
      

      # render an HTTP Range response
      def send_range
        _, range = request.headers["Range"].split('bytes=')
        from, to = range.split('-').map(&:to_i)
        to = datastream.dsSize - 1 unless to
        length = to - from + 1
        response.headers['Content-Range'] = "bytes #{from}-#{to}/#{datastream.dsSize}"
        response.headers['Content-Length'] = "#{length}"
        self.status = 206
        send_file_headers! content_options
        self.response_body = datastream.stream(from, length)
      end
      
      private 
      
      def default_content_ds
        ActiveFedora::ContentModel.known_models_for(asset).each do |model_class|
          return model_class.default_content_ds if model_class.respond_to?(:default_content_ds)
        end
        if asset.datastreams.keys.include?(DownloadsController.default_content_dsid)
          return asset.datastreams[DownloadsController.default_content_dsid]
        end
      end
      
      module ClassMethods
        def default_content_dsid
          "content"
        end
      end
    end
  end
end

