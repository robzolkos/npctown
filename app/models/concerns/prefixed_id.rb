# frozen_string_literal: true

# PrefixedId provides Stripe-style prefixed KSUID generation for ActiveRecord models.
#
# Usage:
#   class Project < ApplicationRecord
#     include PrefixedId
#     has_prefixed_id prefix: "proj"
#   end
#
# This will generate IDs like: proj_0ujsswThIGTUYm2K8FjOOfXtY1K
#
# The ID format is: {prefix}_{ksuid}
# - Prefix: 3-5 character identifier for the model type
# - KSUID: 27-character K-Sortable Unique ID (time-ordered, distributed-safe)
#
# Benefits:
# - IDs are immediately recognizable by type (proj_ vs scen_ vs run_)
# - Sortable by creation time (KSUID timestamp component)
# - Safe for distributed generation (no coordination needed)
# - URL-safe (alphanumeric only)
#
module PrefixedId
  extend ActiveSupport::Concern

  # Registry of all prefixes to their model classes
  PREFIXES = {}

  class_methods do
    # Configure a model to use prefixed KSUIDs
    #
    # @param prefix [String] The prefix for this model (e.g., "proj", "scen", "run")
    #
    def has_prefixed_id(prefix:)
      raise ArgumentError, "Prefix must be a string" unless prefix.is_a?(String)
      raise ArgumentError, "Prefix must be 2-5 characters" unless prefix.length.between?(2, 5)
      raise ArgumentError, "Prefix must be lowercase alphanumeric" unless prefix.match?(/\A[a-z0-9]+\z/)

      @id_prefix = prefix.freeze
      PrefixedId::PREFIXES[prefix] = self

      before_create :generate_prefixed_id
    end

    # Get the prefix for this model
    def id_prefix
      @id_prefix
    end

    # Generate a new prefixed ID without persisting
    #
    # @return [String] A new prefixed ID
    #
    def generate_id
      "#{@id_prefix}_#{KSUID.new}"
    end

    # Find a model by its prefixed ID, validating the prefix matches
    #
    # @param id [String] The prefixed ID to find
    # @return [ApplicationRecord, nil] The found record or nil
    #
    def find_by_prefixed_id(id)
      return nil unless id.to_s.start_with?("#{@id_prefix}_")

      find_by(id: id)
    end

    # Find a model by its prefixed ID, raising if not found
    #
    # @param id [String] The prefixed ID to find
    # @return [ApplicationRecord] The found record
    # @raise [ActiveRecord::RecordNotFound] If the record is not found
    #
    def find_by_prefixed_id!(id)
      find_by_prefixed_id(id) || raise(ActiveRecord::RecordNotFound, "Couldn't find #{name} with id=#{id}")
    end
  end

  # Parse a prefixed ID and return its components
  #
  # @param id [String] The prefixed ID to parse
  # @return [Hash, nil] Hash with :prefix and :ksuid keys, or nil if invalid
  #
  def self.parse(id)
    return nil unless id.is_a?(String)

    match = id.match(/\A([a-z0-9]{2,5})_([A-Za-z0-9]{27})\z/)
    return nil unless match

    { prefix: match[1], ksuid: match[2] }
  end

  # Check if a string is a valid prefixed ID format
  #
  # @param id [String] The string to check
  # @return [Boolean] True if valid format
  #
  def self.valid?(id)
    parse(id).present?
  end

  # Get the model class for a given prefix
  #
  # @param prefix [String] The prefix to look up
  # @return [Class, nil] The model class or nil
  #
  def self.model_for_prefix(prefix)
    PREFIXES[prefix]
  end

  private

  def generate_prefixed_id
    self.id ||= self.class.generate_id
  end
end
