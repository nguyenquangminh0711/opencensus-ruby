# Copyright 2017 OpenCensus Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module OpenCensus
  module Trace
    ##
    # Span represents a single span within a request trace.
    #
    class SpanBuilder
      ## The type of a message event or link is unknown.
      TYPE_UNSPECIFIED = :TYPE_UNSPECIFIED

      ## Indicates a sent message.
      SENT = :SENT

      ## Indicates a received message.
      RECEIVED = :RECEIVED

      ## The linked span is a child of the current span.
      CHILD_LINKED_SPAN = :CHILD_LINKED_SPAN

      ## The linked span is a parent of the current span.
      PARENT_LINKED_SPAN = :PARENT_LINKED_SPAN

      ##
      # The context that can build children of this span.
      #
      # @return [SpanContext]
      #
      attr_reader :context

      ##
      # The trace ID, as a 32-character hex string.
      #
      # @return [String]
      #
      def trace_id
        context.trace_id
      end

      ##
      # The span ID, as a 16-character hex string.
      #
      # @return [String]
      #
      def span_id
        context.span_id
      end

      ##
      # The span ID of the parent, as a 16-character hex string, or the empty
      # string if this is a root span.
      #
      # @return [String]
      #
      def parent_span_id
        context.parent.span_id
      end

      ##
      # Sampling decision for this span. Generally this field is set when the
      # span is first created. However, you can also change it after the fact.
      #
      # @return [boolean]
      #
      attr_accessor :sampled

      ##
      # A description of the span's operation.
      #
      # For example, the name can be a qualified method name or a file name and
      # a line number where the operation is called. A best practice is to use
      # the same display name at the same call point in an application.
      # This makes it easier to correlate spans in different traces.
      #
      # This field is required.
      #
      # @return [String, TruncatableString]
      #
      attr_accessor :name

      ##
      # The start time of the span. On the client side, this is the time kept
      # by the local machine where the span execution starts. On the server
      # side, this is the time when the server's application handler starts
      # running.
      #
      # In Ruby, this is represented by a Time object in UTC, or `nil` if the
      # starting timestamp has not yet been populated.
      #
      # @return [Time, nil]
      #
      attr_accessor :start_time

      ##
      # The end time of the span. On the client side, this is the time kept by
      # the local machine where the span execution ends. On the server side,
      # this is the time when the server application handler stops running.
      #
      # In Ruby, this is represented by a Time object in UTC, or `nil` if the
      # starting timestamp has not yet been populated.
      #
      # @return [Time, nil]
      #
      attr_accessor :end_time

      ##
      # Whether this span is finished (i.e. has both a start and end time)
      #
      # @return [boolean]
      #
      def finished?
        !start_time.nil? && !end_time.nil?
      end

      ##
      # Start this span by setting the start time to the current time.
      # Raises an exception if the start time is already set.
      #
      def start!
        raise "Span already started" unless start_time.nil?
        @start_time = Time.now.utc
        self
      end

      ##
      # Finish this span by setting the end time to the current time.
      # Raises an exception if the start time is not yet set, or the end time
      # is already set.
      #
      def finish!
        raise "Span not yet started" if start_time.nil?
        raise "Span already finished" unless end_time.nil?
        @end_time = Time.now.utc
        self
      end

      ##
      # Add an attribute to this span.
      #
      # Attributes are key-value pairs representing properties of this span.
      # You could, for example, add an attribute indicating the URL for the
      # request being handled, the user-agent, the database query being run,
      # the ID of the logged-in user, or any other relevant information.
      #
      # Keys must be strings.
      # Values may be String, TruncatableString, Integer, or Boolean.
      # The valid integer range is 64-bit signed `(-2^63..2^63-1)`.
      #
      # @param [String, Symbol] key
      # @param [String, TruncatableString, Integer, boolean] value
      #
      def put_attribute key, value
        @attributes[key.to_s] = value
        self
      end

      ##
      # Add an event annotation with a timestamp.
      #
      # @param [String] description Description of the event
      # @param [Hash] attributes Key-value pairs providing additional
      #     properties of the event. Keys must be strings, and values are
      #     restricted to the same types as attributes (see #put_attribute).
      # @param [Time, nil] time Timestamp of the event. Optional, defaults to
      #     the current time.
      #
      def put_annotation description, attributes = {}, time: nil
        time ||= Time.now.utc
        annotation = AnnotationBuilder.new time, description, attributes
        @annotations << annotation
        self
      end

      ##
      # Add an event describing a message sent/received between spans.
      #
      # @param [Symbol] type The type of MessageEvent. Indicates whether the
      #     message was sent or received. Valid values are `SpanBuilder::SENT`
      #     `SpanBuilder::RECEIVED`, and `SpanBuilder::TYPE_UNSPECIFIED`.
      # @param [Integer] id An identifier for the MessageEvent's message that
      #     can be used to match SENT and RECEIVED events. For example, this
      #     field could represent a sequence ID for a streaming RPC. It is
      #     recommended to be unique within a Span. The valid range is 64-bit
      #     unsigned `(0..2^64-1)`
      # @param [Integer] uncompressed_size The number of uncompressed bytes
      #     sent or received.
      # @param [Integer, nil] compressed_size The number of compressed bytes
      #     sent or received. Optional.
      # @param [Time, nil] time Timestamp of the event. Optional, defaults to
      #     the current time.
      #
      def put_message_event type, id, uncompressed_size,
                            compressed_size: nil, time: nil
        time ||= Time.now.utc
        message_event =
          MessageEventBuilder.new time, type, id, uncompressed_size,
                                  compressed_size
        @message_events << message_event
        self
      end

      ##
      # Add a pointer from the current span to another span, which may be in
      # the same trace or in a different trace. For example, this can be used
      # in batching operations, where a single batch handler processes multiple
      # requests from different traces or when the handler receives a request
      # from a different project.
      #
      # @param [String] trace_id The unique identifier for a trace. A 16-byte
      #     array expressed as 32 hex digits.
      # @param [String] span_id The unique identifier for a span within a trace.
      #     An 8-byte array expressed as 16 hex digits.
      # @param [Symbol] type The relationship of the current span relative to
      #     the linked span. Valid values are `SpanBuilder::CHILD_LINKED_SPAN`,
      #     `SpanBuilder::PARENT_LINKED_SPAN`, and
      #     `SpanBuilder::TYPE_UNSPECIFIED`.
      # @param [String] attributes Key-value pairs providing additional
      #     properties of the link. Keys must be strings, and values are
      #     restricted to the same types as attributes (see #put_attribute).
      #
      def put_link trace_id, span_id, type, attributes = {}
        link = LinkBuilder.new trace_id, span_id, type, attributes
        @links << link
        self
      end

      ##
      # Set the optional final status for the span.
      #
      # @param [Integer] code Status code as a 32-bit signed integer
      # @param [String] message A developer-facing error message, which should
      #     be in English.
      def set_status code, message = ""
        @status_code = code
        @status_message = message
        self
      end

      ##
      # Set the stack trace for this span.
      # You may call this in one of three ways:
      #
      # *   Pass in no argument to use the caller's stack trace.
      # *   Pass in an integer to use the caller's stack trace, but skip
      #     additional stack frames.
      # *   Pass in an explicit array of Thread::Backtrace::Location as
      #     returned from Kernel#caller_locations
      #
      # @param [Array<Thread::Backtrace::Location>, Integer] stack_trace
      #
      def update_stack_trace stack_trace = 0
        @stack_trace =
          case stack_trace
          when Integer
            caller_locations(stack_trace + 2)
          when Array
            stack_trace
          else
            raise ArgumentError, "Unknown stack trace type: #{stack_trace}"
          end
        self
      end

      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/AbcSize

      ##
      # Return a read-only version of this span
      #
      # @return [Span]
      #
      def to_span max_attributes: nil,
                  max_stack_frames: nil,
                  max_annotations: nil,
                  max_message_events: nil,
                  max_links: nil,
                  max_string_length: nil,
                  same_process_as_parent_span: nil

        raise "Span must have start_time" unless @start_time
        raise "Span must have end_time" unless @end_time

        builder = PieceBuilder.new max_attributes: max_attributes,
                                   max_stack_frames: max_stack_frames,
                                   max_annotations: max_annotations,
                                   max_message_events: max_message_events,
                                   max_links: max_links,
                                   max_string_length: max_string_length

        built_name = builder.truncatable_string name
        built_attributes = builder.convert_attributes @attributes
        dropped_attributes_count = @attributes.size - built_attributes.size
        built_stack_trace = builder.truncate_stack_trace @stack_trace
        dropped_frames_count = @stack_trace.size - built_stack_trace.size
        built_annotations = builder.convert_annotations @annotations
        dropped_annotations_count = @annotations.size - built_annotations.size
        built_message_events = builder.convert_message_events @message_events
        dropped_message_events_count =
          @message_events.size - built_message_events.size
        built_links = builder.convert_links @links
        dropped_links_count = @links.size - built_links.size
        built_status = builder.convert_status @status_code, @status_message

        Span.new trace_id, span_id, built_name, @start_time, @end_time,
                 parent_span_id: parent_span_id,
                 attributes: built_attributes,
                 dropped_attributes_count: dropped_attributes_count,
                 stack_trace: built_stack_trace,
                 dropped_frames_count: dropped_frames_count,
                 time_events: built_annotations + built_message_events,
                 dropped_annotations_count: dropped_annotations_count,
                 dropped_message_events_count: dropped_message_events_count,
                 links: built_links,
                 dropped_links_count: dropped_links_count,
                 status: built_status,
                 same_process_as_parent_span: same_process_as_parent_span
      end

      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/AbcSize

      ##
      # Initializer.
      #
      # @private
      #
      def initialize span_context, sampled, skip_frames: 0
        @context = span_context
        @sampled = sampled
        @name = ""
        @start_time = nil
        @end_time = nil
        @attributes = {}
        @annotations = []
        @message_events = []
        @links = []
        @status_code = nil
        @status_message = nil
        @stack_trace = caller_locations(skip_frames + 2)
      end

      ##
      # Internal structure for holding annotations.
      #
      # @private
      #
      AnnotationBuilder = Struct.new :time, :description, :attributes

      ##
      # Internal structure for holding message events.
      #
      # @private
      #
      MessageEventBuilder = Struct.new :time, :type, :id, :uncompressed_size,
                                       :compressed_size
      ##
      # Internal structure for holding links.
      #
      # @private
      #
      LinkBuilder = Struct.new :trace_id, :span_id, :type, :attributes

      ##
      # Internal class that builds pieces of a span, honoring limits.
      #
      # @private
      #
      class PieceBuilder
        ##
        # Minimum value of int64
        # @private
        #
        MIN_INT = -0x10000000000000000

        ##
        # Maximum value of int64
        # @private
        #
        MAX_INT = 0xffffffffffffffff

        ##
        # Initializer for PieceBuilder
        # @private
        #
        def initialize max_attributes: nil,
                       max_stack_frames: nil,
                       max_annotations: nil,
                       max_message_events: nil,
                       max_links: nil,
                       max_string_length: nil
          config = OpenCensus::Trace.config
          @max_attributes = max_attributes || config.default_max_attributes
          @max_stack_frames =
            max_stack_frames || config.default_max_stack_frames
          @max_annotations = max_annotations || config.default_max_annotations
          @max_message_events =
            max_message_events || config.default_max_message_events
          @max_links = max_links || config.default_max_links
          @max_string_length =
            max_string_length || config.default_max_string_length
        end

        ##
        # Build a canonical attributes hash, truncating if necessary
        # @private
        #
        def convert_attributes attrs
          result = {}
          attrs.each do |k, v|
            break if @max_attributes != 0 && result.size >= @max_attributes
            result[k.to_s] =
              case v
              when Integer
                if v >= MIN_INT && v <= MAX_INT
                  v
                else
                  truncatable_string v.to_s
                end
              when true, false, TruncatableString
                v
              else
                truncatable_string v.to_s
              end
          end
          result
        end

        ##
        # Build a canonical stack trace, truncating if necessary
        # @private
        #
        def truncate_stack_trace raw_trace
          if @max_stack_frames.zero? || raw_trace.size <= @max_stack_frames
            raw_trace
          else
            raw_trace[0, @max_stack_frames]
          end
        end

        ##
        # Build a canonical annotations list, truncating if necessary
        # @private
        #
        def convert_annotations raw_annotations
          result = []
          raw_annotations.each do |ann|
            break if @max_annotations != 0 && result.size >= @max_annotations
            attrs = convert_attributes ann.attributes
            dropped_attributes_count = ann.attributes.size - attrs.size
            result <<
              OpenCensus::Trace::Annotation.new(
                truncatable_string(ann.description),
                attributes: attrs,
                dropped_attributes_count: dropped_attributes_count,
                time: ann.time
              )
          end
          result
        end

        ##
        # Build a canonical message list, truncating if necessary
        # @private
        #
        def convert_message_events raw_message_events
          result = []
          raw_message_events.each do |evt|
            break if @max_message_events != 0 &&
                     result.size >= @max_message_events
            result <<
              OpenCensus::Trace::MessageEvent.new(
                evt.type,
                evt.id,
                evt.uncompressed_size,
                compressed_size: evt.compressed_size,
                time: evt.time
              )
          end
          result
        end

        ##
        # Build a canonical links list, truncating if necessary
        # @private
        #
        def convert_links raw_links
          result = []
          raw_links.each do |lnk|
            break if @max_links != 0 && result.size >= @max_links
            attrs = convert_attributes lnk.attributes
            dropped_attributes_count = lnk.attributes.size - attrs.size
            result <<
              OpenCensus::Trace::Link.new(
                lnk.trace_id,
                lnk.span_id,
                type: lnk.type,
                attributes: attrs,
                dropped_attributes_count: dropped_attributes_count
              )
          end
          result
        end

        ##
        # Build a canonical status object
        # @private
        #
        def convert_status status_code, status_message
          return nil unless status_code || status_message
          Status.new status_code.to_i, status_message.to_s
        end

        ##
        # Build a truncatable string
        # @private
        #
        def truncatable_string str
          return str if str.is_a? TruncatableString
          orig_str = str.encode Encoding::UTF_8,
                                invalid: :replace,
                                undef: :replace
          if @max_string_length != 0 && @max_string_length < str.bytesize
            str = truncate_str orig_str, @max_string_length
            truncated_bytes = orig_str.bytesize - str.bytesize
            TruncatableString.new str, truncated_byte_count: truncated_bytes
          else
            TruncatableString.new orig_str
          end
        end

        private

        def truncate_str str, target_bytes
          tstr = str.dup
          tstr.force_encoding Encoding::ASCII_8BIT
          tstr.slice! target_bytes..-1
          tstr.force_encoding Encoding::UTF_8
          until tstr.valid_encoding?
            tstr.force_encoding Encoding::ASCII_8BIT
            tstr.slice!(-1..-1)
            tstr.force_encoding Encoding::UTF_8
          end
          tstr
        end
      end
    end
  end
end
