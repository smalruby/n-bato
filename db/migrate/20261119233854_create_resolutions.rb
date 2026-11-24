class CreateResolutions < ActiveRecord::Migration[8.1]
  def change
    create_table :resolutions do |t|
      t.string :body, null: false # general_meeting / board
      t.string :title, null: false
      t.date :proposed_on, null: false
      t.references :proposer, null: false, foreign_key: {to_table: :people}
      t.string :voting_method, null: false, default: "written" # written(みなし決議) / meeting
      t.date :held_on
      t.string :place, null: false, default: ""
      t.text :note, null: false, default: ""
      t.references :minutes_author, foreign_key: {to_table: :people}
      t.timestamps
    end
  end
end
