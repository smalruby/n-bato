class FilingDestinationSearchJob < ApplicationJob
  queue_as :default

  def perform(search) = search.run!
end
