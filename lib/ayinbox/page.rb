# frozen_string_literal: true

module Ayinbox
  # One page of a `data` + `pagination` list. Rows are Hashes with string keys.
  class Page
    include Enumerable

    attr_reader :data, :next_cursor, :total, :raw

    def initialize(raw, fetch_next)
      @raw = raw.is_a?(Hash) ? raw : {}
      @data = @raw["data"].is_a?(Array) ? @raw["data"] : []
      pagination = @raw["pagination"].is_a?(Hash) ? @raw["pagination"] : {}
      cursor = pagination["next_cursor"]
      @next_cursor = cursor.is_a?(String) && !cursor.empty? ? cursor : nil
      @has_more = pagination["has_more"] == true
      @total = pagination["total"]
      @fetch_next = fetch_next
    end

    def has_more?
      @has_more && !@next_cursor.nil?
    end

    # Reads a top-level field other than data and pagination, such as "counts".
    def [](key)
      @raw[key.to_s]
    end

    # Iterates the rows of this page only.
    def each(&block)
      return enum_for(:each) unless block

      @data.each(&block)
    end

    # Fetches the following page, or nil on the last one.
    def next_page
      has_more? ? @fetch_next.call(@next_cursor) : nil
    end

    # Yields every row of this page and every page after it, fetching lazily.
    def auto_paging_each(&block)
      return enum_for(:auto_paging_each) unless block

      page = self
      while page
        page.data.each(&block)
        page = page.next_page
      end
    end
  end
end
