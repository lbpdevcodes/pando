# frozen_string_literal: true

RSpec.describe Pando::TextArea do
  it "clears the value and homes the cursor with clear!" do
    area = Pando::TextArea.new(value: "line one\nline two")

    area.clear!

    expect(area.value).to eq("")
    expect(area.cursor).to eq(0)
  end

  it "restores a draft with value=" do
    area = Pando::TextArea.new

    area.value = "saved draft"

    expect(area.value).to eq("saved draft")
    expect(area.cursor).to eq("saved draft".length)
  end

  it "refreshes placeholder and width per render" do
    area = Pando::TextArea.new(placeholder: "Message Alice…", width: 40)

    area.placeholder = "Message Zoe…"
    area.width = 60

    expect(area.placeholder).to eq("Message Zoe…")
    expect(area.width).to eq(60)
  end
end
