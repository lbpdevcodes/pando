# frozen_string_literal: true

RSpec.describe Pando::Graphics::Cache do
  let(:kitty_terminal) { Charming::Image::Terminal.new(env: {"KITTY_WINDOW_ID" => "1"}) }
  let(:cache) { described_class.new(terminal: kitty_terminal) }

  def png_bytes(width: 4, height: 8)
    ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::WHITE).to_blob
  end

  it "builds a sized source once and returns the cached entry after" do
    built = 0
    entry = cache.fetch("a") do
      built += 1
      png_bytes
    end

    expect(entry[:source]).to be_a(Charming::Image::Source)
    expect(entry[:rows]).to be_between(1, Pando::Graphics::MAX_CELL_ROWS)
    again = cache.fetch("a") { raise "should not rebuild" }
    expect(again).to equal(entry)
    expect(built).to eq(1)
  end

  it "transmits once per source and releases on retain, re-arming retransmit" do
    entry = cache.fetch("a") { png_bytes }
    image = Charming::Components::Image.new(source: entry[:source], rows: entry[:rows],
      cols: entry[:cols])

    first = Charming::Escape.collecting { image.render }
    second = Charming::Escape.collecting { image.render }
    expect(first.length).to eq(1)
    expect(second).to be_empty

    releases = Charming::Escape.collecting { cache.retain([]) }
    expect(releases.sole.payload).to include("a=d")
    expect(entry[:source].transmitted?).to be(false)
  end

  it "caps resident sources, releasing the oldest" do
    releases = Charming::Escape.collecting do
      (Pando::Graphics::MAX_SOURCES + 2).times { |i| cache.fetch("img-#{i}") { png_bytes } }
    end

    expect(releases.length).to eq(2)
  end

  it "returns nil for bytes that are not a decodable PNG" do
    expect(cache.fetch("junk") { "not a png" }).to be_nil
  end
end
