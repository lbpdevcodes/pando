# frozen_string_literal: true

RSpec.describe Pando::TextInput do
  it "clears the value and homes the cursor with clear!" do
    input = Pando::TextInput.new(value: "paste an invite code")

    input.clear!

    expect(input.value).to eq("")
    expect(input.cursor).to eq(0)
  end

  it "still types after a clear" do
    input = Pando::TextInput.new(value: "old")
    input.clear!

    event = Struct.new(:char).new("a")
    input.handle_key(event)

    expect(input.value).to eq("a")
  end
end
