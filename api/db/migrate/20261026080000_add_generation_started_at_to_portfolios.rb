# frozen_string_literal: true

# Records when a portfolio generation run started, so a run that never finishes
# (worker killed, deploy mid-job) can be recognised and retried instead of
# showing "generating" forever.
#
# Nullable on purpose: existing rows keep working untouched, and `change` makes
# this reversible (rollback simply drops the column).
class AddGenerationStartedAtToPortfolios < ActiveRecord::Migration[7.0]
  def change
    add_column :portfolios, :generation_started_at, :datetime
  end
end
