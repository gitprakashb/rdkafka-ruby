module Rdkafka
  class Consumer
    # A list of topics with their partition information
    class TopicPartitionList
      include Enumerable

      # Create a topic partition list.
      #
      # @param data [Hash<String => [nil,Partition]>] The topic and partion data or nil to create an empty list
      #
      # @return [TopicPartitionList]
      def initialize(data=nil)
        @data = data || {}
      end

      # Number of items in the list
      # @return [Integer]
      def count
        i = 0
        @data.each do |_topic, partitions|
          if partitions
            i += partitions.count
          else
            i+= 1
          end
        end
        i
      end

      # Whether this list is empty
      # @return [Boolean]
      def empty?
        @data.empty?
      end

      # Whether the specified topic is in this list or not
      def has_key?(topic)
        @data.has_key?(topic)
      end

      # Returns the partitions for the specified topic. Returns `nil` if the
      # topic is not in the list.
      #
      # @return [Array<Partition>,nil]
      def [](topic)
        @data[topic]
      end

      # Iterates through each topic, yielding the topic name, and an array of
      # partitions within each topic.
      #
      # @yieldparam topic [String] Name of the topic
      # @yieldparam partitions [Array<Partition>] Partitions
      def each(&block)
        @data.each(&block)
      end

      # Add a topic with optionally partitions to the list.
      # Calling this method multiple times for the same topic will overwrite the previous configuraton.
      #
      # @example Add a topic with unassigned partitions
      #   tpl.add_topic("topic")
      #
      # @example Add a topic with assigned partitions
      #   tpl.add_topic("topic", (0..8))
      #
      # @example Add a topic with all topics up to a count
      #   tpl.add_topic("topic", 9)
      #
      # @param topic [String] The topic's name
      # @param partitions [Array<Integer>, Range<Integer>, Integer] The topic's partitions or partition count
      #
      # @return [nil]
      def add_topic(topic, partitions=nil)
        if partitions.nil?
          @data[topic.to_s] = nil
        else
          if partitions.is_a? Integer
            partitions = (0..partitions - 1)
          end
          @data[topic.to_s] = partitions.map { |p| Partition.new(p, nil, 0) }
        end
      end

      # Add a topic with partitions and offsets set to the list
      # Calling this method multiple times for the same topic will overwrite the previous configuraton.
      #
      # @param topic [String] The topic's name
      # @param partitions_with_offsets [Hash<Integer, Integer>] The topic's partitions and offsets
      #
      # @return [nil]
      def add_topic_and_partitions_with_offsets(topic, partitions_with_offsets)
        @data[topic.to_s] = partitions_with_offsets.map { |p, o| Partition.new(p, o) }
      end

      # Return a `Hash` with the topics as keys and and an array of partition information as the value if present.
      #
      # @return [Hash<String, [Array<Partition>, nil]>]
      def to_h
        @data
      end

      # Human readable representation of this list.
      # @return [String]
      def to_s
        "<TopicPartitionList: #{to_h}>"
      end

      def ==(other)
        self.to_h == other.to_h
      end

      # Create a new topic partition list based of a native one.
      #
      # @param pointer [FFI::Pointer] Optional pointer to an existing native list. Its contents will be copied and afterwards it will be destroyed.
      #
      # @return [TopicPartitionList]
      #
      # @private
      def self.from_native_tpl(pointer, destroy = true)
        # Data to be moved into the tpl
        data = {}

        # Create struct and copy its contents
        native_tpl = Rdkafka::Bindings::TopicPartitionList.new(pointer)
        native_tpl[:cnt].times do |i|
          ptr = native_tpl[:elems] + (i * Rdkafka::Bindings::TopicPartition.size)
          elem = Rdkafka::Bindings::TopicPartition.new(ptr)
          if elem[:partition] == -1
            data[elem[:topic]] = nil
          else
            partitions = data[elem[:topic]] || []
            offset = if elem[:offset] == -1001
                       nil
                     else
                       elem[:offset]
                     end
            partition = Partition.new(elem[:partition], offset, elem[:err])
            partitions.push(partition)
            data[elem[:topic]] = partitions
          end
        end

        # Return the created object
        TopicPartitionList.new(data)
      ensure
        # Destroy the tpl
        if destroy
          Rdkafka::Bindings.rd_kafka_topic_partition_list_destroy(pointer)
        end
      end

      # Create a native tpl with the contents of this object added
      #
      # @private
      def to_native_tpl
        Rdkafka::Bindings.rd_kafka_topic_partition_list_new(count).tap do |tpl|
          @data.each do |topic, partitions|
            if partitions
              partitions.each do |p|
                Rdkafka::Bindings.rd_kafka_topic_partition_list_add(
                  tpl,
                  topic,
                  p.partition
                )
                if p.offset
                  Rdkafka::Bindings.rd_kafka_topic_partition_list_set_offset(
                    tpl,
                    topic,
                    p.partition,
                    p.offset
                  )
                end
              end
            else
              Rdkafka::Bindings.rd_kafka_topic_partition_list_add(
                tpl,
                topic,
                -1
              )
            end
          end
        end
      end
    end
  end
end
